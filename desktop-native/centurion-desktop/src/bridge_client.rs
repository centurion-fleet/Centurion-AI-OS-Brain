//! Persistent `remote_bridge` daemon client (Unix socket).
//!
//! Replaces per-call `python -m centurion_cli.remote_bridge` spawns so Chat,
//! Settings, and Mission Deck share one warm Python process.

use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use crate::chat_page::{
    configure_bridge_command, parse_bridge_stdout, resolve_bridge_python, resolve_centurion_home,
};

static DAEMON: OnceLock<Mutex<DaemonState>> = OnceLock::new();
/// Recycle any pre-existing socket daemon once per Brain process so updates
/// to ``centurion_cli`` are loaded (orphans kept serving old code).
static RECYCLED_ORPHAN: AtomicBool = AtomicBool::new(false);

struct DaemonState {
    child: Option<Child>,
    socket_path: PathBuf,
}

fn daemon_lock() -> &'static Mutex<DaemonState> {
    DAEMON.get_or_init(|| {
        Mutex::new(DaemonState {
            child: None,
            socket_path: bridge_socket_path(),
        })
    })
}

/// Resolve `$CENTURION_HOME/run/bridge.sock` (or `CENTURION_BRIDGE_SOCKET`).
pub fn bridge_socket_path() -> PathBuf {
    if let Ok(p) = std::env::var("CENTURION_BRIDGE_SOCKET") {
        let trimmed = p.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }
    PathBuf::from(resolve_centurion_home())
        .join("run")
        .join("bridge.sock")
}

fn socket_connectable(path: &Path) -> bool {
    UnixStream::connect(path).is_ok()
}

fn wait_for_socket(path: &Path, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if socket_connectable(path) {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
    }
    socket_connectable(path)
}

fn spawn_daemon(socket_path: &Path) -> Result<Child, String> {
    if let Some(parent) = socket_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    // Stale sock from a crashed daemon blocks bind; remove if nothing is listening.
    if socket_path.exists() && !socket_connectable(socket_path) {
        let _ = std::fs::remove_file(socket_path);
    }

    let mut cmd = Command::new(resolve_bridge_python());
    cmd.args([
        "-m",
        "centurion_cli.remote_bridge",
        "--serve",
        "--socket",
        &socket_path.to_string_lossy(),
    ])
    .stdin(Stdio::null())
    .stdout(Stdio::null())
    .stderr(Stdio::null());
    configure_bridge_command(&mut cmd);
    cmd.env("CENTURION_BRIDGE_SOCKET", socket_path.as_os_str());
    cmd.spawn()
        .map_err(|e| format!("Could not start Centurion bridge daemon: {e}"))
}

fn stop_listener_on_socket(socket_path: &Path) {
    // Best-effort: remove the sock so the next bind wins. If something is still
    // connected we also try to shut it down by connecting and closing.
    if socket_connectable(socket_path) {
        if let Ok(stream) = UnixStream::connect(socket_path) {
            let _ = stream.shutdown(Shutdown::Both);
        }
        // Give an orphan a moment to exit after EOF; then force-remove the path.
        thread::sleep(Duration::from_millis(150));
    }
    if socket_path.exists() {
        let _ = std::fs::remove_file(socket_path);
    }
}

/// Ensure the bridge daemon is running and accepting connections.
pub fn ensure_bridge_daemon() -> Result<PathBuf, String> {
    let mut state = daemon_lock()
        .lock()
        .map_err(|_| "Bridge daemon lock poisoned.".to_owned())?;
    let path = state.socket_path.clone();

    // First call in this Brain process: drop any orphan daemon left from a
    // previous run so we do not keep talking to pre-update centurion_cli.
    let recycled = !RECYCLED_ORPHAN.swap(true, Ordering::SeqCst);
    if recycled {
        if let Some(mut child) = state.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
        drop(state);
        stop_listener_on_socket(&path);
        // Also try pkill of bridge serve for this socket (best-effort, Linux).
        let _ = Command::new("pkill")
            .args(["-f", "centurion_cli.remote_bridge.*--serve"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        thread::sleep(Duration::from_millis(250));
        stop_listener_on_socket(&path);
        state = daemon_lock()
            .lock()
            .map_err(|_| "Bridge daemon lock poisoned.".to_owned())?;
    }

    // After a recycle pass, never adopt a leftover listener — spawn ours.
    if !recycled && socket_connectable(&path) {
        return Ok(path);
    }
    if recycled && socket_connectable(&path) {
        stop_listener_on_socket(&path);
    }

    if let Some(child) = state.child.as_mut() {
        match child.try_wait() {
            Ok(Some(_)) | Err(_) => state.child = None,
            Ok(None) => {
                drop(state);
                if wait_for_socket(&path, Duration::from_secs(8)) {
                    return Ok(path);
                }
                return Err("Centurion bridge daemon is not accepting connections.".to_owned());
            }
        }
    }

    let child = spawn_daemon(&path)?;
    state.child = Some(child);
    drop(state);

    if wait_for_socket(&path, Duration::from_secs(12)) {
        Ok(path)
    } else {
        Err("Centurion bridge daemon did not become ready.".to_owned())
    }
}

/// Connect to the daemon (starts it if needed). One restart retry on failure.
pub fn connect_bridge() -> Result<UnixStream, String> {
    let path = ensure_bridge_daemon()?;
    match UnixStream::connect(&path) {
        Ok(stream) => Ok(stream),
        Err(_) => {
            {
                let mut state = daemon_lock()
                    .lock()
                    .map_err(|_| "Bridge daemon lock poisoned.".to_owned())?;
                if let Some(mut child) = state.child.take() {
                    let _ = child.kill();
                    let _ = child.wait();
                }
                if state.socket_path.exists() {
                    let _ = std::fs::remove_file(&state.socket_path);
                }
            }
            let path = ensure_bridge_daemon()?;
            UnixStream::connect(&path)
                .map_err(|e| format!("Could not connect to Centurion bridge: {e}"))
        }
    }
}

/// One request / one JSON response (Settings, soul_get, life_*, …).
pub fn bridge_request(action: &str, extra: Value) -> Result<Value, String> {
    let mut body = serde_json::Map::new();
    body.insert("id".to_owned(), Value::String("desktop-bridge".to_owned()));
    body.insert("action".to_owned(), Value::String(action.to_owned()));
    if let Value::Object(map) = extra {
        for (key, value) in map {
            body.insert(key, value);
        }
    }
    let payload = Value::Object(body).to_string();
    let mut stream = connect_bridge()?;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(120)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(30)));
    stream
        .write_all(payload.as_bytes())
        .and_then(|_| stream.write_all(b"\n"))
        .and_then(|_| stream.flush())
        .map_err(|e| format!("Could not talk to Centurion: {e}"))?;
    let _ = stream.shutdown(Shutdown::Write);

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .map_err(|e| format!("Centurion bridge failed: {e}"))?;
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Err("Centurion did not return a reply.".to_owned());
    }
    serde_json::from_str(trimmed).map_err(|e| format!("Invalid bridge response: {e}"))
}

/// Fallback: one-shot stdin spawn (tests / daemon unavailable).
pub fn bridge_request_oneshot(action: &str, extra: Value) -> Result<Value, String> {
    let mut body = serde_json::Map::new();
    body.insert("id".to_owned(), Value::String("desktop-chat".to_owned()));
    body.insert("action".to_owned(), Value::String(action.to_owned()));
    if let Value::Object(map) = extra {
        for (key, value) in map {
            body.insert(key, value);
        }
    }
    let payload = Value::Object(body).to_string();
    let mut child = Command::new(resolve_bridge_python());
    child
        .args(["-m", "centurion_cli.remote_bridge"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    configure_bridge_command(&mut child);
    let mut child = child
        .spawn()
        .map_err(|e| format!("Could not start Centurion chat bridge: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(payload.as_bytes())
            .map_err(|e| format!("Could not talk to Centurion: {e}"))?;
    }
    let output = child
        .wait_with_output()
        .map_err(|e| format!("Centurion chat bridge failed: {e}"))?;
    parse_bridge_stdout(&output.stdout).ok_or_else(|| {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.trim().is_empty() {
            "Centurion did not return a reply.".to_owned()
        } else {
            stderr
                .lines()
                .next()
                .unwrap_or("Centurion chat failed.")
                .to_owned()
        }
    })
}

/// Prefer daemon; fall back to one-shot on failure.
pub fn bridge_request_resilient(action: &str, extra: Value) -> Result<Value, String> {
    match bridge_request(action, extra.clone()) {
        Ok(v) => Ok(v),
        Err(_) => bridge_request_oneshot(action, extra),
    }
}

/// Best-effort: kick the daemon at app startup so the first Chat send is warm.
pub fn warm_bridge_daemon_async() {
    thread::spawn(|| {
        let _ = ensure_bridge_daemon();
    });
}
