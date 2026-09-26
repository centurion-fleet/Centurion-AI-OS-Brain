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
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::discuss::DiscussTopic;
use crate::home_page::{HomeHandle, HomeHooks};

const DECK_HOST: &str = "127.0.0.1";
const DECK_PORT: u16 = 9120;
const DECK_URL: &str = "http://127.0.0.1:9120/";
const COLLAB_URL: &str = "http://127.0.0.1:9120/conjunction.html";

#[derive(Clone, Copy)]
enum DeckAttention {
    LifeDecisions,
    SwarmWaiting,
}

fn deck_role(attention: DeckAttention) -> &'static str {
    match attention {
        DeckAttention::LifeDecisions => "focus",
        DeckAttention::SwarmWaiting => "collab",
    }
}

const PENDING_PLAN_STATUSES: &[&str] = &[
    "pending_review",
    "held",
    "adjusted",
    "proposed",
    "pending",
];

/// Focus tab badge: only “Decisions needed” (open choices + pending plans).
fn focus_attention_count() -> u32 {
    count_open_decisions().saturating_add(count_pending_plans())
}

fn collab_seen_path() -> std::path::PathBuf {
    std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
        .join("brain_collab_seen.json")
}

fn load_collab_seen_unix() -> u64 {
    std::fs::read_to_string(collab_seen_path())
        .ok()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
        .and_then(|v| v.get("seen_unix").and_then(|x| x.as_u64()))
        .unwrap_or(0)
}

fn mark_collab_viewed() {
    let path = collab_seen_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let payload = serde_json::json!({ "seen_unix": unix_secs() });
    if let Ok(bytes) = serde_json::to_vec(&payload) {
        let _ = std::fs::write(path, bytes);
    }
}

fn parse_iso_unix(raw: &str) -> u64 {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return 0;
    }
    glib::DateTime::from_iso8601(trimmed, None)
        .ok()
        .map(|dt| dt.to_unix().max(0) as u64)
        .unwrap_or(0)
}

fn count_open_decisions() -> u32 {
    crate::bridge_actions::run_bridge_action(
        "life_decisions_list",
        serde_json::json!({ "limit": 200 }),
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
    .unwrap_or(0)
}

fn count_pending_plans() -> u32 {
    crate::bridge_actions::run_bridge_action(
        "plans_list",
        serde_json::json!({ "status": "pending_review" }),
    )
    .as_ref()
    .and_then(|b| b.get("plans"))
    .and_then(|v| v.as_array())
    .map(|arr| {
        arr.iter()
            .filter(|p| {
                let st = p
                    .get("status")
                    .and_then(|s| s.as_str())
                    .unwrap_or("pending_review")
                    .to_ascii_lowercase();
                PENDING_PLAN_STATUSES.iter().any(|x| *x == st)
            })
            .count() as u32
    })
    .unwrap_or(0)
}

/// Collab tab badge: items newer than the last time the user opened Collab.
fn swarm_attention_count() -> u32 {
    let last_seen = load_collab_seen_unix();
    crate::bridge_actions::run_bridge_action("swarm_snapshot", serde_json::json!({}))
        .as_ref()
        .and_then(|b| b.get("swarms"))
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .map(|s| unseen_collab_items(s, last_seen))
                .sum::<u32>()
        })
        .unwrap_or(0)
}

fn unseen_collab_items(swarm: &serde_json::Value, last_seen: u64) -> u32 {
    if let Some(cards) = swarm.get("cards").and_then(|c| c.as_array()) {
        if !cards.is_empty() {
            return cards
                .iter()
                .filter(|c| {
                    let ts = c
                        .get("created_at")
                        .and_then(|t| t.as_str())
                        .map(parse_iso_unix)
                        .unwrap_or(0);
                    ts > last_seen
                })
                .count() as u32;
        }
    }
    let updated = swarm
        .get("updated_at")
        .and_then(|t| t.as_str())
        .map(parse_iso_unix)
        .unwrap_or(0);
    u32::from(updated > last_seen)
}

struct DeckRuntime {
    ready: Arc<DeckReady>,
    supervisor: Option<Arc<Mutex<DeckSupervisor>>>,
}

fn deck_runtime() -> &'static DeckRuntime {
    static RUNTIME: OnceLock<DeckRuntime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        let ready = Arc::new(DeckReady::default());
        let supervisor = resolve_mission_deck_dir().map(|dir| {
            Arc::new(Mutex::new(DeckSupervisor::new(dir, ready.clone())))
        });
        DeckRuntime { ready, supervisor }
    })
}

/// Resolve where `web-dashboard` (with `server.js` + `dist/`) lives.
pub fn resolve_mission_deck_dir() -> Option<PathBuf> {
    let candidates: Vec<PathBuf> = {
        let mut list = Vec::new();
        if let Ok(p) = std::env::var("CENTURION_MISSION_DECK_DIR") {
            list.push(PathBuf::from(p));
        }
        // Full Fedora RPM install path.
        list.push(PathBuf::from("/usr/share/centurion/mission-deck"));
        if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
            list.push(home.join(".local/share/centurion/mission-deck"));
        }
        if let Ok(repo) = std::env::var("CENTURION_AI_REPO") {
            list.push(PathBuf::from(&repo).join("brain/web-dashboard"));
            // Legacy checkout layout (pre client-folder reorg).
            list.push(PathBuf::from(repo).join("web-dashboard"));
        }
        list.push(PathBuf::from(
            "/usr/lib/centurion/Centurion-AI-OS/brain/web-dashboard",
        ));
        list.push(PathBuf::from(
            "/usr/lib/centurion/Centurion-AI-OS/web-dashboard",
        ));
        // Compile-time: …/brain/linux/centurion-desktop → brain/web-dashboard
        list.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../web-dashboard"));
        list
    };

    for path in candidates {
        let Ok(canon) = path.canonicalize() else {
            // Still accept non-canonical if server.js is present (env may point
            // at a path that exists but canonicalize fails on some mounts).
            if path.join("server.js").is_file() && path.join("dist").is_dir() {
                return Some(path);
            }
            continue;
        };
        if canon.join("server.js").is_file() && canon.join("dist").is_dir() {
            return Some(canon);
        }
        // Dev: allow server.js without dist (vite --dev), but Get Brain needs dist.
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

fn unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Lock-free readiness signal shared with the UI thread.
///
/// `ensure_running` holds the supervisor mutex for as long as Node takes to
/// warm (up to 8s). GTK reads this instead so showing the tab never waits on
/// that lock — and never issues a health request of its own.
#[derive(Default)]
struct DeckReady {
    /// Unix seconds of the last successful health check (0 = never).
    at_secs: AtomicU64,
    warming: AtomicBool,
}

impl DeckReady {
    fn mark(&self) {
        self.at_secs.store(unix_secs(), Ordering::Relaxed);
    }

    fn recent(&self) -> bool {
        let at = self.at_secs.load(Ordering::Relaxed);
        at != 0 && unix_secs().saturating_sub(at) < READY_CACHE_SECS
    }

    /// Claim the right to run a warm — false when one is already in flight.
    fn begin_warm(&self) -> bool {
        !self.warming.swap(true, Ordering::SeqCst)
    }

    fn end_warm(&self) {
        self.warming.store(false, Ordering::SeqCst);
    }
}

/// Kick `ensure_running` onto a worker thread. `None` means there is nothing
/// to wait for — either the deck directory is missing or a warm is already in
/// flight.
fn spawn_deck_warm(
    supervisor: Option<Arc<Mutex<DeckSupervisor>>>,
    ready: Arc<DeckReady>,
) -> Option<mpsc::Receiver<Result<(), String>>> {
    let supervisor = supervisor?;
    if !ready.begin_warm() {
        return None;
    }
    let (tx, rx) = mpsc::channel::<Result<(), String>>();
    std::thread::spawn(move || {
        let result = supervisor
            .lock()
            .map_err(|e| e.to_string())
            .and_then(|mut s| s.ensure_running());
        ready.end_warm();
        let _ = tx.send(result);
    });
    Some(rx)
}

struct DeckSupervisor {
    child: Option<Child>,
    dir: PathBuf,
    last_ready: Option<Instant>,
    ready: Arc<DeckReady>,
}

impl DeckSupervisor {
    fn new(dir: PathBuf, ready: Arc<DeckReady>) -> Self {
        Self {
            child: None,
            dir,
            last_ready: None,
            ready,
        }
    }

    fn mark_ready(&mut self) {
        self.last_ready = Some(Instant::now());
        self.ready.mark();
    }

    /// True when health succeeded recently — timestamp only, no network I/O.
    fn ready_recently(&self) -> bool {
        matches!(self.last_ready, Some(t) if t.elapsed() < Duration::from_secs(READY_CACHE_SECS))
    }

    /// Blocking spawn + readiness wait — call only from a background thread.
    fn ensure_running(&mut self) -> Result<(), String> {
        if self.ready_recently() {
            return Ok(());
        }
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
                crate::bridge_actions::resolve_centurion_home(),
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
    build_inner(hooks, DECK_URL, DeckAttention::LifeDecisions)
}

/// Conjunction tab — the collaboration instrument, served by the same deck.
/// The page itself links on to the boards and pairing screens at `/collab`.
pub fn build_collab(hooks: HomeHooks) -> (gtk::Box, HomeHandle) {
    build_inner(hooks, COLLAB_URL, DeckAttention::SwarmWaiting)
}

fn opening_label(attention: DeckAttention) -> &'static str {
    match attention {
        DeckAttention::LifeDecisions => "Opening Mission Deck…",
        DeckAttention::SwarmWaiting => "Opening Collaborate…",
    }
}

fn build_inner(
    hooks: HomeHooks,
    initial_url: &'static str,
    attention_kind: DeckAttention,
) -> (gtk::Box, HomeHandle) {
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

    let status = gtk::Label::new(Some(opening_label(attention_kind)));
    status.add_css_class("centurion-mission-deck-status");
    status.set_wrap(true);
    status.set_margin_top(24);
    status.set_margin_bottom(12);
    status.set_margin_start(24);
    status.set_margin_end(24);
    root.append(&status);

    let retry = gtk::Button::with_label("Retry");
    retry.add_css_class("suggested-action");
    retry.set_halign(gtk::Align::Center);
    retry.set_margin_bottom(24);
    root.append(&retry);

    let runtime = deck_runtime();
    let deck_ready = runtime.ready.clone();
    let supervisor: Rc<RefCell<Option<Arc<Mutex<DeckSupervisor>>>>> =
        Rc::new(RefCell::new(runtime.supervisor.clone()));

    // Node warms on first Focus show or after the tab has sat idle for two seconds.
    // WebView still attaches only on first Focus show.
    let node_ready = Rc::new(Cell::new(false));
    let node_error: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
    let warm_started = Rc::new(Cell::new(false));

    let attach_if_needed: Rc<dyn Fn()> = {
        let root = root.clone();
        let hooks = hooks.clone();
        let webview_slot = webview_slot.clone();
        let suspended = suspended.clone();
        let status = status.clone();
        let node_ready = node_ready.clone();
        let node_error = node_error.clone();
        let retry = retry.clone();
        Rc::new(move || {
            if webview_slot.borrow().is_some() {
                status.set_visible(false);
                retry.set_visible(false);
                return;
            }
            if let Some(err) = node_error.borrow().clone() {
                status.set_visible(true);
                status.set_label(&err);
                retry.set_visible(true);
                return;
            }
            if !node_ready.get() {
                status.set_visible(true);
                status.set_label(opening_label(attention_kind));
                retry.set_visible(true);
                return;
            }
            match attach_webview(
                &root,
                hooks.clone(),
                suspended.clone(),
                initial_url,
                deck_role(attention_kind),
            ) {
                Some(wv) => {
                    apply_deck_suspend(&wv, suspended.get());
                    *webview_slot.borrow_mut() = Some(wv);
                    status.set_visible(false);
                    retry.set_visible(false);
                }
                None => {
                    status.set_visible(true);
                    status.set_label(
                        "WebKitGTK is required for Mission Deck. Install webkitgtk6.0 and rebuild.",
                    );
                    retry.set_visible(true);
                }
            }
        })
    };

    let start_warm: Rc<dyn Fn()> = {
        let supervisor = supervisor.clone();
        let deck_ready = deck_ready.clone();
        let node_ready = node_ready.clone();
        let node_error = node_error.clone();
        let warm_started = warm_started.clone();
        let status = status.clone();
        let retry = retry.clone();
        let suspended = suspended.clone();
        let attach_if_needed = attach_if_needed.clone();
        Rc::new(move || {
            warm_started.set(true);
            node_ready.set(false);
            *node_error.borrow_mut() = None;
            status.set_visible(true);
            status.set_label(opening_label(attention_kind));
            retry.set_visible(true);

            let supervisor_bg = supervisor.borrow().clone();
            let Some(rx) = spawn_deck_warm(supervisor_bg, deck_ready.clone()) else {
                if supervisor.borrow().is_none() {
                    let err = "Stillpoint is not available on this install yet. Reinstall the latest \
                               Sovereign AI Brain from Get Brain, or ask your advisor for an update."
                        .to_string();
                    *node_error.borrow_mut() = Some(err.clone());
                    status.set_label(&err);
                    return;
                }
                let deck_ready = deck_ready.clone();
                let node_ready = node_ready.clone();
                let status = status.clone();
                let retry = retry.clone();
                let suspended = suspended.clone();
                let attach_if_needed = attach_if_needed.clone();
                let ticks = Rc::new(Cell::new(0u32));
                glib::timeout_add_local(Duration::from_millis(50), move || {
                    if deck_ready.recent() {
                        node_ready.set(true);
                        retry.set_visible(false);
                        if suspended.get() {
                            status.set_label("Ready — open this tab when you need it.");
                        } else {
                            attach_if_needed();
                        }
                        return glib::ControlFlow::Break;
                    }
                    let n = ticks.get().saturating_add(1);
                    ticks.set(n);
                    if n > 160 {
                        let err = "Mission Deck server did not become ready.".to_string();
                        node_ready.set(false);
                        status.set_label(&err);
                        retry.set_visible(true);
                        return glib::ControlFlow::Break;
                    }
                    glib::ControlFlow::Continue
                });
                return;
            };

            let node_ready = node_ready.clone();
            let node_error = node_error.clone();
            let status = status.clone();
            let retry = retry.clone();
            let suspended = suspended.clone();
            let attach_if_needed = attach_if_needed.clone();
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(result) => {
                    match result {
                        Ok(()) => {
                            node_ready.set(true);
                            *node_error.borrow_mut() = None;
                            retry.set_visible(false);
                            if suspended.get() {
                                status.set_label("Ready — open this tab when you need it.");
                            } else {
                                attach_if_needed();
                            }
                        }
                        Err(err) => {
                            node_ready.set(false);
                            *node_error.borrow_mut() = Some(err.clone());
                            status.set_visible(true);
                            status.set_label(&err);
                            retry.set_visible(true);
                        }
                    }
                    glib::ControlFlow::Break
                }
                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(mpsc::TryRecvError::Disconnected) => {
                    let err = "Mission Deck failed to start.".to_string();
                    node_ready.set(false);
                    *node_error.borrow_mut() = Some(err.clone());
                    status.set_visible(true);
                    status.set_label(&err);
                    retry.set_visible(true);
                    glib::ControlFlow::Break
                }
            });
        })
    };

    {
        let start_warm = start_warm.clone();
        retry.connect_clicked(move |_| start_warm());
    }

    {
        let start_warm = start_warm.clone();
        let warm_started = warm_started.clone();
        glib::timeout_add_local(Duration::from_secs(2), move || {
            if !warm_started.get() {
                start_warm();
            }
            glib::ControlFlow::Break
        });
    }

    let refresh: Rc<dyn Fn()> = {
        let deck_ready = deck_ready.clone();
        let webview_slot = webview_slot.clone();
        let suspended = suspended.clone();
        let attach_if_needed = attach_if_needed.clone();
        let start_warm = start_warm.clone();
        let warm_started = warm_started.clone();
        Rc::new(move || {
            // Soft path: never block the UI thread on Node health waits — the
            // readiness flag is atomic, and the warm runs on a worker. Do not
            // let an early refresh bypass the first-Focus/two-second deferral.
            if warm_started.get() && !deck_ready.recent() {
                start_warm();
            }
            // Never hard-reload while suspended — that resets __centurionDeckVisible
            // to false and leaves the React deck stuck on "Opening your deck…".
            if suspended.get() {
                return;
            }
            attach_if_needed();
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
        let deck_ready = deck_ready.clone();
        let attach_if_needed = attach_if_needed.clone();
        let start_warm = start_warm.clone();
        let attention = attention.clone();
        let hooks = hooks.clone();
        Rc::new(move |visible: bool| {
            let now_suspended = !visible;
            suspended.set(now_suspended);
            if visible {
                if matches!(attention_kind, DeckAttention::SwarmWaiting) {
                    mark_collab_viewed();
                    if attention.get() != 0 {
                        attention.set(0);
                        (hooks.on_attention_changed)(0);
                    }
                }
                if deck_ready.recent() {
                    attach_if_needed();
                } else {
                    start_warm();
                }
            }
            if let Some(wv) = webview_slot.borrow().as_ref() {
                apply_deck_suspend(wv, now_suspended);
            }
        })
    };

    let handle = HomeHandle::new(refresh, attention.clone(), notify_tab_visible);

    let poll_attention = {
        let attention = attention.clone();
        let hooks = hooks.clone();
        let suspended = suspended.clone();
        Rc::new(move || {
            if matches!(attention_kind, DeckAttention::SwarmWaiting) && !suspended.get() {
                mark_collab_viewed();
                if attention.get() != 0 {
                    attention.set(0);
                    (hooks.on_attention_changed)(0);
                }
                return;
            }
            let attention = attention.clone();
            let hooks = hooks.clone();
            let (tx, rx) = std::sync::mpsc::channel::<u32>();
            std::thread::spawn(move || {
                let n = match attention_kind {
                    DeckAttention::LifeDecisions => focus_attention_count(),
                    DeckAttention::SwarmWaiting => swarm_attention_count(),
                };
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
        })
    };

    {
        let poll_attention = poll_attention.clone();
        glib::timeout_add_local(Duration::from_millis(400), move || {
            poll_attention();
            glib::ControlFlow::Break
        });
    }

    {
        let poll_attention = poll_attention.clone();
        glib::timeout_add_seconds_local(12, move || {
            // Keep the tab badge honest even while Chat is showing.
            poll_attention();
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

/// Drop the WebView's on-disk cache when the installed version changes.
///
/// Vite emits content-hashed chunk names and each release **replaces** them, so a
/// persistent WebKit cache left over from the previous version holds a page that
/// points at assets which no longer exist. The component's JS 404s and the whole
/// panel silently fails to mount — no error reaches the screen, the feature is
/// simply absent. That is how a Brain-to-Brain invite panel goes missing straight
/// after an update, and it reads to the customer as "the feature isn't there".
///
/// Clearing it on a version change makes the update self-healing instead of
/// relying on someone knowing to delete a cache directory by hand.
///
/// Runs once per process, before the first WebView is constructed.
fn ensure_fresh_deck_cache() {
    use std::sync::Once;
    static ONCE: Once = Once::new();

    ONCE.call_once(|| {
        let version = env!("CARGO_PKG_VERSION");
        let home = crate::bridge_actions::resolve_centurion_home();
        let stamp = std::path::PathBuf::from(&home).join("deck-cache-version");

        // Same version as last run — the cached assets are still valid.
        if std::fs::read_to_string(&stamp)
            .map(|s| s.trim() == version)
            .unwrap_or(false)
        {
            return;
        }

        let cache_root = std::env::var_os("XDG_CACHE_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME")
                    .map(|h| std::path::PathBuf::from(h).join(".cache"))
            });

        if let Some(root) = cache_root {
            // WebKit derives its default data dir from the program name, which is
            // the executable's basename — derive it the same way rather than
            // hard-coding, so a renamed binary still finds its own cache.
            let exe_name = std::env::current_exe()
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
                .unwrap_or_else(|| "centurion-desktop".to_owned());
            let app_dir = root.join(exe_name);

            for sub in ["WebKitCache", "CacheStorage"] {
                let dir = app_dir.join(sub);
                if dir.exists() {
                    match std::fs::remove_dir_all(&dir) {
                        Ok(()) => eprintln!(
                            "deck cache: cleared {dir:?} (version changed to {version})"
                        ),
                        Err(e) => {
                            eprintln!("deck cache: could not clear {dir:?}: {e}")
                        }
                    }
                }
            }
        }

        let _ = std::fs::write(&stamp, format!("{version}\n"));
    });
}

fn attach_webview(
    root: &gtk::Box,
    hooks: Rc<HomeHooks>,
    suspended: Rc<Cell<bool>>,
    initial_url: &'static str,
    deck_role: &'static str,
) -> Option<webkit6::WebView> {
    use webkit6::prelude::*;

    // Clear a stale deck cache BEFORE the first WebView exists, so a version
    // change can never leave the deck pointing at assets the release deleted.
    ensure_fresh_deck_cache();

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

    let vis = if deck_role == "collab" { "true" } else { "false" };
    let script = webkit6::UserScript::new(
        &format!(
            r#"
        window.__centurionDeckRole = "{deck_role}";
        // Collab WebView is only mounted while that tab is showing.
        // Focus defaults false; GTK re-applies true after load when visible.
        if (typeof window.__centurionDeckVisible === 'undefined') {{
          window.__centurionDeckVisible = {vis};
        }}
        "#
        ),
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
                if kind == "collab" {
                    let id = v
                        .get("id")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let name = v
                        .get("name")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Collaboration")
                        .to_string();
                    let pulse = v
                        .get("pulse")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let objective = v
                        .get("objective")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let board_id = v
                        .get("board_id")
                        .and_then(|t| t.as_str())
                        .unwrap_or(&id)
                        .to_string();
                    let root_id = v
                        .get("root_id")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let workers_summary = v
                        .get("workers_summary")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let blackboard_json = v
                        .get("blackboard_json")
                        .and_then(|t| t.as_str())
                        .unwrap_or("{}")
                        .to_string();
                    let kickoff = v
                        .get("kickoff")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Let's talk about this collaboration.")
                        .to_string();
                    let topic = DiscussTopic::Collab {
                        id: if id.is_empty() { name.clone() } else { id },
                        name,
                        pulse,
                        objective,
                        board_id,
                        root_id,
                        workers_summary,
                        blackboard_json,
                    };
                    (hooks.on_ask_about)(topic, kickoff);
                    return;
                }
                if kind == "plan" {
                    let title = v
                        .get("title")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Plan")
                        .to_string();
                    let id = v
                        .get("id")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let status = v
                        .get("status")
                        .and_then(|t| t.as_str())
                        .unwrap_or("pending_review")
                        .to_string();
                    let goal = v
                        .get("goal")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let summary = v
                        .get("summary")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    let steps = v
                        .get("steps")
                        .and_then(|s| s.as_array())
                        .map(|arr| {
                            arr.iter()
                                .filter_map(|x| x.as_str().map(str::to_string))
                                .collect::<Vec<_>>()
                        })
                        .unwrap_or_default();
                    let risks = v
                        .get("risks")
                        .and_then(|s| s.as_array())
                        .map(|arr| {
                            arr.iter()
                                .filter_map(|x| x.as_str().map(str::to_string))
                                .collect::<Vec<_>>()
                        })
                        .unwrap_or_default();
                    let kickoff = v
                        .get("kickoff")
                        .and_then(|t| t.as_str())
                        .unwrap_or("Please proceed with this plan now.")
                        .to_string();
                    let topic = DiscussTopic::Plan {
                        id: if id.is_empty() { title.clone() } else { id },
                        title,
                        status,
                        goal,
                        summary,
                        steps,
                        risks,
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

    webview.load_uri(initial_url);
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
