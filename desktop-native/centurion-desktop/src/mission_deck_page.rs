//! Missions tab — embeds the React Mission Deck (web-dashboard) via WebKitGTK.
//!
//! Replaces the legacy GTK `home_page` stack view as the primary Missions UI.
//! Settings dialogs may still call into `home_page` for back-office edits.

use libadwaita as adw;
use adw::prelude::*;
use gtk4 as gtk;
use gtk4::glib;
use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::Mutex;
use std::time::Duration;

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

struct DeckSupervisor {
    child: Option<Child>,
    dir: PathBuf,
}

impl DeckSupervisor {
    fn new(dir: PathBuf) -> Self {
        Self { child: None, dir }
    }

    fn ensure_running(&mut self) -> Result<(), String> {
        if deck_healthy() {
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
            .env("CENTURION_DECK_SSE_MS", "5000")
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

    let status = gtk::Label::new(Some("Opening Mission Deck…"));
    status.add_css_class("centurion-mission-deck-status");
    status.set_wrap(true);
    status.set_margin_top(24);
    status.set_margin_bottom(12);
    status.set_margin_start(24);
    status.set_margin_end(24);
    root.append(&status);

    let supervisor: Rc<RefCell<Option<Mutex<DeckSupervisor>>>> = Rc::new(RefCell::new(
        resolve_mission_deck_dir().map(|dir| Mutex::new(DeckSupervisor::new(dir))),
    ));

    let root_weak = root.downgrade();
    let supervisor_c = supervisor.clone();
    let hooks_c = hooks.clone();

    // Poll server readiness on the main thread (no std::thread::spawn needed).
    // Retries up to ~8 seconds before showing the fallback message.
    glib::timeout_add_seconds_local(0, move || {
        let result: Result<(), String> = match supervisor_c.borrow().as_ref() {
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

        let Some(root) = root_weak.upgrade() else {
            return glib::ControlFlow::Break;
        };
        match result {
            Ok(()) => {
                status.set_visible(false);
                if attach_webview(&root, hooks_c.clone()).is_none() {
                    status.set_visible(true);
                    status.set_label(
                        "WebKitGTK is required for Mission Deck. Install webkitgtk6.0 and rebuild.",
                    );
                }
            }
            Err(err) => {
                status.set_visible(true);
                status.set_label(&err);
            }
        }
        glib::ControlFlow::Break
    });

    let refresh: Rc<dyn Fn()> = {
        let supervisor = supervisor.clone();
        let root = root.clone();
        Rc::new(move || {
            if let Some(m) = supervisor.borrow().as_ref() {
                if let Ok(mut s) = m.lock() {
                    let _ = s.ensure_running();
                }
            }
            if let Some(child) = root.first_child() {
                let mut w = Some(child);
                while let Some(widget) = w {
                    if let Ok(wv) = widget.clone().downcast::<webkit6::WebView>() {
                        use webkit6::prelude::WebViewExt;
                        wv.reload();
                        break;
                    }
                    w = widget.next_sibling();
                }
            }
        })
    };

    let handle = HomeHandle::new(refresh, attention.clone());

    {
        let attention = attention.clone();
        let hooks = hooks.clone();
        glib::timeout_add_seconds_local(12, move || {
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

fn attach_webview(root: &gtk::Box, hooks: Rc<HomeHooks>) -> Option<webkit6::WebView> {
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

    {
        let hooks = hooks.clone();
        ucm.connect_script_message_received(Some("centurion"), move |_ucm, value| {
            let raw = js_value_to_string(value);
            if raw.is_empty() {
                return;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
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
