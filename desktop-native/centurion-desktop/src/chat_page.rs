//! Phone-like bubble chat for the Linux Brain Chat tab.
//!
//! Drives the local Centurion agent via `centurion_cli.remote_bridge`
//! (same path as iPhone Crypto Chat), with mid-turn tool approvals.

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;
use serde_json::Value;
use std::cell::RefCell;
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

fn session_store_path() -> PathBuf {
    let home = std::env::var("CENTURION_HOME")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".centurion")))
        .unwrap_or_else(|| PathBuf::from(".centurion"));
    home.join("desktop_chat_session")
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
    let mut child = Command::new(resolve_bridge_python())
        .args(["-m", "centurion_cli.remote_bridge"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
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
    messages
        .into_iter()
        .filter_map(|msg| {
            let role = msg.get("role")?.as_str()?;
            let content = match msg.get("content") {
                Some(Value::String(s)) => s.trim().to_owned(),
                Some(Value::Array(parts)) => parts
                    .iter()
                    .filter_map(|part| {
                        if let Some(text) = part.as_str() {
                            return Some(text);
                        }
                        part.get("text").and_then(|v| v.as_str())
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

    let mut child = match Command::new(resolve_bridge_python())
        .args(["-m", "centurion_cli.remote_bridge"])
        .env("CENTURION_REMOTE_EVENTS", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
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

fn message_row(message: &ChatMessage) -> gtk::ListBoxRow {
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
                .label("Centurion")
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

/// Build the Chat tab page (bubble UI + always-visible composer).
pub fn build() -> gtk::Box {
    let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
    container.set_vexpand(true);
    container.set_hexpand(true);

    // Overlay pins the composer to the bottom of the allocated page area.
    // Nested ToolbarView/Stack layouts were clipping the entry off-screen.
    let overlay = gtk::Overlay::new();
    overlay.set_vexpand(true);
    overlay.set_hexpand(true);

    let main = gtk::Box::new(gtk::Orientation::Vertical, 0);
    main.set_vexpand(true);
    main.set_hexpand(true);

    let top = gtk::Box::new(gtk::Orientation::Vertical, 4);
    top.set_margin_top(12);
    top.set_margin_start(16);
    top.set_margin_end(16);
    top.set_margin_bottom(8);
    top.set_vexpand(false);
    top.append(
        &gtk::Label::builder()
            .label("Chat")
            .css_classes(["title-1"])
            .xalign(0.0)
            .build(),
    );
    top.append(
        &gtk::Label::builder()
            .label(
                "Local chat on this brain — no iPhone required. Message box is at the bottom.",
            )
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );
    let new_chat_button = gtk::Button::with_label("New chat");
    new_chat_button.set_halign(gtk::Align::Start);
    new_chat_button.set_tooltip_text(Some(
        "Start a fresh conversation on this brain (clears the on-screen transcript).",
    ));
    top.append(&new_chat_button);
    main.append(&top);

    let messages: Rc<RefCell<Vec<ChatMessage>>> = Rc::new(RefCell::new(Vec::new()));
    let session_id: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(load_session_id()));
    let is_sending = Rc::new(RefCell::new(false));

    let message_list = gtk::ListBox::new();
    message_list.set_selection_mode(gtk::SelectionMode::None);
    message_list.add_css_class("boxed-list");
    message_list.set_margin_start(12);
    message_list.set_margin_end(12);
    message_list.set_margin_top(4);
    // Leave room so the last bubble is not hidden under the overlaid composer.
    message_list.set_margin_bottom(96);

    let message_scroll = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .propagate_natural_height(false)
        .build();
    message_scroll.set_child(Some(&message_list));
    main.append(&message_scroll);
    overlay.set_child(Some(&main));

    let bottom = gtk::Box::new(gtk::Orientation::Vertical, 0);
    bottom.add_css_class("centurion-chat-composer");
    bottom.set_halign(gtk::Align::Fill);
    bottom.set_valign(gtk::Align::End);
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
    overlay.add_overlay(&bottom);

    container.append(&overlay);

    let refresh_messages: Rc<dyn Fn()> = Rc::new({
        let message_list = message_list.clone();
        let messages = messages.clone();
        let message_scroll = message_scroll.clone();
        move || {
            while let Some(child) = message_list.first_child() {
                message_list.remove(&child);
            }
            let msgs = messages.borrow();
            if msgs.is_empty() {
                message_list.append(&message_row(&ChatMessage {
                    role: ChatRole::System,
                    content:
                        "Your private conversation starts here. Use the message box at the bottom of this page."
                            .to_owned(),
                }));
            } else {
                for message in msgs.iter() {
                    message_list.append(&message_row(message));
                }
            }
            let adj = message_scroll.vadjustment();
            glib::idle_add_local_once(move || {
                adj.set_value(adj.upper());
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
        }
    });

    {
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let (tx, rx) = mpsc::channel::<(String, Vec<ChatMessage>)>();
        thread::spawn(move || {
            let Ok(sid) = ensure_session_id() else {
                return;
            };
            let history = load_history(&sid);
            let _ = tx.send((sid, history));
        });
        glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
            Ok((sid, history)) => {
                *session_id.borrow_mut() = Some(sid);
                if !history.is_empty() {
                    *messages.borrow_mut() = history;
                }
                refresh_messages();
                glib::ControlFlow::Break
            }
            Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        });
    }
    refresh_messages();

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

    {
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let set_error = set_error.clone();
        let clear_approval = clear_approval.clone();
        let set_sending = set_sending.clone();
        let is_sending = is_sending.clone();
        new_chat_button.connect_clicked(move |_| {
            if *is_sending.borrow() {
                return;
            }
            clear_approval();
            set_sending(false);
            set_error(None);
            messages.borrow_mut().clear();
            *session_id.borrow_mut() = None;
            let path = session_store_path();
            let _ = std::fs::remove_file(&path);
            refresh_messages();
            let messages = messages.clone();
            let session_id = session_id.clone();
            let refresh_messages = refresh_messages.clone();
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
        let set_error = set_error.clone();
        let set_sending = set_sending.clone();
        let is_sending = is_sending.clone();
        let show_approval = show_approval.clone();
        let clear_approval = clear_approval.clone();
        let pending_approval_tx = pending_approval_tx.clone();
        move || {
            if *is_sending.borrow() {
                return;
            }
            let text = input.text().to_string();
            if text.trim().is_empty() {
                return;
            }
            input.set_text("");
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

            let sid_for_worker = session_id.borrow().clone();
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
            let set_error = set_error.clone();
            let set_sending = set_sending.clone();
            let show_approval = show_approval.clone();
            let clear_approval = clear_approval.clone();
            let pending_approval_tx = pending_approval_tx.clone();
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
                                refresh_messages();
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
