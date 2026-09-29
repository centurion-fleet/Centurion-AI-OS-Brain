//! Desktop bridge plumbing shared by the Brain shell.
//!
//! Extracted from the former `chat_page` module when Chat was removed from the
//! Linux Brain (v6.0.0). Everything here is infrastructure that the rest of the
//! shell depends on — path resolution for HOME / repo / CLI, and the async
//! bridge invocation helpers. None of it is chat-specific.
//!
//! Chat itself is gone; conversation now lives in the Sovereign AI Remote.

use serde_json::Value;

/// The credential this Brain authenticates an update download with (NR-001 fault 2).
///
/// Two compose, explicit/env code first so a Brain that holds one keeps using it
/// (route 2a):
///
///   1. `explicit_code` (the `--licence-code` CLI flag, dry runs) or
///      `CENTURION_LICENCE_CODE` in the environment.
///   2. The identity this Brain is *already bound with* — `license_id` +
///      `machine_fingerprint`, the pair `/api/v1/license/checkin` trusts. This is
///      route 2b and it asks nothing of the owner: the machine is already reconciled
///      with the licence server, so the download door can consult the same records
///      the checkin door already does.
///
/// `None` means the Brain holds neither — an unactivated machine. That is a real state,
/// and the update reports exactly that rather than failing obscurely.
///
/// Lives here rather than in the GTK module because the headless `--update-dry-run`
/// entry point needs the same resolution, and a dry run that authenticated differently
/// from the real path would test the wrong thing.
pub fn packaged_update_credential(explicit_code: Option<&str>) -> Option<crate::brain_update::DownloadAuth> {
    use crate::brain_update::DownloadAuth;

    // Route 2a — an explicit code, or one in the environment.
    let from_env = std::env::var("CENTURION_LICENCE_CODE").ok();
    for candidate in [explicit_code, from_env.as_deref()] {
        if let Some(code) = candidate.map(str::trim).filter(|c| !c.is_empty()) {
            return Some(DownloadAuth::Code(code.to_owned()));
        }
    }
    // Seam for persisting a code at activation — not yet stored anywhere. Read back
    // from this Brain's own encrypted entitlement store when it is.

    // Route 2b — the identity the Brain already presents.
    let payload = run_bridge_action("license_update_identity", serde_json::json!({}))?;
    if payload.get("ok").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    let field = |name: &str| -> Option<String> {
        payload
            .get(name)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
    };
    Some(DownloadAuth::Identity {
        license_id: field("license_id")?,
        hardware_id: field("hardware_id")?,
        install_id: field("install_id"),
    })
}
use std::cell::Cell;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{mpsc, OnceLock};
use std::thread;
use std::time::Duration;

pub fn resolve_centurion_home() -> String {
    static CACHE: OnceLock<String> = OnceLock::new();
    CACHE.get_or_init(resolve_centurion_home_uncached).clone()
}

fn resolve_centurion_home_uncached() -> String {
    let default_root = || -> PathBuf {
        std::env::var("HOME")
            .map(|home| PathBuf::from(home).join(".centurion"))
            .unwrap_or_else(|_| PathBuf::from(".centurion"))
    };

    let fallback = |path: PathBuf| -> String {
        let root = default_root();
        if path.is_dir() {
            path.to_string_lossy().into_owned()
        } else {
            root.to_string_lossy().into_owned()
        }
    };

    if let Ok(home) = std::env::var("CENTURION_HOME") {
        let trimmed = home.trim();
        if !trimmed.is_empty() {
            let path = PathBuf::from(trimmed);
            if path
                .parent()
                .and_then(|parent| parent.file_name())
                .is_some_and(|name| name == "profiles")
            {
                return fallback(path);
            }
        }
    }

    let root = default_root();
    let active = root.join("active_profile");
    if let Ok(name) = std::fs::read_to_string(&active) {
        let name = name.trim();
        if !name.is_empty() && name != "default" {
            return fallback(root.join("profiles").join(name));
        }
    }

    if let Ok(home) = std::env::var("CENTURION_HOME") {
        let trimmed = home.trim();
        if !trimmed.is_empty() {
            let path = PathBuf::from(trimmed);
            if path.is_dir() {
                return trimmed.to_owned();
            }
        }
    }

    root.to_string_lossy().into_owned()
}

/// Resolve the Centurion AI OS checkout used by the Python bridge.
///
/// Cached like `resolve_centurion_home` — the probe stats several candidate
/// paths and is called for every bridge command we spawn.
pub fn resolve_centurion_repo_root() -> Option<PathBuf> {
    static CACHE: OnceLock<Option<PathBuf>> = OnceLock::new();
    CACHE
        .get_or_init(resolve_centurion_repo_root_uncached)
        .clone()
}

fn resolve_centurion_repo_root_uncached() -> Option<PathBuf> {
    if let Ok(env_root) = std::env::var("CENTURION_AI_REPO") {
        let trimmed = env_root.trim();
        if !trimmed.is_empty() {
            let root = PathBuf::from(trimmed);
            let script = root
                .join("brain")
                .join("linux")
                .join("scripts")
                .join("install-user.sh");
            if script.is_file() {
                return Some(root);
            }
            // Legacy pre-reorg layout.
            let legacy = root
                .join("desktop-native")
                .join("scripts")
                .join("install-user.sh");
            if legacy.is_file() {
                return Some(root);
            }
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        for root in [
            home.join("Centurion-AI-OS").join("Centurion-AI-OS"),
            home.join("Centurion-AI-OS"),
            home.join(".centurion").join("Centurion-AI-OS"),
        ] {
            let script = root
                .join("brain")
                .join("linux")
                .join("scripts")
                .join("install-user.sh");
            if script.is_file() {
                return Some(root);
            }
            // Legacy pre-reorg layout.
            let legacy = root
                .join("desktop-native")
                .join("scripts")
                .join("install-user.sh");
            if legacy.is_file() {
                return Some(root);
            }
        }
    }
    None
}

pub fn configure_bridge_command(command: &mut Command) {
    command.env("CENTURION_HOME", resolve_centurion_home());
    if let Some(root) = resolve_centurion_repo_root() {
        command.env("CENTURION_AI_REPO", root.as_os_str());
        command.current_dir(&root);
        // Prefer checkout imports over a stale site-packages install.
        let mut pythonpath = root.display().to_string();
        if let Ok(existing) = std::env::var("PYTHONPATH") {
            let trimmed = existing.trim();
            if !trimmed.is_empty() {
                pythonpath.push(':');
                pythonpath.push_str(trimmed);
            }
        }
        command.env("PYTHONPATH", pythonpath);
    }
}

/// True when ``python`` can import the Brain bridge *and* the ``centurion`` package.
///
/// New customer installs often had ``centurion_cli`` on an old user venv while
/// license/fleet code needs ``import centurion`` — verify both so we never pick
/// a half-installed interpreter (and never fall through to bare system python3).
fn python_imports_brain_core(python: &str) -> bool {
    let path = PathBuf::from(python);
    if !path.is_file() {
        return false;
    }
    Command::new(python)
        .args([
            "-c",
            "import centurion_cli.remote_bridge, centurion.license.enforcement",
        ])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// Resolve the Python that can import Brain core (bundled Fedora venv preferred).
pub fn resolve_bridge_python() -> String {
    for key in ["CENTURION_PYTHON", "CENTURION_REMOTE_PYTHON"] {
        if let Ok(path) = std::env::var(key) {
            let trimmed = path.trim();
            if !trimmed.is_empty() && python_imports_brain_core(trimmed) {
                return trimmed.to_owned();
            }
        }
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
    // Full Get Brain RPM ships core here — prefer over any stale ~/.centurion venv.
    candidates.push(PathBuf::from("/usr/lib/centurion/venv/bin/python"));
    if let Ok(repo) = std::env::var("CENTURION_AI_REPO") {
        let root = PathBuf::from(repo.trim());
        if !root.as_os_str().is_empty() {
            candidates.push(root.join(".venv/bin/python"));
            candidates.push(root.join("venv/bin/python"));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        candidates.push(home.join(".centurion/Centurion-AI-OS/venv/bin/python"));
        candidates.push(home.join(".centurion/Centurion-AI-OS/.venv/bin/python"));
        candidates.push(home.join(".centurion/venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/.venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/.venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/venv/bin/python"));
        candidates.push(home.join("src/Centurion-AI-OS/.venv/bin/python"));
        candidates.push(home.join("src/Centurion-AI-OS/venv/bin/python"));
    }
    // Match customer-install.sh: follow a PATH `centurion` shim to its venv.
    if let Some(centurion) = which_on_path("centurion") {
        if let Some(bin_dir) = centurion.parent() {
            candidates.push(bin_dir.join("python"));
            candidates.push(bin_dir.join("python3"));
        }
    }

    for path in candidates {
        let candidate = path.to_string_lossy();
        if python_imports_brain_core(candidate.as_ref()) {
            return candidate.into_owned();
        }
    }
    // Last resort: still prefer the RPM python binary if present (import probe
    // may fail before PYTHONPATH is applied by configure_bridge_command).
    let bundled = "/usr/lib/centurion/venv/bin/python";
    if PathBuf::from(bundled).is_file() {
        return bundled.to_owned();
    }
    "python3".to_owned()
}

/// Resolve the ``centurion`` CLI next to the Brain venv (not a stale ~/.local/bin shim).
pub fn resolve_centurion_cli() -> String {
    if let Ok(py) = std::env::var("CENTURION_PYTHON") {
        let trimmed = py.trim();
        if !trimmed.is_empty() {
            if let Some(bin_dir) = PathBuf::from(trimmed).parent() {
                let centurion = bin_dir.join("centurion");
                if centurion.is_file() {
                    return centurion.to_string_lossy().into_owned();
                }
            }
        }
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
    // Fedora Brain RPM wrappers / venv entry points first.
    candidates.push(PathBuf::from("/usr/bin/centurion"));
    candidates.push(PathBuf::from("/usr/lib/centurion/venv/bin/centurion"));
    if let Ok(repo) = std::env::var("CENTURION_AI_REPO") {
        let root = PathBuf::from(repo.trim());
        if !root.as_os_str().is_empty() {
            candidates.push(root.join(".venv/bin/centurion"));
            candidates.push(root.join("venv/bin/centurion"));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        candidates.push(home.join(".centurion/Centurion-AI-OS/venv/bin/centurion"));
        candidates.push(home.join(".centurion/Centurion-AI-OS/.venv/bin/centurion"));
        candidates.push(home.join(".centurion/venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/.venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/.venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/venv/bin/centurion"));
        candidates.push(home.join("src/Centurion-AI-OS/.venv/bin/centurion"));
        candidates.push(home.join("src/Centurion-AI-OS/venv/bin/centurion"));
        candidates.push(home.join(".local/bin/centurion"));
    }
    if let Some(path) = which_on_path("centurion") {
        candidates.push(path);
    }

    for path in candidates {
        if path.is_file() {
            return path.to_string_lossy().into_owned();
        }
    }
    "centurion".to_owned()
}

fn which_on_path(name: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn run_bridge_json(action: &str, extra: Value) -> Result<Value, String> {
    crate::bridge_client::bridge_request_resilient(action, extra)
}

fn parse_final_json(stdout: &str) -> Option<Value> {
    let mut last = None;
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
            last = Some(value);
        }
    }
    last.or_else(|| serde_json::from_str(stdout.trim()).ok())
}

/// Parse bridge stdout the same way Chat does (last JSON line wins).
pub fn parse_bridge_stdout(stdout: &[u8]) -> Option<Value> {
    let text = String::from_utf8_lossy(stdout);
    parse_final_json(&text)
}

/// Run one Settings/bridge action (Soul, Horizon, oversight, …).
/// Call from a worker thread — never block the GTK main loop.
pub fn run_bridge_action(action: &str, extra: Value) -> Option<Value> {
    crate::bridge_client::bridge_request_resilient(action, extra).ok()
}

/// Like `run_bridge_action`, but keeps the reason it failed.
///
/// The plain version drops the error string, and that is how a real client's
/// screen ended up saying only "Could not save token" (David Clynch, 26 Sep
/// 2026): a bridge that never answered and a handler that refused both arrive
/// as the same shrug. Any dialog that reports failure must use this one, so the
/// owner — and support — get the cause rather than a dead end.
pub fn run_bridge_action_result(action: &str, extra: Value) -> Result<Value, String> {
    crate::bridge_client::bridge_request_resilient(action, extra)
}

/// Spawn bridge I/O off the GTK thread and apply the result on the UI loop.
///
/// Prefer this over `run_bridge_action` inside `connect_clicked` / dialog
/// open/save handlers. `work` must be `Send`; `apply` runs on the main context.
pub fn run_bridge_async<T, FWork, FApply>(work: FWork, apply: FApply)
where
    T: Send + 'static,
    FWork: FnOnce() -> T + Send + 'static,
    FApply: FnOnce(T) + 'static,
{
    let (tx, rx) = mpsc::channel::<T>();
    thread::spawn(move || {
        let _ = tx.send(work());
    });
    // timeout_add_local requires FnMut; Cell lets us take the FnOnce once.
    let apply = Cell::new(Some(apply));
    glib::timeout_add_local(Duration::from_millis(40), move || match rx.try_recv() {
        Ok(value) => {
            if let Some(apply) = apply.take() {
                apply(value);
            }
            glib::ControlFlow::Break
        }
        Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
        Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
    });
}

/// Convenience: one bridge action, then apply `Option<Value>` on the UI thread.
pub fn run_bridge_action_async<FApply>(action: &str, extra: Value, apply: FApply)
where
    FApply: FnOnce(Option<Value>) + 'static,
{
    let action = action.to_owned();
    run_bridge_async(move || run_bridge_action(&action, extra), apply);
}

