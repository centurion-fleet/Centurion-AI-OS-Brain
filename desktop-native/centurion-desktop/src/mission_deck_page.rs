//! Missions tab — embeds the React Mission Deck (web-dashboard) via WebKitGTK.
//!
//! Replaces the legacy GTK `home_page` stack view as the primary Missions UI.
//! Settings dialogs may still call into `home_page` for back-office edits.

use libadwaita as adw;
use adw::prelude::*;
use gio;
use gtk4 as gtk;
use gtk4::glib;
use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, Instant};

use crate::chat_page::DiscussTopic;
use crate::home_page::{HomeHandle, HomeHooks};

const DECK_HOST: &str = "127.0.0.1";
const DECK_PORT: u16 = 9120;
const DECK_URL: &str = "http://127.0.0.1:9120/";

/// Resolve where `web-dashboard` (with `server.js` + `dist/`) lives.
pub fn resolve_mission_deck_dir() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("CENTURION_MISSION_DECK_DIR") {
        let path = PathBuf::from(p);
        if path.join("server.js").is_file() {
            return Some(path);
        }
    }

    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        let installed = home.join(".local/share/centurion/mission-deck");
        if installed.join("server.js").is_file() {
            return Some(installed);
        }
    }

    // Compile-time path: …/Centurion-AI-OS/desktop-native/centurion-desktop → repo/web-dashboard
    let from_manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../web-dashboard");
    if let Ok(canon) = from_manifest.canonicalize() {
        if canon.join("server.js").is_file() {
            return Some(canon);
        }
    }

    None
}

fn find_node() -> PathBuf {
    if let Ok(p) = std::env::var("CENTURION_NODE") {
        return PathBuf::from(p);
    }
    PathBuf::from("node")
}

fn deck_healthy() -> bool {
    ureq::get("http://127.0.0.1:9120/api/health")
        .timeout(Duration::from_millis(800))
        .call()
        .map(|r| r.status() == 200)
        .unwrap_or(false)
}

const READY_CACHE_SECS: u64 = 30;

struct DeckSupervisor {
    child: Option<Child>,
    dir: PathBuf,
    last_ready: Option<Instant>,
}

impl DeckSupervisor {
    fn new(dir: PathBuf) -> Self {
        Self {
            child: None,
            dir,
            last_ready: None,
        }
    }

    fn mark_ready(&mut self) {
        self.last_ready = Some(Instant::now());
    }

    /// True when health succeeded recently — skip spawn/wait on tab show.
    fn ready_recently(&self) -> bool {
        match self.last_ready {
            Some(t) if t.elapsed() < Duration::from_secs(READY_CACHE_SECS) => deck_healthy(),
            _ => false,
        }
    }

    /// Blocking spawn + readiness wait — call only from a background thread.
    fn ensure_running(&mut self) -> Result<(), String> {
        if deck_healthy() {
            self.mark_ready();
            return Ok(());
        }
        if let Some(child) = self.child.as_mut() {
            match child.try_wait() {
                Ok(Some(_)) | Err(_) => self.child = None,
                Ok(None) => {}
            }
        }
        if self.child.is_none() {
            self.spawn()?;
        }
        for _ in 0..40 {
            if deck_healthy() {
                self.mark_ready();
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(200));
        }
        Err(
            "Mission Deck server did not become ready on http://127.0.0.1:9120. \
             Run `cd web-dashboard && npm run build && npm start`, or set CENTURION_MISSION_DECK_DIR."
                .into(),
        )
    }

    fn spawn(&mut self) -> Result<(), String> {
        let server = self.dir.join("server.js");
        if !server.is_file() {
            return Err(format!("Missing {}", server.display()));
        }
        let dist = self.dir.join("dist");
        if !dist.join("index.html").is_file() {
            return Err(format!(
                "Mission Deck not built — missing {}. Run: cd web-dashboard && npm run build",
                dist.join("index.html").display()
            ));
        }

        let mut cmd = Command::new(find_node());
        cmd.arg(&server)
            .current_dir(&self.dir)
            .env("MISSION_DECK_HOST", DECK_HOST)
            .env("MISSION_DECK_PORT", DECK_PORT.to_string())
            .env("CENTURION_DECK_SSE_MS", "15000")
            .env(
                "CENTURION_HOME",
                crate::chat_page::resolve_centurion_home(),
            )
            .env(
                "CENTURION_BRIDGE_SOCKET",
                crate::bridge_client::bridge_socket_path(),
            )
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());

        if let Ok(root) = self.dir.join("..").canonicalize() {
            let venv = root.join(".venv/bin/python");
            if venv.is_file() {
                cmd.env("CENTURION_PYTHON", venv);
            }
            // Align with Brain bridge: prefer checkout over orphan packages.
            cmd.env("CENTURION_AI_REPO", &root);
            let mut pythonpath = root.display().to_string();
            if let Ok(existing) = std::env::var("PYTHONPATH") {
                let trimmed = existing.trim();
                if !trimmed.is_empty() {
                    pythonpath.push(':');
                    pythonpath.push_str(trimmed);
                }
            }
            cmd.env("PYTHONPATH", pythonpath);
        }

        let child = cmd
            .spawn()
            .map_err(|e| format!("Failed to start Mission Deck (node): {e}"))?;
        self.child = Some(child);
        Ok(())
    }
}

impl Drop for DeckSupervisor {
    fn drop(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// Build the Missions tab: WebKit view of Mission Deck, with GTK fallback message.
pub fn build(hooks: HomeHooks) -> (gtk::Box, HomeHandle) {
    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.set_hexpand(true);
    root.set_vexpand(true);
    root.add_css_class("centurion-mission-deck-host");

    let attention = Rc::new(Cell::new(0u32));
    let hooks = Rc::new(hooks);
    // Window starts on Chat — keep Deck suspended until Missions is shown.
    let suspended = Rc::new(Cell::new(true));
    // GTK widgets are !Send — keep WebView on the UI thread via Rc/RefCell.
    let webview_slot: Rc<RefCell<Option<webkit6::WebView>>> = Rc::new(RefCell::new(None));

    let status = gtk::Label::new(Some("Opening Mission Deck…"));
    status.add_css_class("centurion-mission-deck-status");
    status.set_wrap(true);
    status.set_margin_top(24);
    status.set_margin_bottom(12);
    status.set_margin_start(24);
    status.set_margin_end(24);
    root.append(&status);

    let supervisor: Rc<RefCell<Option<Arc<Mutex<DeckSupervisor>>>>> = Rc::new(RefCell::new(
        resolve_mission_deck_dir().map(|dir| Arc::new(Mutex::new(DeckSupervisor::new(dir)))),
    ));

    let root_weak = root.downgrade();
    let supervisor_c = supervisor.clone();
    let hooks_c = hooks.clone();
    let webview_slot_c = webview_slot.clone();
    let suspended_c = suspended.clone();
    let status_c = status.clone();

    // Pre-warm Node on a background thread as soon as the tab is built (window
    // show path) so Chat stays responsive and Focus often finds a ready deck.
    let (tx, rx) = mpsc::channel::<Result<(), String>>();
    {
        let supervisor_bg = supervisor_c.borrow().clone();
        std::thread::spawn(move || {
            let result = match supervisor_bg {
                Some(m) => m
                    .lock()
                    .map_err(|e| e.to_string())
                    .and_then(|mut s| s.ensure_running()),
                None => Err(
                    "Mission Deck not found. Build web-dashboard (`npm run build`) and install, \
                     or set CENTURION_MISSION_DECK_DIR."
                        .into(),
                ),
            };
            let _ = tx.send(result);
        });
    }
    glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
        Ok(result) => {
            let Some(root) = root_weak.upgrade() else {
                return glib::ControlFlow::Break;
            };
            match result {
                Ok(()) => {
                    status_c.set_visible(false);
                    if webview_slot_c.borrow().is_none() {
                        match attach_webview(&root, hooks_c.clone(), suspended_c.clone()) {
                            Some(wv) => {
                                apply_deck_suspend(&wv, suspended_c.get());
                                *webview_slot_c.borrow_mut() = Some(wv);
                            }
                            None => {
                                status_c.set_visible(true);
                                status_c.set_label(
                                    "WebKitGTK is required for Mission Deck. Install webkitgtk6.0 and rebuild.",
                                );
                            }
                        }
                    }
                }
                Err(err) => {
                    status_c.set_visible(true);
                    status_c.set_label(&err);
                }
            }
            glib::ControlFlow::Break
        }
        Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
        Err(mpsc::TryRecvError::Disconnected) => {
            status_c.set_visible(true);
            status_c.set_label("Mission Deck failed to start.");
            glib::ControlFlow::Break
        }
    });

    let refresh: Rc<dyn Fn()> = {
        let supervisor = supervisor.clone();
        let webview_slot = webview_slot.clone();
        let suspended = suspended.clone();
        Rc::new(move || {
            // Soft path: never block the UI thread on Node health waits.
            if let Some(m) = supervisor.borrow().as_ref() {
                let skip = m
                    .lock()
                    .map(|s| s.ready_recently())
                    .unwrap_or(false);
                if !skip {
                    let m = m.clone();
                    std::thread::spawn(move || {
                        if let Ok(mut s) = m.lock() {
                            let _ = s.ensure_running();
                        }
                    });
                }
            }
            // Never hard-reload while suspended — that resets __centurionDeckVisible
            // to false and leaves the React deck stuck on "Opening your deck…".
            if suspended.get() {
                return;
            }
            if let Some(wv) = webview_slot.borrow().as_ref() {
                // Soft resume: push visibility into the live page so polls start.
                // Avoid wv.reload() here — reload races the visibility flag.
                apply_deck_suspend(wv, false);
            }
        })
    };

    let notify_tab_visible: Rc<dyn Fn(bool)> = {
        let webview_slot = webview_slot.clone();
        let suspended = suspended.clone();
        let supervisor = supervisor.clone();
        Rc::new(move |visible: bool| {
            let now_suspended = !visible;
            suspended.set(now_suspended);
            if visible {
                if let Some(m) = supervisor.borrow().as_ref() {
                    let skip = m
                        .lock()
                        .map(|s| s.ready_recently())
                        .unwrap_or(false);
                    if !skip {
                        let m = m.clone();
                        std::thread::spawn(move || {
                            if let Ok(mut s) = m.lock() {
                                let _ = s.ensure_running();
                            }
                        });
                    }
                }
            }
            if let Some(wv) = webview_slot.borrow().as_ref() {
                apply_deck_suspend(wv, now_suspended);
            }
        })
    };

    let handle = HomeHandle::new(refresh, attention.clone(), notify_tab_visible);

    {
        let attention = attention.clone();
        let hooks = hooks.clone();
        let suspended = suspended.clone();
        glib::timeout_add_seconds_local(12, move || {
            if suspended.get() {
                return glib::ControlFlow::Continue;
            }
            let attention = attention.clone();
            let hooks = hooks.clone();
            let (tx, rx) = std::sync::mpsc::channel::<u32>();
            std::thread::spawn(move || {
                let n = crate::chat_page::run_bridge_action(
                    "life_decisions_list",
                    serde_json::json!({ "limit": 20 }),
                )
                .as_ref()
                .and_then(|b| b.get("decisions"))
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter(|d| {
                            d.get("chosen")
                                .and_then(|c| c.as_str())
                                .unwrap_or("")
                                .is_empty()
                        })
                        .count() as u32
                })
                .unwrap_or(0);
                let _ = tx.send(n);
            });
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(n) => {
                    if attention.get() != n {
                        attention.set(n);
                        (hooks.on_attention_changed)(n);
                    }
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            });
            glib::ControlFlow::Continue
        });
    }

    (root, handle)
}

/// Mute WebView media and tell the React deck to pause SSE / stack polls.
fn apply_deck_suspend(webview: &webkit6::WebView, suspended: bool) {
    use webkit6::prelude::WebViewExt;
    webview.set_is_muted(suspended);
    let flag = if suspended { "false" } else { "true" };
    let script = format!(
        r#"(function(){{
  window.__centurionDeckVisible = {flag};
  try {{
    window.dispatchEvent(new CustomEvent('centurion-deck-visibility', {{
      detail: {{ visible: {flag} }}
    }}));
  }} catch (e) {{}}
}})();"#
    );
    webview.evaluate_javascript(&script, None, None, gio::Cancellable::NONE, |_| {});
}

fn attach_webview(
    root: &gtk::Box,
    hooks: Rc<HomeHooks>,
    suspended: Rc<Cell<bool>>,
) -> Option<webkit6::WebView> {
    use webkit6::prelude::*;

    let ucm = webkit6::UserContentManager::new();
    let _ = ucm.register_script_message_handler("centurion", None);

    let settings = webkit6::Settings::new();
    settings.set_enable_developer_extras(cfg!(debug_assertions));

    let webview = webkit6::WebView::builder()
        .user_content_manager(&ucm)
        .settings(&settings)
        .hexpand(true)
        .vexpand(true)
        .build();

    let script = webkit6::UserScript::new(
        r#"
        // Default false for Brain embed; GTK re-applies true after load when
        // the Missions tab is visible (see connect_load_changed).
        if (typeof window.__centurionDeckVisible === 'undefined') {
          window.__centurionDeckVisible = false;
        }
        window.centurionDiscuss = function(payload) {
          try {
            var msg = typeof payload === 'string' ? payload : JSON.stringify(payload);
            window.webkit.messageHandlers.centurion.postMessage(msg);
          } catch (e) {}
        };
        window.centurionOpenChat = window.centurionDiscuss;
        "#,
        webkit6::UserContentInjectedFrames::TopFrame,
        webkit6::UserScriptInjectionTime::Start,
        &[],
        &[],
    );
    ucm.add_script(&script);

    // After every navigation/reload, re-push tab visibility so React polls start.
    // Also retry shortly after Finished — React may mount after the first inject.
    {
        let suspended = suspended.clone();
        webview.connect_load_changed(move |wv, event| {
            if event != webkit6::LoadEvent::Finished {
                return;
            }
            apply_deck_suspend(wv, suspended.get());
            let wv = wv.clone();
            let suspended = suspended.clone();
            glib::timeout_add_local(Duration::from_millis(300), move || {
                apply_deck_suspend(&wv, suspended.get());
                glib::ControlFlow::Break
            });
        });
    }

    {
        let hooks = hooks.clone();
        ucm.connect_script_message_received(Some("centurion"), move |_ucm, value| {
            let raw = js_value_to_string(value);
            if raw.is_empty() {
                return;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
                let kind = v
                    .get("kind")
                    .and_then(|t| t.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if kind == "decision" {
                    let title = v
                        .get("title")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Decision")
                        .to_string();
                    let id = v
                        .get("id")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let chosen = v
                        .get("chosen")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let context = v
                        .get("context")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let mission_id = v
                        .get("mission_id")
                        .and_then(|t| t.as_str())
                        .map(str::to_string);
                    let mission_title = v
                        .get("mission_title")
                        .and_then(|t| t.as_str())
                        .map(str::to_string);
                    let target_id = v
                        .get("target_id")
                        .and_then(|t| t.as_str())
                        .map(str::to_string);
                    let kickoff = v
                        .get("kickoff")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Let's revisit this decision.")
                        .to_string();
                    let topic = DiscussTopic::Decision {
                        id: if id.is_empty() {
                            title.clone()
                        } else {
                            id
                        },
                        title,
                        chosen,
                        context,
                        mission_id,
                        mission_title,
                        target_id,
                    };
                    (hooks.on_ask_about)(topic, kickoff);
                    return;
                }
                if kind == "document" {
                    let title = v
                        .get("title")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Document")
                        .to_string();
                    let id = v
                        .get("id")
                        .and_then(|t| t.as_str())
                        .filter(|s| !s.is_empty())
                        .map(str::to_string);
                    let mission_id = v
                        .get("mission_id")
                        .and_then(|t| t.as_str())
                        .filter(|s| !s.is_empty())
                        .map(str::to_string);
                    let doc_type = v
                        .get("doc_type")
                        .and_then(|t| t.as_str())
                        .filter(|s| !s.is_empty())
                        .map(str::to_string);
                    let summary = v
                        .get("summary")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let body_excerpt = v
                        .get("body_excerpt")
                        .or_else(|| v.get("body_md"))
                        .or_else(|| v.get("body"))
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let plan_id = v
                        .get("plan_id")
                        .and_then(|t| t.as_str())
                        .filter(|s| !s.is_empty())
                        .map(str::to_string);
                    let kickoff = v
                        .get("kickoff")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Let's evolve this document.")
                        .to_string();
                    let topic = DiscussTopic::Document {
                        id,
                        mission_id,
                        doc_type,
                        title,
                        summary,
                        plan_id,
                        body_excerpt,
                    };
                    (hooks.on_ask_about)(topic, kickoff);
                    return;
                }
                let title = v
                    .get("title")
                    .and_then(|t| t.as_str())
                    .unwrap_or("Mission")
                    .to_string();
                let statement = v
                    .get("statement")
                    .and_then(|t| t.as_str())
                    .unwrap_or("")
                    .to_string();
                let id = v.get("id").and_then(|t| t.as_str()).map(str::to_string);
                let kickoff = v
                    .get("kickoff")
                    .and_then(|t| t.as_str())
                    .unwrap_or("Let's talk about this mission.")
                    .to_string();
                let topic = DiscussTopic::Mission {
                    statement: if statement.is_empty() {
                        title.clone()
                    } else {
                        statement
                    },
                    id,
                    title: Some(title),
                    target_id: v
                        .get("target_id")
                        .and_then(|t| t.as_str())
                        .map(str::to_string),
                    target_title: v
                        .get("target_title")
                        .and_then(|t| t.as_str())
                        .map(str::to_string),
                    target_type: v
                        .get("target_type")
                        .and_then(|t| t.as_str())
                        .map(str::to_string),
                    target_description: v
                        .get("target_description")
                        .and_then(|t| t.as_str())
                        .map(str::to_string),
                    target_status: v
                        .get("target_status")
                        .and_then(|t| t.as_str())
                        .map(str::to_string),
                    sequence_number: v
                        .get("sequence_number")
                        .and_then(|t| t.as_i64())
                        .or_else(|| {
                            v.get("sequence_number")
                                .and_then(|t| t.as_u64())
                                .map(|n| n as i64)
                        }),
                };
                (hooks.on_ask_about)(topic, kickoff);
            }
        });
    }

    webview.load_uri(DECK_URL);
    webview.set_hexpand(true);
    webview.set_vexpand(true);
    root.append(&webview);
    Some(webview)
}

fn js_value_to_string(value: &javascriptcore6::Value) -> String {
    // postMessage(string) arrives as a JS string; fall back to JSON.
    if value.is_string() {
        return value.to_str().to_string();
    }
    value
        .to_json(0)
        .map(|s| {
            let t = s.trim();
            if t.starts_with('"') && t.ends_with('"') {
                serde_json::from_str::<String>(t).unwrap_or_else(|_| t.to_string())
            } else {
                s.to_string()
            }
        })
        .unwrap_or_default()
}

#[allow(dead_code)]
pub fn deck_dir_display() -> String {
    resolve_mission_deck_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|| "(not found)".into())
}
