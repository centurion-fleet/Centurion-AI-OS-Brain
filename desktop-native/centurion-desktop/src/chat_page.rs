//! Phone-like bubble chat for the Linux Brain Chat tab.
//!
//! Drives the local Centurion agent via `centurion_cli.remote_bridge`
//! (same path as iPhone Crypto Chat), with mid-turn tool approvals.

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;
use serde_json::Value;
use std::cell::{Cell, RefCell};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ChatRole {
    User,
    Assistant,
    System,
}

#[derive(Clone, Debug)]
struct ChatMessage {
    role: ChatRole,
    content: String,
}

struct ApprovalRequest {
    #[allow(dead_code)]
    approval_id: String,
    session_key: String,
    command: String,
    description: String,
    choices: Vec<String>,
}

enum WorkerEvent {
    Approval(ApprovalRequest),
    Done(Result<ChatTurnResult, String>),
}

struct ChatTurnResult {
    text: String,
    session_id: String,
}

struct ApprovalDecision {
    session_key: String,
    choice: String,
}

#[derive(Clone, Debug)]
struct SessionSummary {
    id: String,
    title: String,
    preview: String,
    last_active_label: String,
}

/// Resolve CENTURION_HOME the same way the CLI honors ``active_profile``.
pub fn resolve_centurion_home() -> String {
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
pub fn resolve_centurion_repo_root() -> Option<PathBuf> {
    if let Ok(env_root) = std::env::var("CENTURION_AI_REPO") {
        let trimmed = env_root.trim();
        if !trimmed.is_empty() {
            let root = PathBuf::from(trimmed);
            let script = root
                .join("desktop-native")
                .join("scripts")
                .join("install-user.sh");
            if script.is_file() {
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
                .join("desktop-native")
                .join("scripts")
                .join("install-user.sh");
            if script.is_file() {
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
    }
}

/// Resolve the Python that can `import centurion_cli` (venv preferred).
pub fn resolve_bridge_python() -> String {
    for key in ["CENTURION_PYTHON", "CENTURION_REMOTE_PYTHON"] {
        if let Ok(path) = std::env::var(key) {
            let trimmed = path.trim();
            if !trimmed.is_empty() && PathBuf::from(trimmed).is_file() {
                return trimmed.to_owned();
            }
        }
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
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
        candidates.push(home.join(".centurion/venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/.venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/.venv/bin/python"));
        candidates.push(home.join("Centurion-AI-OS/venv/bin/python"));
    }

    for path in candidates {
        if path.is_file() {
            return path.to_string_lossy().into_owned();
        }
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
        candidates.push(home.join(".centurion/venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/.venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/Centurion-AI-OS/venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/.venv/bin/centurion"));
        candidates.push(home.join("Centurion-AI-OS/venv/bin/centurion"));
        candidates.push(home.join(".local/bin/centurion"));
    }

    for path in candidates {
        if path.is_file() {
            return path.to_string_lossy().into_owned();
        }
    }
    "centurion".to_owned()
}

fn session_store_path() -> PathBuf {
    PathBuf::from(resolve_centurion_home()).join("desktop_chat_session")
}

/// Drop the Brain Chat session pointer so the next message starts clean
/// (needed after Soul/name changes — prior Hermes replies stick otherwise).
pub fn clear_desktop_chat_session() {
    let path = session_store_path();
    let _ = std::fs::remove_file(path);
}

fn load_session_id() -> Option<String> {
    let path = session_store_path();
    std::fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
}

fn save_session_id(session_id: &str) {
    let path = session_store_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(path, session_id);
}

fn run_bridge_json(action: &str, extra: Value) -> Result<Value, String> {
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
    let stdout = String::from_utf8_lossy(&output.stdout);
    parse_final_json(&stdout).ok_or_else(|| {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.trim().is_empty() {
            "Centurion did not return a reply.".to_owned()
        } else {
            stderr.lines().next().unwrap_or("Centurion chat failed.").to_owned()
        }
    })
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
pub fn run_bridge_action(action: &str, extra: Value) -> Option<Value> {
    let mut body = serde_json::Map::new();
    body.insert("id".to_owned(), Value::String("desktop-settings".to_owned()));
    body.insert(
        "action".to_owned(),
        Value::String(action.to_owned()),
    );
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
    let mut child = child.spawn().ok()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(payload.as_bytes()).ok()?;
    }
    let output = child.wait_with_output().ok()?;
    if !output.status.success() && output.stdout.is_empty() {
        return None;
    }
    parse_bridge_stdout(&output.stdout)
}

fn ensure_session_id() -> Result<String, String> {
    if let Some(existing) = load_session_id() {
        return Ok(existing);
    }
    let response = run_bridge_json(
        "session_new",
        serde_json::json!({ "title": "Brain Chat" }),
    )?;
    if response.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not start a chat session.")
            .to_owned());
    }
    let session_id = response
        .get("session_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Could not start a chat session.".to_owned())?
        .to_owned();
    save_session_id(&session_id);
    Ok(session_id)
}

fn parse_bridge_messages(messages: &[Value]) -> Vec<ChatMessage> {
    messages
        .iter()
        .filter_map(|msg| {
            let role = msg.get("role")?.as_str()?;
            let content = match msg.get("content") {
                Some(Value::String(s)) => s.trim().to_owned(),
                Some(Value::Array(parts)) => parts
                    .iter()
                    .filter_map(|part| {
                        if let Some(text) = part.as_str() {
                            return Some(text.to_owned());
                        }
                        part.get("text")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned)
                    })
                    .collect::<Vec<_>>()
                    .join("")
                    .trim()
                    .to_owned(),
                _ => return None,
            };
            if content.is_empty() {
                return None;
            }
            let role = match role {
                "user" => ChatRole::User,
                "assistant" => ChatRole::Assistant,
                _ => return None,
            };
            Some(ChatMessage { role, content })
        })
        .collect()
}

fn load_history(session_id: &str) -> Vec<ChatMessage> {
    let Ok(response) = run_bridge_json(
        "session_history",
        serde_json::json!({ "session_id": session_id }),
    ) else {
        return Vec::new();
    };
    if response.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return Vec::new();
    }
    let messages = response
        .get("messages")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    parse_bridge_messages(&messages)
}

fn format_last_active(value: Option<&Value>) -> String {
    let Some(value) = value else {
        return String::new();
    };
    let secs = if let Some(n) = value.as_f64() {
        n as i64
    } else if let Some(n) = value.as_i64() {
        n
    } else if let Some(s) = value.as_str() {
        // ISO-ish or plain epoch string — show a short slice.
        if let Ok(n) = s.parse::<f64>() {
            n as i64
        } else if s.len() >= 16 {
            return s[..16].replace('T', " ");
        } else {
            return s.to_owned();
        }
    } else {
        return String::new();
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(secs);
    let delta = (now - secs).max(0);
    if delta < 60 {
        "just now".to_owned()
    } else if delta < 3600 {
        format!("{}m ago", delta / 60)
    } else if delta < 86400 {
        format!("{}h ago", delta / 3600)
    } else if delta < 86400 * 7 {
        format!("{}d ago", delta / 86400)
    } else {
        format!("{}w ago", delta / (86400 * 7))
    }
}

fn list_sessions() -> Vec<SessionSummary> {
    let Ok(response) = run_bridge_json(
        "session_list",
        serde_json::json!({ "limit": 50, "source": "remote" }),
    ) else {
        return Vec::new();
    };
    if response.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return Vec::new();
    }
    let sessions = response
        .get("sessions")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    sessions
        .into_iter()
        .filter_map(|row| {
            let id = row.get("id")?.as_str()?.trim().to_owned();
            if id.is_empty() {
                return None;
            }
            let title = row
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_owned();
            let preview = row
                .get("preview")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_owned();
            let display_title = if !title.is_empty() {
                title
            } else if !preview.is_empty() {
                preview.chars().take(48).collect()
            } else {
                "Untitled chat".to_owned()
            };
            Some(SessionSummary {
                id,
                title: display_title,
                preview,
                last_active_label: format_last_active(row.get("last_active")),
            })
        })
        .collect()
}

fn resume_session(session_id: &str) -> Result<(String, Vec<ChatMessage>), String> {
    let response = run_bridge_json(
        "session_resume",
        serde_json::json!({ "session_id": session_id }),
    )?;
    if response.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not open that conversation.")
            .to_owned());
    }
    let tip = response
        .get("session_id")
        .and_then(|v| v.as_str())
        .unwrap_or(session_id)
        .to_owned();
    let messages = response
        .get("messages")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    Ok((tip, parse_bridge_messages(&messages)))
}

fn session_row(summary: &SessionSummary, active: bool) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.set_activatable(true);
    row.set_selectable(true);
    row.set_widget_name(&summary.id);
    if active {
        row.add_css_class("centurion-session-active");
    }

    let box_ = gtk::Box::new(gtk::Orientation::Vertical, 2);
    box_.set_margin_top(8);
    box_.set_margin_bottom(8);
    box_.set_margin_start(10);
    box_.set_margin_end(10);

    let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let title = gtk::Label::builder()
        .label(&summary.title)
        .xalign(0.0)
        .ellipsize(gtk::pango::EllipsizeMode::End)
        .hexpand(true)
        .css_classes(["heading"])
        .build();
    title_row.append(&title);
    if !summary.last_active_label.is_empty() {
        title_row.append(
            &gtk::Label::builder()
                .label(&summary.last_active_label)
                .xalign(1.0)
                .css_classes(["caption", "dim-label"])
                .build(),
        );
    }
    box_.append(&title_row);

    if !summary.preview.is_empty() && summary.preview != summary.title {
        box_.append(
            &gtk::Label::builder()
                .label(&summary.preview)
                .xalign(0.0)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .css_classes(["caption", "dim-label"])
                .build(),
        );
    }

    row.set_child(Some(&box_));
    row
}

fn run_chat_turn(
    session_id: String,
    text: String,
    event_tx: mpsc::Sender<WorkerEvent>,
    approval_rx: mpsc::Receiver<ApprovalDecision>,
) {
    let payload = serde_json::json!({
        "id": "desktop-chat",
        "action": "chat",
        "text": text,
        "session_id": session_id,
    });
    let mut line = match serde_json::to_vec(&payload) {
        Ok(mut bytes) => {
            bytes.push(b'\n');
            bytes
        }
        Err(e) => {
            let _ = event_tx.send(WorkerEvent::Done(Err(format!("Could not prepare message: {e}"))));
            return;
        }
    };

    let mut child = Command::new(resolve_bridge_python());
    child
        .args(["-m", "centurion_cli.remote_bridge"])
        .env("CENTURION_REMOTE_EVENTS", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    configure_bridge_command(&mut child);
    let mut child = match child.spawn()
    {
        Ok(child) => child,
        Err(e) => {
            let _ = event_tx.send(WorkerEvent::Done(Err(format!(
                "Could not start Centurion chat bridge: {e}"
            ))));
            return;
        }
    };

    let mut stdin = match child.stdin.take() {
        Some(stdin) => stdin,
        None => {
            let _ = event_tx.send(WorkerEvent::Done(Err(
                "Centurion chat bridge stdin unavailable.".to_owned(),
            )));
            return;
        }
    };
    if let Err(e) = stdin.write_all(&line) {
        let _ = event_tx.send(WorkerEvent::Done(Err(format!("Could not send message: {e}"))));
        return;
    }
    let _ = stdin.flush();

    let stdout = match child.stdout.take() {
        Some(stdout) => stdout,
        None => {
            let _ = event_tx.send(WorkerEvent::Done(Err(
                "Centurion chat bridge stdout unavailable.".to_owned(),
            )));
            return;
        }
    };
    let reader = BufReader::new(stdout);
    let mut final_response: Option<Value> = None;

    for raw_line in reader.lines() {
        // Drain any approval decisions the UI already queued.
        while let Ok(decision) = approval_rx.try_recv() {
            let payload = serde_json::json!({
                "action": "approval_respond",
                "session_key": decision.session_key,
                "choice": decision.choice,
            });
            if let Ok(mut bytes) = serde_json::to_vec(&payload) {
                bytes.push(b'\n');
                let _ = stdin.write_all(&bytes);
                let _ = stdin.flush();
            }
        }

        let Ok(raw_line) = raw_line else {
            break;
        };
        let trimmed = raw_line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        if value.get("centurion_event").and_then(|v| v.as_str()) == Some("approval_request") {
            let request = ApprovalRequest {
                approval_id: value
                    .get("approval_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_owned(),
                session_key: value
                    .get("session_key")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_owned(),
                command: value
                    .get("command")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_owned(),
                description: value
                    .get("description")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_owned(),
                choices: value
                    .get("choices")
                    .and_then(|v| v.as_array())
                    .map(|items| {
                        items
                            .iter()
                            .filter_map(|item| item.as_str().map(str::to_owned))
                            .collect()
                    })
                    .unwrap_or_else(|| {
                        vec![
                            "once".to_owned(),
                            "session".to_owned(),
                            "always".to_owned(),
                            "deny".to_owned(),
                        ]
                    }),
            };
            let deny_session_key = request.session_key.clone();
            let _ = event_tx.send(WorkerEvent::Approval(request));
            // Block until the UI answers this approval (or the channel closes).
            match approval_rx.recv_timeout(Duration::from_secs(600)) {
                Ok(decision) => {
                    let payload = serde_json::json!({
                        "action": "approval_respond",
                        "session_key": decision.session_key,
                        "choice": decision.choice,
                    });
                    if let Ok(mut bytes) = serde_json::to_vec(&payload) {
                        bytes.push(b'\n');
                        let _ = stdin.write_all(&bytes);
                        let _ = stdin.flush();
                    }
                }
                Err(_) => {
                    let payload = serde_json::json!({
                        "action": "approval_respond",
                        "session_key": deny_session_key,
                        "choice": "deny",
                    });
                    if let Ok(mut bytes) = serde_json::to_vec(&payload) {
                        bytes.push(b'\n');
                        let _ = stdin.write_all(&bytes);
                        let _ = stdin.flush();
                    }
                }
            }
            continue;
        }
        final_response = Some(value);
        break;
    }

    let _ = child.wait();

    let result = match final_response {
        Some(value) if value.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
            let text = value
                .get("text")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();
            let sid = value
                .get("session_id")
                .and_then(|v| v.as_str())
                .unwrap_or(&session_id)
                .to_owned();
            Ok(ChatTurnResult {
                text: if text.trim().is_empty() {
                    "(No reply text.)".to_owned()
                } else {
                    text
                },
                session_id: sid,
            })
        }
        Some(value) => Err(value
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Centurion could not reply.")
            .to_owned()),
        None => Err("Centurion did not return a reply.".to_owned()),
    };
    let _ = event_tx.send(WorkerEvent::Done(result));
}

fn message_row(message: &ChatMessage, assistant_name: &str) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.set_activatable(false);
    row.set_selectable(false);

    let outer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    outer.set_margin_top(4);
    outer.set_margin_bottom(4);

    let bubble = gtk::Box::new(gtk::Orientation::Vertical, 4);
    bubble.set_hexpand(true);

    if message.role == ChatRole::Assistant {
        bubble.append(
            &gtk::Label::builder()
                .label(assistant_name)
                .xalign(0.0)
                .css_classes(["caption", "dim-label"])
                .build(),
        );
    } else if message.role == ChatRole::System {
        bubble.append(
            &gtk::Label::builder()
                .label("Status")
                .xalign(0.0)
                .css_classes(["caption", "dim-label"])
                .build(),
        );
    }

    bubble.append(
        &gtk::Label::builder()
            .label(&message.content)
            .wrap(true)
            .xalign(0.0)
            .selectable(true)
            .build(),
    );

    match message.role {
        ChatRole::User => {
            bubble.set_halign(gtk::Align::End);
            bubble.add_css_class("centurion-chat-user");
            outer.append(&bubble);
        }
        ChatRole::Assistant => {
            bubble.set_halign(gtk::Align::Start);
            bubble.add_css_class("centurion-chat-bot");
            outer.append(&bubble);
        }
        ChatRole::System => {
            bubble.set_halign(gtk::Align::Fill);
            bubble.add_css_class("centurion-chat-system");
            outer.append(&bubble);
        }
    }

    row.set_child(Some(&outer));
    row
}

fn load_assistant_display_name() -> String {
    match run_bridge_json("soul_get", serde_json::json!({})) {
        Ok(payload) => {
            let display = payload
                .pointer("/soul/displayName")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim();
            let name = if !display.is_empty() {
                display
            } else {
                payload
                    .pointer("/soul/name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
            };
            if name.is_empty() || name.eq_ignore_ascii_case("hermes") {
                "Centurion".to_owned()
            } else {
                name.chars().take(48).collect()
            }
        }
        Err(_) => "Centurion".to_owned(),
    }
}

fn scroll_chat_to_latest(
    message_scroll: &gtk::ScrolledWindow,
    message_list: &gtk::ListBox,
    programmatic: &Rc<Cell<bool>>,
) {
    // Fedora Brain ships an older GTK4 — ListBox::scroll_to is unavailable there.
    // Pin via the ScrolledWindow adjustment; follow-bottom wiring keeps chasing
    // as new rows are laid out.
    programmatic.set(true);
    if let Some(child) = message_list.last_child() {
        if let Ok(row) = child.downcast::<gtk::ListBoxRow>() {
            message_list.select_row(Some(&row));
        }
    }
    let adj = message_scroll.vadjustment();
    let target = (adj.upper() - adj.page_size()).max(adj.lower());
    adj.set_value(target);
    programmatic.set(false);
}

fn schedule_scroll_to_latest(
    message_scroll: &gtk::ScrolledWindow,
    message_list: &gtk::ListBox,
    follow_bottom: &Rc<Cell<bool>>,
    programmatic: &Rc<Cell<bool>>,
) {
    follow_bottom.set(true);
    scroll_chat_to_latest(message_scroll, message_list, programmatic);

    for delay_ms in [16u64, 50, 120, 250, 500] {
        let message_scroll = message_scroll.clone();
        let message_list = message_list.clone();
        let follow_bottom = follow_bottom.clone();
        let programmatic = programmatic.clone();
        glib::timeout_add_local_once(Duration::from_millis(delay_ms), move || {
            follow_bottom.set(true);
            scroll_chat_to_latest(&message_scroll, &message_list, &programmatic);
        });
    }
}

fn wire_follow_bottom_scroll(
    message_scroll: &gtk::ScrolledWindow,
    follow_bottom: Rc<Cell<bool>>,
    programmatic: Rc<Cell<bool>>,
) {
    let adj = message_scroll.vadjustment();

    adj.connect_changed({
        let follow_bottom = follow_bottom.clone();
        let programmatic = programmatic.clone();
        move |adj| {
            if !follow_bottom.get() {
                return;
            }
            let target = (adj.upper() - adj.page_size()).max(adj.lower());
            if (adj.value() - target).abs() > 1.0 {
                programmatic.set(true);
                adj.set_value(target);
                programmatic.set(false);
            }
        }
    });

    adj.connect_value_changed({
        let follow_bottom = follow_bottom.clone();
        let programmatic = programmatic.clone();
        move |adj| {
            if programmatic.get() {
                return;
            }
            let target = (adj.upper() - adj.page_size()).max(adj.lower());
            // If the user scrolls away from the bottom, stop chasing until
            // the next send/reply arms follow again.
            follow_bottom.set(adj.value() >= target - 48.0);
        }
    });
}

/// Settings → Soul save clears ``desktop_chat_session`` on disk. Honor that in
/// the live Chat tab so the next turn starts a clean session with the new Soul
/// instead of continuing a stale in-memory session id.
fn honor_soul_session_reset(
    session_id: &Rc<RefCell<Option<String>>>,
    messages: &Rc<RefCell<Vec<ChatMessage>>>,
) -> bool {
    if session_id.borrow().is_some() && load_session_id().is_none() {
        *session_id.borrow_mut() = None;
        messages.borrow_mut().clear();
        return true;
    }
    false
}

/// Build the Chat tab page (bubble UI + always-visible composer).
pub fn build() -> gtk::Box {
    let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
    container.set_vexpand(true);
    container.set_hexpand(true);

    let paned = gtk::Paned::new(gtk::Orientation::Horizontal);
    paned.set_vexpand(true);
    paned.set_hexpand(true);
    paned.set_wide_handle(true);
    paned.set_resize_start_child(false);
    paned.set_shrink_start_child(false);
    paned.set_resize_end_child(true);
    paned.set_shrink_end_child(false);
    paned.set_position(280);

    // ── Conversation sidebar ──────────────────────────────────────────
    let sidebar = gtk::Box::new(gtk::Orientation::Vertical, 0);
    sidebar.set_size_request(240, -1);
    sidebar.add_css_class("centurion-chat-sidebar");
    sidebar.set_vexpand(true);

    let sidebar_header = gtk::Box::new(gtk::Orientation::Vertical, 6);
    sidebar_header.set_margin_top(12);
    sidebar_header.set_margin_start(12);
    sidebar_header.set_margin_end(12);
    sidebar_header.set_margin_bottom(8);
    sidebar_header.append(
        &gtk::Label::builder()
            .label("Conversations")
            .css_classes(["title-4"])
            .xalign(0.0)
            .build(),
    );
    let new_chat_button = gtk::Button::with_label("New chat");
    new_chat_button.set_halign(gtk::Align::Fill);
    new_chat_button.add_css_class("suggested-action");
    new_chat_button.set_tooltip_text(Some(
        "Start a fresh conversation on this brain.",
    ));
    sidebar_header.append(&new_chat_button);
    sidebar.append(&sidebar_header);

    let session_list = gtk::ListBox::new();
    session_list.set_selection_mode(gtk::SelectionMode::Browse);
    session_list.add_css_class("navigation-sidebar");
    session_list.set_vexpand(true);

    let session_empty = gtk::Label::builder()
        .label("No past conversations yet.\nSend a message to begin.")
        .wrap(true)
        .justify(gtk::Justification::Center)
        .css_classes(["dim-label"])
        .margin_top(24)
        .margin_start(12)
        .margin_end(12)
        .build();

    let session_stack = gtk::Stack::new();
    session_stack.set_vexpand(true);
    session_stack.set_hexpand(true);
    let session_scroll = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .child(&session_list)
        .build();
    session_stack.add_named(&session_scroll, Some("list"));
    session_stack.add_named(&session_empty, Some("empty"));
    session_stack.set_visible_child_name("empty");
    sidebar.append(&session_stack);

    paned.set_start_child(Some(&sidebar));

    // ── Main chat pane ────────────────────────────────────────────────
    // Vertical stack (not Overlay): the composer sits in normal layout so
    // "scroll to latest" lands above the input — not under it.
    let chat_column = gtk::Box::new(gtk::Orientation::Vertical, 0);
    chat_column.set_vexpand(true);
    chat_column.set_hexpand(true);

    let assistant_name = Rc::new(RefCell::new(load_assistant_display_name()));

    let top = gtk::Box::new(gtk::Orientation::Vertical, 4);
    top.set_margin_top(12);
    top.set_margin_start(16);
    top.set_margin_end(16);
    top.set_margin_bottom(8);
    top.set_vexpand(false);
    let title = gtk::Label::builder()
        .label(&format!("Chat with {}", assistant_name.borrow()))
        .css_classes(["title-1"])
        .xalign(0.0)
        .build();
    top.append(&title);
    top.append(
        &gtk::Label::builder()
            .label(
                "Local chat on this brain — pick a past conversation on the left, \
                 or start a new one. Soul and Memory Horizon load with each answer.",
            )
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );
    chat_column.append(&top);

    let messages: Rc<RefCell<Vec<ChatMessage>>> = Rc::new(RefCell::new(Vec::new()));
    let session_id: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(load_session_id()));
    let is_sending = Rc::new(RefCell::new(false));
    let switching = Rc::new(Cell::new(false));

    let message_list = gtk::ListBox::new();
    message_list.set_selection_mode(gtk::SelectionMode::None);
    message_list.add_css_class("boxed-list");
    message_list.set_margin_start(12);
    message_list.set_margin_end(12);
    message_list.set_margin_top(4);
    message_list.set_margin_bottom(12);

    let message_scroll = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .propagate_natural_height(false)
        .build();
    message_scroll.set_child(Some(&message_list));
    let follow_bottom = Rc::new(Cell::new(true));
    let programmatic_scroll = Rc::new(Cell::new(false));
    wire_follow_bottom_scroll(
        &message_scroll,
        follow_bottom.clone(),
        programmatic_scroll.clone(),
    );
    chat_column.append(&message_scroll);

    let bottom = gtk::Box::new(gtk::Orientation::Vertical, 0);
    bottom.add_css_class("centurion-chat-composer");
    bottom.set_hexpand(true);
    bottom.set_vexpand(false);

    let approval_box = gtk::Box::new(gtk::Orientation::Vertical, 8);
    approval_box.set_margin_start(16);
    approval_box.set_margin_end(16);
    approval_box.set_margin_top(8);
    approval_box.set_margin_bottom(4);
    approval_box.set_visible(false);
    approval_box.add_css_class("centurion-chat-approval");
    let approval_title = gtk::Label::builder()
        .label("Your Sovereign needs approval")
        .css_classes(["title-4"])
        .xalign(0.0)
        .build();
    let approval_detail = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .build();
    let approval_buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    approval_box.append(&approval_title);
    approval_box.append(&approval_detail);
    approval_box.append(&approval_buttons);
    bottom.append(&approval_box);

    let error_label = gtk::Label::builder()
        .wrap(true)
        .xalign(0.0)
        .margin_start(16)
        .margin_end(16)
        .margin_bottom(4)
        .css_classes(["error"])
        .build();
    error_label.set_visible(false);
    bottom.append(&error_label);

    let input_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    input_row.set_margin_start(16);
    input_row.set_margin_end(16);
    input_row.set_margin_top(10);
    input_row.set_margin_bottom(16);
    input_row.set_vexpand(false);

    let input = gtk::Entry::builder()
        .placeholder_text("Type a message to your Centurion…")
        .hexpand(true)
        .can_focus(true)
        .css_classes(["centurion-chat-entry"])
        .build();
    input.set_size_request(-1, 44);

    let send_button = gtk::Button::with_label("Send");
    send_button.add_css_class("suggested-action");
    send_button.set_tooltip_text(Some("Send"));
    send_button.set_valign(gtk::Align::Center);
    send_button.set_size_request(88, 44);

    let sending_spinner = gtk::Spinner::new();
    sending_spinner.set_visible(false);
    sending_spinner.set_valign(gtk::Align::Center);

    input_row.append(&input);
    input_row.append(&send_button);
    input_row.append(&sending_spinner);
    bottom.append(&input_row);
    chat_column.append(&bottom);

    paned.set_end_child(Some(&chat_column));
    container.append(&paned);

    let refresh_messages: Rc<dyn Fn()> = Rc::new({
        let message_list = message_list.clone();
        let messages = messages.clone();
        let message_scroll = message_scroll.clone();
        let assistant_name = assistant_name.clone();
        let title = title.clone();
        let follow_bottom = follow_bottom.clone();
        let programmatic_scroll = programmatic_scroll.clone();
        move || {
            let name = assistant_name.borrow().clone();
            title.set_label(&format!("Chat with {name}"));
            while let Some(child) = message_list.first_child() {
                message_list.remove(&child);
            }
            let msgs = messages.borrow();
            if msgs.is_empty() {
                message_list.append(&message_row(
                    &ChatMessage {
                        role: ChatRole::System,
                        content:
                            "Your private conversation starts here. Use the message box at the bottom of this page."
                                .to_owned(),
                    },
                    &name,
                ));
            } else {
                for message in msgs.iter() {
                    message_list.append(&message_row(message, &name));
                }
            }
            schedule_scroll_to_latest(
                &message_scroll,
                &message_list,
                &follow_bottom,
                &programmatic_scroll,
            );
        }
    });

    let refresh_sessions: Rc<dyn Fn()> = Rc::new({
        let session_list = session_list.clone();
        let session_stack = session_stack.clone();
        let session_id = session_id.clone();
        move || {
            let session_list = session_list.clone();
            let session_stack = session_stack.clone();
            let session_id = session_id.clone();
            let (tx, rx) = mpsc::channel::<Vec<SessionSummary>>();
            thread::spawn(move || {
                let _ = tx.send(list_sessions());
            });
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(sessions) => {
                    while let Some(child) = session_list.first_child() {
                        session_list.remove(&child);
                    }
                    let active = session_id.borrow().clone();
                    if sessions.is_empty() {
                        session_stack.set_visible_child_name("empty");
                    } else {
                        session_stack.set_visible_child_name("list");
                        let mut active_row: Option<gtk::ListBoxRow> = None;
                        for summary in &sessions {
                            let is_active = active.as_deref() == Some(summary.id.as_str());
                            let row = session_row(summary, is_active);
                            if is_active {
                                active_row = Some(row.clone());
                            }
                            session_list.append(&row);
                        }
                        if let Some(row) = active_row {
                            session_list.select_row(Some(&row));
                        }
                    }
                    glib::ControlFlow::Break
                }
                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            });
        }
    });

    let set_error: Rc<dyn Fn(Option<String>)> = Rc::new({
        let error_label = error_label.clone();
        move |text: Option<String>| {
            if let Some(message) = text {
                error_label.set_label(&message);
                error_label.set_visible(true);
            } else {
                error_label.set_visible(false);
            }
        }
    });

    let set_sending: Rc<dyn Fn(bool)> = Rc::new({
        let send_button = send_button.clone();
        let sending_spinner = sending_spinner.clone();
        let input = input.clone();
        let is_sending = is_sending.clone();
        let new_chat_button = new_chat_button.clone();
        let session_list = session_list.clone();
        move |sending: bool| {
            *is_sending.borrow_mut() = sending;
            send_button.set_visible(!sending);
            sending_spinner.set_visible(sending);
            if sending {
                sending_spinner.start();
            } else {
                sending_spinner.stop();
            }
            input.set_sensitive(!sending);
            new_chat_button.set_sensitive(!sending);
            session_list.set_sensitive(!sending);
        }
    });

    // Initial session + history + sidebar load (bridge stays off the UI thread).
    {
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let (tx, rx) =
            mpsc::channel::<Result<(String, Vec<ChatMessage>), String>>();
        thread::spawn(move || {
            match ensure_session_id() {
                Ok(sid) => {
                    let history = load_history(&sid);
                    let _ = tx.send(Ok((sid, history)));
                }
                Err(err) => {
                    let _ = tx.send(Err(err));
                }
            }
        });
        glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
            Ok(Ok((sid, history))) => {
                *session_id.borrow_mut() = Some(sid);
                if !history.is_empty() {
                    *messages.borrow_mut() = history;
                }
                refresh_messages();
                refresh_sessions();
                glib::ControlFlow::Break
            }
            Ok(Err(error)) => {
                set_error(Some(error));
                refresh_sessions();
                glib::ControlFlow::Break
            }
            Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        });
    }
    refresh_messages();
    refresh_sessions();

    let pending_approval_tx: Rc<RefCell<Option<mpsc::Sender<ApprovalDecision>>>> =
        Rc::new(RefCell::new(None));

    let clear_approval: Rc<dyn Fn()> = Rc::new({
        let approval_box = approval_box.clone();
        let approval_buttons = approval_buttons.clone();
        move || {
            while let Some(child) = approval_buttons.first_child() {
                approval_buttons.remove(&child);
            }
            approval_box.set_visible(false);
        }
    });

    // New chat
    {
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let clear_approval = clear_approval.clone();
        let set_sending = set_sending.clone();
        let is_sending = is_sending.clone();
        let assistant_name = assistant_name.clone();
        let follow_bottom = follow_bottom.clone();
        new_chat_button.connect_clicked(move |_| {
            if *is_sending.borrow() {
                return;
            }
            clear_approval();
            set_sending(false);
            set_error(None);
            *assistant_name.borrow_mut() = load_assistant_display_name();
            messages.borrow_mut().clear();
            *session_id.borrow_mut() = None;
            let path = session_store_path();
            let _ = std::fs::remove_file(&path);
            follow_bottom.set(true);
            refresh_messages();
            let messages = messages.clone();
            let session_id = session_id.clone();
            let refresh_messages = refresh_messages.clone();
            let refresh_sessions = refresh_sessions.clone();
            let set_error = set_error.clone();
            let (tx, rx) = mpsc::channel::<Result<String, String>>();
            thread::spawn(move || {
                let _ = tx.send(ensure_session_id());
            });
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(Ok(sid)) => {
                    *session_id.borrow_mut() = Some(sid);
                    messages.borrow_mut().clear();
                    refresh_messages();
                    refresh_sessions();
                    glib::ControlFlow::Break
                }
                Ok(Err(error)) => {
                    set_error(Some(error));
                    glib::ControlFlow::Break
                }
                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            });
        });
    }

    // Switch conversation from sidebar
    {
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let clear_approval = clear_approval.clone();
        let is_sending = is_sending.clone();
        let switching = switching.clone();
        let follow_bottom = follow_bottom.clone();
        let assistant_name = assistant_name.clone();
        session_list.connect_row_activated(move |_, row| {
            if *is_sending.borrow() || switching.get() {
                return;
            }
            let target_id = row.widget_name().to_string();
            if target_id.is_empty() {
                return;
            }
            if session_id.borrow().as_deref() == Some(target_id.as_str()) {
                return;
            }
            switching.set(true);
            clear_approval();
            set_error(None);
            let messages = messages.clone();
            let session_id = session_id.clone();
            let refresh_messages = refresh_messages.clone();
            let refresh_sessions = refresh_sessions.clone();
            let set_error = set_error.clone();
            let switching = switching.clone();
            let follow_bottom = follow_bottom.clone();
            let assistant_name = assistant_name.clone();
            let (tx, rx) = mpsc::channel::<Result<(String, Vec<ChatMessage>), String>>();
            thread::spawn(move || {
                let _ = tx.send(resume_session(&target_id));
            });
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(Ok((sid, history))) => {
                    save_session_id(&sid);
                    *session_id.borrow_mut() = Some(sid);
                    *messages.borrow_mut() = history;
                    *assistant_name.borrow_mut() = load_assistant_display_name();
                    follow_bottom.set(true);
                    refresh_messages();
                    refresh_sessions();
                    switching.set(false);
                    glib::ControlFlow::Break
                }
                Ok(Err(error)) => {
                    set_error(Some(error));
                    switching.set(false);
                    glib::ControlFlow::Break
                }
                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(mpsc::TryRecvError::Disconnected) => {
                    switching.set(false);
                    glib::ControlFlow::Break
                }
            });
        });
    }

    let show_approval: Rc<dyn Fn(ApprovalRequest)> = Rc::new({
        let approval_box = approval_box.clone();
        let approval_detail = approval_detail.clone();
        let approval_buttons = approval_buttons.clone();
        let pending_approval_tx = pending_approval_tx.clone();
        let clear_approval = clear_approval.clone();
        move |request: ApprovalRequest| {
            while let Some(child) = approval_buttons.first_child() {
                approval_buttons.remove(&child);
            }
            let detail = if request.description.trim().is_empty() {
                request.command.clone()
            } else if request.command.trim().is_empty() {
                request.description.clone()
            } else {
                format!("{}\n\n{}", request.description, request.command)
            };
            approval_detail.set_label(&detail);
            approval_box.set_visible(true);

            let choices = if request.choices.is_empty() {
                vec![
                    "once".to_owned(),
                    "session".to_owned(),
                    "always".to_owned(),
                    "deny".to_owned(),
                ]
            } else {
                request.choices.clone()
            };
            for choice in choices {
                let label = match choice.as_str() {
                    "once" => "Allow once",
                    "session" => "Allow this session",
                    "always" => "Always allow",
                    "deny" => "Deny",
                    other => other,
                };
                let button = gtk::Button::with_label(label);
                if choice == "deny" {
                    button.add_css_class("destructive-action");
                } else {
                    button.add_css_class("suggested-action");
                }
                let session_key = request.session_key.clone();
                let choice_id = choice.clone();
                let pending_approval_tx = pending_approval_tx.clone();
                let clear_approval = clear_approval.clone();
                button.connect_clicked(move |_| {
                    if let Some(tx) = pending_approval_tx.borrow().as_ref() {
                        let _ = tx.send(ApprovalDecision {
                            session_key: session_key.clone(),
                            choice: choice_id.clone(),
                        });
                    }
                    clear_approval();
                });
                approval_buttons.append(&button);
            }
        }
    });

    let submit: Rc<dyn Fn()> = Rc::new({
        let messages = messages.clone();
        let session_id = session_id.clone();
        let input = input.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let set_sending = set_sending.clone();
        let is_sending = is_sending.clone();
        let show_approval = show_approval.clone();
        let clear_approval = clear_approval.clone();
        let pending_approval_tx = pending_approval_tx.clone();
        let follow_bottom = follow_bottom.clone();
        let assistant_name = assistant_name.clone();
        let title = title.clone();
        move || {
            if *is_sending.borrow() {
                return;
            }
            let text = input.text().to_string();
            if text.trim().is_empty() {
                return;
            }
            // Soul save clears the on-disk session pointer — drop the stale
            // in-memory session so the next turn loads the new SOUL.md cleanly.
            let _ = honor_soul_session_reset(&session_id, &messages);
            // Always refresh the title from disk so Settings → Name shows up.
            *assistant_name.borrow_mut() = load_assistant_display_name();
            title.set_label(&format!("Chat with {}", assistant_name.borrow()));
            input.set_text("");
            follow_bottom.set(true);
            messages.borrow_mut().push(ChatMessage {
                role: ChatRole::User,
                content: text.clone(),
            });
            refresh_messages();
            set_error(None);
            clear_approval();
            set_sending(true);

            let (event_tx, event_rx) = mpsc::channel::<WorkerEvent>();
            let (approval_tx, approval_rx) = mpsc::channel::<ApprovalDecision>();
            *pending_approval_tx.borrow_mut() = Some(approval_tx);

            // Re-read pointer after Soul reset; create a new session if needed.
            let sid_for_worker = session_id.borrow().clone().or_else(load_session_id);
            if let Some(ref sid) = sid_for_worker {
                *session_id.borrow_mut() = Some(sid.clone());
            }
            thread::spawn(move || {
                let sid = match sid_for_worker {
                    Some(sid) => sid,
                    None => match ensure_session_id() {
                        Ok(sid) => sid,
                        Err(err) => {
                            let _ = event_tx.send(WorkerEvent::Done(Err(err)));
                            return;
                        }
                    },
                };
                run_chat_turn(sid, text, event_tx, approval_rx);
            });

            let messages = messages.clone();
            let session_id = session_id.clone();
            let refresh_messages = refresh_messages.clone();
            let refresh_sessions = refresh_sessions.clone();
            let set_error = set_error.clone();
            let set_sending = set_sending.clone();
            let show_approval = show_approval.clone();
            let clear_approval = clear_approval.clone();
            let pending_approval_tx = pending_approval_tx.clone();
            let follow_bottom = follow_bottom.clone();
            glib::timeout_add_local(Duration::from_millis(50), move || {
                match event_rx.try_recv() {
                    Ok(WorkerEvent::Approval(request)) => {
                        show_approval(request);
                        glib::ControlFlow::Continue
                    }
                    Ok(WorkerEvent::Done(result)) => {
                        set_sending(false);
                        clear_approval();
                        *pending_approval_tx.borrow_mut() = None;
                        match result {
                            Ok(turn) => {
                                save_session_id(&turn.session_id);
                                *session_id.borrow_mut() = Some(turn.session_id);
                                messages.borrow_mut().push(ChatMessage {
                                    role: ChatRole::Assistant,
                                    content: turn.text,
                                });
                                follow_bottom.set(true);
                                refresh_messages();
                                refresh_sessions();
                            }
                            Err(err) => set_error(Some(err)),
                        }
                        glib::ControlFlow::Break
                    }
                    Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    Err(mpsc::TryRecvError::Disconnected) => {
                        set_sending(false);
                        clear_approval();
                        *pending_approval_tx.borrow_mut() = None;
                        set_error(Some(
                            "Centurion connection dropped before a reply arrived.".to_owned(),
                        ));
                        glib::ControlFlow::Break
                    }
                }
            });
        }
    });

    send_button.connect_clicked({
        let submit = submit.clone();
        move |_| submit()
    });
    input.connect_activate({
        let submit = submit.clone();
        move |_| submit()
    });

    glib::idle_add_local_once({
        let input = input.clone();
        move || {
            input.grab_focus();
        }
    });

    container
}
