//! Brain Home tab — iPhone Mission Portfolio / Pulse parity.
//!
//! Projects `swarm_snapshot` + `plans_list` (+ `mission_get`) into the six
//! pills: Working on now, Plans, Finished, Documents, Needs your choice, Updates.

use adw::prelude::*;
use gtk4 as gtk;
use gtk4::glib;
use libadwaita as adw;
use serde_json::Value;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use crate::chat_page::run_bridge_action;

#[derive(Clone)]
pub struct HomeHooks {
    /// Jump to Chat with a seeded composer prompt about this item.
    pub on_ask_about: Rc<dyn Fn(String, String)>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PulseCategory {
    Live,
    Plans,
    Wins,
    Outputs,
    Decisions,
    Pulse,
}

impl PulseCategory {
    const ALL: [PulseCategory; 6] = [
        Self::Live,
        Self::Plans,
        Self::Wins,
        Self::Outputs,
        Self::Decisions,
        Self::Pulse,
    ];

    fn title(self) -> &'static str {
        match self {
            Self::Live => "Working on now",
            Self::Plans => "Plans",
            Self::Wins => "Finished",
            Self::Outputs => "Documents",
            Self::Decisions => "Needs your choice",
            Self::Pulse => "Updates",
        }
    }
}

#[derive(Clone, Debug, Default)]
struct SubAgent {
    name: String,
    role: String,
    active: bool,
    summary: String,
}

#[derive(Clone, Debug, Default)]
struct LiveActivity {
    id: String,
    summary: String,
    detail: String,
    progress: f64,
    phase: String,
    agents: Vec<SubAgent>,
}

#[derive(Clone, Debug)]
struct FinishedItem {
    id: String,
    summary: String,
    detail: String,
}

#[derive(Clone, Debug)]
struct DocumentItem {
    id: String,
    title: String,
    summary: String,
    body: String,
    is_plan: bool,
    plan_id: Option<String>,
}

#[derive(Clone, Debug)]
struct DecisionItem {
    id: String,
    title: String,
    context: String,
    signal_id: Option<String>,
    plan_id: Option<String>,
}

#[derive(Clone, Debug)]
struct ThoughtItem {
    id: String,
    text: String,
    kind: String,
    related: String,
}

#[derive(Clone, Debug)]
struct PlanItem {
    id: String,
    title: String,
    summary: String,
    status: String,
    goal: String,
    steps: Vec<String>,
}

#[derive(Clone, Debug, Default)]
struct MissionInfo {
    statement: String,
    targets: Vec<String>,
}

#[derive(Clone, Debug, Default)]
struct SwarmOrb {
    id: String,
    name: String,
    pulse: String,
}

#[derive(Clone, Debug, Default)]
struct FleetPeerItem {
    id: String,
    name: String,
    status: String,
    address: String,
    last_seen: f64,
}

#[derive(Clone, Debug, Default)]
struct HomeFeed {
    live: Option<LiveActivity>,
    wins: Vec<FinishedItem>,
    outputs: Vec<DocumentItem>,
    decisions: Vec<DecisionItem>,
    thoughts: Vec<ThoughtItem>,
    plans: Vec<PlanItem>,
    mission: MissionInfo,
    swarms: Vec<SwarmOrb>,
    fleet_peers: Vec<FleetPeerItem>,
    error: Option<String>,
}

fn json_str(value: Option<&Value>) -> String {
    value
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_owned()
}

fn json_f64(value: Option<&Value>) -> f64 {
    value
        .and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|n| n as f64)))
        .unwrap_or(0.0)
}

fn looks_like_plan(text: &str) -> bool {
    let lower = text.to_lowercase();
    lower.contains("plan")
        || lower.contains("propose")
        || lower.contains("before we")
        || lower.contains("approve the")
}

fn pulse_progress(pulse: &str) -> f64 {
    match pulse {
        "complete" => 1.0,
        "active" => 0.6,
        "attention" | "waiting" => 0.5,
        "blocked" => 0.4,
        "forming" => 0.2,
        _ => 0.1,
    }
}

fn pulse_phase(pulse: &str) -> &'static str {
    match pulse {
        "forming" | "idle" => "planning",
        "active" => "executing",
        _ => "verifying",
    }
}

fn map_live(swarm: &Value, activities: &[Value]) -> LiveActivity {
    let id = json_str(swarm.get("id"));
    let display = json_str(swarm.get("display_name"));
    let objective = json_str(swarm.get("objective"));
    let pulse = json_str(swarm.get("pulse"));
    let phase = pulse_phase(&pulse).to_owned();
    let recent: Vec<String> = activities
        .iter()
        .filter(|a| json_str(a.get("swarm_id")) == id)
        .take(3)
        .map(|a| json_str(a.get("summary")))
        .filter(|s| !s.is_empty())
        .collect();
    let detail = if recent.is_empty() {
        display.clone()
    } else {
        recent.join(" · ")
    };
    let summary = if phase == "planning" {
        if objective.is_empty() {
            "Drafting a plan…".to_owned()
        } else {
            format!("Drafting a plan: {objective}")
        }
    } else if objective.is_empty() {
        display
    } else {
        objective.clone()
    };
    let agents = swarm
        .get("participants")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|p| json_str(p.get("kind")) == "centurion")
        .map(|p| SubAgent {
            name: json_str(p.get("name")),
            role: json_str(p.get("role")),
            active: p.get("is_active").and_then(|v| v.as_bool()).unwrap_or(false),
            summary: objective.clone(),
        })
        .collect();
    LiveActivity {
        id,
        summary,
        detail,
        progress: pulse_progress(&pulse),
        phase,
        agents,
    }
}

fn map_feed(snapshot: &Value, plans: &[Value], mission: &Value) -> HomeFeed {
    let swarms = snapshot
        .get("swarms")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let signals = snapshot
        .get("signals")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let outcomes = snapshot
        .get("outcomes")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let activities = snapshot
        .get("activities")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let live_swarm = swarms
        .iter()
        .filter(|s| {
            matches!(
                json_str(s.get("pulse")).as_str(),
                "active" | "blocked" | "forming" | "attention" | "waiting"
            )
        })
        .max_by(|a, b| {
            json_f64(a.get("attention_score"))
                .partial_cmp(&json_f64(b.get("attention_score")))
                .unwrap_or(std::cmp::Ordering::Equal)
        });

    let live = live_swarm.map(|s| map_live(s, &activities));

    let wins: Vec<FinishedItem> = outcomes
        .iter()
        .filter(|o| {
            matches!(
                json_str(o.get("status")).as_str(),
                "complete" | "ready" | "done"
            )
        })
        .map(|o| FinishedItem {
            id: json_str(o.get("id")),
            summary: json_str(o.get("description")),
            detail: format!("Finished by {}", json_str(o.get("owner_name"))),
        })
        .collect();

    let mut outputs: Vec<DocumentItem> = outcomes
        .iter()
        .map(|o| {
            let title = json_str(o.get("description"));
            let is_plan = looks_like_plan(&title);
            let owner = json_str(o.get("owner_name"));
            let status = json_str(o.get("status"));
            let body = if is_plan {
                format!(
                    "# {title}\n\nYour Sovereign proposes this plan.\n\nOwner: {owner}\nStatus: {status}\n"
                )
            } else {
                format!("# {title}\n\nOwner: {owner}\nStatus: {status}\n")
            };
            DocumentItem {
                id: json_str(o.get("id")),
                title: title.chars().take(80).collect(),
                summary: title,
                body,
                is_plan,
                plan_id: None,
            }
        })
        .collect();

    for plan in plans {
        let title = json_str(plan.get("title"));
        let summary = json_str(plan.get("summary"));
        let goal = json_str(plan.get("goal"));
        let steps = plan
            .get("steps")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(|s| s.as_str().map(str::to_owned))
            .collect::<Vec<_>>();
        let body = format!(
            "# {title}\n\n{summary}\n\nGoal: {goal}\n\nSteps:\n{}\n",
            steps
                .iter()
                .map(|s| format!("- {s}"))
                .collect::<Vec<_>>()
                .join("\n")
        );
        outputs.insert(
            0,
            DocumentItem {
                id: format!("plan:{}", json_str(plan.get("id"))),
                title: if title.is_empty() {
                    "Plan".to_owned()
                } else {
                    title.clone()
                },
                summary: if summary.is_empty() {
                    goal.clone()
                } else {
                    summary
                },
                body,
                is_plan: true,
                plan_id: Some(json_str(plan.get("id"))),
            },
        );
    }
    outputs.truncate(24);

    let swarm_name = |swarm_id: &str| -> String {
        swarms
            .iter()
            .find(|s| json_str(s.get("id")) == swarm_id)
            .map(|s| json_str(s.get("display_name")))
            .unwrap_or_default()
    };

    let mut decisions: Vec<DecisionItem> = signals
        .iter()
        .filter(|s| {
            let status = json_str(s.get("status")).to_lowercase();
            status.is_empty() || status == "open" || status == "pending"
        })
        .map(|s| {
            let message = json_str(s.get("message"));
            let sid = json_str(s.get("id"));
            let swarm_id = json_str(s.get("swarm_id"));
            let name = swarm_name(&swarm_id);
            DecisionItem {
                id: format!("signal:{sid}"),
                title: message.chars().take(120).collect(),
                context: if name.is_empty() {
                    "Your Sovereign needs a decision.".to_owned()
                } else {
                    format!("From collaboration “{name}”.")
                },
                signal_id: Some(sid),
                plan_id: None,
            }
        })
        .collect();

    for plan in plans {
        let status = json_str(plan.get("status")).to_lowercase();
        if !matches!(
            status.as_str(),
            "pending_review" | "held" | "adjusted" | "proposed"
        ) {
            continue;
        }
        let plan_id = json_str(plan.get("id"));
        let mut signal_id = json_str(plan.get("signalId"));
        if signal_id.is_empty() {
            signal_id = json_str(plan.get("signal_id"));
        }
        if !signal_id.is_empty()
            && decisions
                .iter()
                .any(|d| d.signal_id.as_deref() == Some(signal_id.as_str()))
        {
            continue;
        }
        let title = json_str(plan.get("title"));
        let summary = json_str(plan.get("summary"));
        decisions.insert(
            0,
            DecisionItem {
                id: format!("plan:{plan_id}"),
                title: if title.is_empty() {
                    "Proposed plan".to_owned()
                } else {
                    title
                },
                context: if summary.is_empty() {
                    "Review this plan before your Sovereign continues.".to_owned()
                } else {
                    summary
                },
                signal_id: if signal_id.is_empty() {
                    None
                } else {
                    Some(signal_id)
                },
                plan_id: Some(plan_id),
            },
        );
    }

    let thoughts: Vec<ThoughtItem> = activities
        .iter()
        .take(30)
        .map(|a| {
            let swarm_id = json_str(a.get("swarm_id"));
            ThoughtItem {
                id: json_str(a.get("id")),
                text: json_str(a.get("summary")),
                kind: json_str(a.get("kind")),
                related: swarm_name(&swarm_id),
            }
        })
        .filter(|t| !t.text.is_empty())
        .collect();

    let plan_items: Vec<PlanItem> = plans
        .iter()
        .map(|p| PlanItem {
            id: json_str(p.get("id")),
            title: json_str(p.get("title")),
            summary: json_str(p.get("summary")),
            status: json_str(p.get("status")),
            goal: json_str(p.get("goal")),
            steps: p
                .get("steps")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default()
                .iter()
                .filter_map(|s| s.as_str().map(str::to_owned))
                .collect(),
        })
        .collect();

    let mut targets = Vec::new();
    if let Some(arr) = mission.get("targets").and_then(|v| v.as_array()) {
        for item in arr {
            if let Some(obj) = item.as_object() {
                let title = json_str(obj.get("title"));
                if !title.is_empty() {
                    targets.push(title);
                }
            } else {
                let text = json_str(Some(item));
                if !text.is_empty() {
                    targets.push(text);
                }
            }
        }
    }

    let orb_swarms: Vec<SwarmOrb> = swarms
        .iter()
        .take(6)
        .map(|s| SwarmOrb {
            id: json_str(s.get("id")),
            name: json_str(s.get("display_name")),
            pulse: json_str(s.get("pulse")),
        })
        .filter(|s| !s.name.is_empty())
        .collect();

    HomeFeed {
        live,
        wins,
        outputs,
        decisions,
        thoughts,
        plans: plan_items,
        mission: MissionInfo {
            statement: json_str(mission.get("statement")),
            targets,
        },
        swarms: orb_swarms,
        fleet_peers: Vec::new(),
        error: None,
    }
}

fn load_home_feed() -> HomeFeed {
    let snapshot = run_bridge_action("swarm_snapshot", serde_json::json!({}))
        .and_then(|r| {
            if r.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                r.get("snapshot").cloned()
            } else {
                None
            }
        })
        .unwrap_or_else(|| serde_json::json!({}));

    let plans = run_bridge_action("plans_list", serde_json::json!({ "status": "all" }))
        .and_then(|r| {
            if r.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                r.get("plans").and_then(|v| v.as_array()).cloned()
            } else {
                None
            }
        })
        .unwrap_or_default();

    let mission = run_bridge_action("mission_get", serde_json::json!({}))
        .and_then(|r| {
            if r.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                r.get("mission").cloned()
            } else {
                None
            }
        })
        .unwrap_or_else(|| serde_json::json!({}));

    let mut feed = map_feed(&snapshot, &plans, &mission);
    if let Some(resp) = run_bridge_action("fleet_status", serde_json::json!({})) {
        if resp.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            feed.fleet_peers = resp
                .get("peers")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
                .map(|p| FleetPeerItem {
                    id: json_str(p.get("id")),
                    name: json_str(p.get("name")),
                    status: json_str(p.get("status")),
                    address: json_str(p.get("address")),
                    last_seen: json_f64(p.get("last_seen")),
                })
                .filter(|p| !p.id.is_empty() || !p.name.is_empty())
                .collect();
        }
    }
    feed
}

fn decide_plan(plan_id: &str, choice: &str) -> Result<(), String> {
    let response = run_bridge_action(
        "plan_decide",
        serde_json::json!({ "plan_id": plan_id, "choice": choice }),
    )
    .ok_or_else(|| "Could not reach the plan service.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Plan decision failed.")
            .to_owned())
    }
}

fn resolve_signal(signal_id: &str, note: &str) -> Result<(), String> {
    let response = run_bridge_action(
        "swarm_resolve_signal",
        serde_json::json!({ "signal_id": signal_id, "choice_note": note }),
    )
    .ok_or_else(|| "Could not reach the collaboration service.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not record that choice.")
            .to_owned())
    }
}

fn save_mission_statement(statement: &str) -> Result<(), String> {
    let response = run_bridge_action(
        "mission_put",
        serde_json::json!({ "mission": { "statement": statement } }),
    )
    .ok_or_else(|| "Could not reach the mission service.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not save Life Mission.")
            .to_owned())
    }
}

fn show_home_error(parent: &impl IsA<gtk::Widget>, message: &str) {
    let dialog = adw::AlertDialog::builder()
        .heading("Could not record that")
        .body(message)
        .close_response("ok")
        .build();
    dialog.add_response("ok", "OK");
    dialog.present(Some(parent));
}

fn run_async_result<F>(
    parent: gtk::Widget,
    refresh: Rc<dyn Fn()>,
    work: F,
) where
    F: FnOnce() -> Result<(), String> + Send + 'static,
{
    let (tx, rx) = mpsc::channel::<Result<(), String>>();
    thread::spawn(move || {
        let _ = tx.send(work());
    });
    glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
        Ok(Ok(())) => {
            refresh();
            glib::ControlFlow::Break
        }
        Ok(Err(msg)) => {
            show_home_error(&parent, &msg);
            refresh();
            glib::ControlFlow::Break
        }
        Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
        Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
    });
}

fn empty_cta_box(
    message: &str,
    primary_label: &str,
    on_primary: impl Fn() + 'static,
    secondary_label: Option<&str>,
    on_secondary: Option<Rc<dyn Fn()>>,
) -> gtk::Box {
    let box_ = gtk::Box::new(gtk::Orientation::Vertical, 10);
    box_.append(&empty_label(message));
    let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let primary = gtk::Button::with_label(primary_label);
    primary.add_css_class("suggested-action");
    primary.connect_clicked(move |_| on_primary());
    actions.append(&primary);
    if let (Some(label), Some(cb)) = (secondary_label, on_secondary) {
        let secondary = gtk::Button::with_label(label);
        secondary.add_css_class("flat");
        secondary.connect_clicked(move |_| cb());
        actions.append(&secondary);
    }
    box_.append(&actions);
    box_
}

fn show_mission_edit_dialog(
    parent: &impl IsA<gtk::Widget>,
    current: &str,
    refresh: Rc<dyn Fn()>,
) {
    let entry = gtk::TextView::builder()
        .wrap_mode(gtk::WrapMode::WordChar)
        .hexpand(true)
        .vexpand(true)
        .build();
    entry.buffer().set_text(current);
    let scrolled = gtk::ScrolledWindow::builder()
        .child(&entry)
        .min_content_height(120)
        .hexpand(true)
        .build();
    let dialog = adw::AlertDialog::builder()
        .heading("Life Mission")
        .body("What are you building toward? Your Sovereign uses this to stay aligned.")
        .extra_child(&scrolled)
        .close_response("cancel")
        .default_response("save")
        .build();
    dialog.add_response("cancel", "Cancel");
    dialog.add_response("save", "Save");
    dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
    let parent_w = parent.clone().upcast::<gtk::Widget>();
    dialog.connect_response(None, move |_d, response| {
        if response != "save" {
            return;
        }
        let (start, end) = entry.buffer().bounds();
        let text = entry.buffer().text(&start, &end, false).trim().to_owned();
        let refresh = refresh.clone();
        let parent_w = parent_w.clone();
        run_async_result(parent_w, refresh, move || save_mission_statement(&text));
    });
    dialog.present(Some(parent));
}

fn clear_box(container: &gtk::Box) {
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }
}

fn empty_label(text: &str) -> gtk::Label {
    gtk::Label::builder()
        .label(text)
        .wrap(true)
        .xalign(0.0)
        .css_classes(["dim-label"])
        .margin_top(12)
        .build()
}

fn section_heading(text: &str) -> gtk::Label {
    gtk::Label::builder()
        .label(text)
        .css_classes(["title-4"])
        .xalign(0.0)
        .margin_top(8)
        .margin_bottom(4)
        .build()
}

fn card_box() -> gtk::Box {
    let card = gtk::Box::new(gtk::Orientation::Vertical, 8);
    card.add_css_class("centurion-home-card");
    card.set_margin_bottom(10);
    card
}

fn show_how_dialog(parent: &impl IsA<gtk::Widget>, live: &LiveActivity) {
    let body = gtk::Box::new(gtk::Orientation::Vertical, 10);
    body.set_margin_top(8);
    body.set_margin_bottom(8);
    body.append(
        &gtk::Label::builder()
            .label(&format!("Phase: {}", live.phase))
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );
    body.append(
        &gtk::Label::builder()
            .label(&live.detail)
            .wrap(true)
            .xalign(0.0)
            .build(),
    );
    if live.agents.is_empty() {
        body.append(&empty_label("No sub-agents reported for this loop yet."));
    } else {
        for agent in &live.agents {
            let row = gtk::Box::new(gtk::Orientation::Vertical, 4);
            row.add_css_class("centurion-home-agent");
            row.append(
                &gtk::Label::builder()
                    .label(&format!(
                        "{} · {}{}",
                        agent.name,
                        agent.role,
                        if agent.active { " · active" } else { " · waiting" }
                    ))
                    .xalign(0.0)
                    .build(),
            );
            if !agent.summary.is_empty() {
                row.append(
                    &gtk::Label::builder()
                        .label(&agent.summary)
                        .wrap(true)
                        .xalign(0.0)
                        .css_classes(["dim-label"])
                        .build(),
                );
            }
            let bar = gtk::ProgressBar::new();
            bar.set_fraction(if agent.active { 0.65 } else { 0.15 });
            row.append(&bar);
            body.append(&row);
        }
    }
    let dialog = adw::AlertDialog::builder()
        .heading("How it's working")
        .body(&live.summary)
        .extra_child(&body)
        .close_response("close")
        .default_response("close")
        .build();
    dialog.add_response("close", "Close");
    dialog.present(Some(parent));
}

fn show_document_dialog(parent: &impl IsA<gtk::Widget>, doc: &DocumentItem) {
    let view = gtk::TextView::builder()
        .editable(false)
        .wrap_mode(gtk::WrapMode::WordChar)
        .hexpand(true)
        .vexpand(true)
        .build();
    view.buffer().set_text(&doc.body);
    let scroll = gtk::ScrolledWindow::builder()
        .child(&view)
        .min_content_height(220)
        .min_content_width(420)
        .build();
    let dialog = adw::AlertDialog::builder()
        .heading(&doc.title)
        .extra_child(&scroll)
        .close_response("close")
        .default_response("close")
        .build();
    dialog.add_response("close", "Close");
    dialog.present(Some(parent));
}

fn show_plan_dialog(
    parent: &impl IsA<gtk::Widget>,
    plan: &PlanItem,
    refresh: Rc<dyn Fn()>,
    on_ask: Rc<dyn Fn(String, String)>,
) {
    let body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    if !plan.summary.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label(&plan.summary)
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
    }
    if !plan.goal.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label(&format!("Goal: {}", plan.goal))
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
    }
    for step in &plan.steps {
        body.append(
            &gtk::Label::builder()
                .label(&format!("• {step}"))
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
    }
    let dialog = adw::AlertDialog::builder()
        .heading(&plan.title)
        .body(&format!("Status: {}", plan.status))
        .extra_child(&body)
        .close_response("close")
        .default_response("close")
        .build();
    dialog.add_response("close", "Close");
    let pending = matches!(
        plan.status.to_lowercase().as_str(),
        "pending_review" | "held" | "adjusted" | "proposed"
    );
    if pending {
        dialog.add_response("approve", "Proceed");
        dialog.add_response("hold", "Hold");
        dialog.add_response("adjust", "Adjust");
        dialog.add_response("reject", "Reject");
        dialog.set_response_appearance("approve", adw::ResponseAppearance::Suggested);
        dialog.set_response_appearance("reject", adw::ResponseAppearance::Destructive);
    }
    let plan_id = plan.id.clone();
    let title = plan.title.clone();
    let summary = plan.summary.clone();
    let parent_w = parent.clone().upcast::<gtk::Widget>();
    dialog.connect_response(None, move |_d, response| match response {
        "approve" | "hold" | "reject" => {
            let choice = match response {
                "approve" => "approve",
                "hold" => "hold",
                _ => "reject",
            };
            let refresh = refresh.clone();
            let plan_id = plan_id.clone();
            let parent_w = parent_w.clone();
            run_async_result(parent_w, refresh, move || decide_plan(&plan_id, choice));
        }
        "adjust" => {
            on_ask(
                title.clone(),
                format!(
                    "I'd like to adjust this plan.\n\n{}\n\nWhat should change?",
                    summary
                ),
            );
        }
        _ => {}
    });
    dialog.present(Some(parent));
}

/// Build the Home (Pulse) tab.
pub fn build(hooks: HomeHooks) -> gtk::Box {
    let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
    container.set_vexpand(true);
    container.set_hexpand(true);
    container.add_css_class("centurion-home");

    let header = gtk::Box::new(gtk::Orientation::Vertical, 4);
    header.set_margin_top(16);
    header.set_margin_start(20);
    header.set_margin_end(20);
    header.set_margin_bottom(8);
    header.append(
        &gtk::Label::builder()
            .label("Home")
            .css_classes(["title-1"])
            .xalign(0.0)
            .build(),
    );
    header.append(
        &gtk::Label::builder()
            .label("What your Sovereign is doing, has finished, and needs from you.")
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );
    container.append(&header);

    let pill_bar = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    pill_bar.add_css_class("centurion-home-pills");
    pill_bar.set_margin_start(16);
    pill_bar.set_margin_end(16);
    pill_bar.set_margin_bottom(8);
    let pill_scroll = gtk::ScrolledWindow::builder()
        .child(&pill_bar)
        .hscrollbar_policy(gtk::PolicyType::Automatic)
        .vscrollbar_policy(gtk::PolicyType::Never)
        .hexpand(true)
        .build();
    container.append(&pill_scroll);

    let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
    body.set_hexpand(true);

    let chrome = gtk::Box::new(gtk::Orientation::Vertical, 10);
    chrome.set_margin_start(20);
    chrome.set_margin_end(20);
    chrome.set_margin_top(4);
    chrome.set_margin_bottom(8);

    let constellation = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    constellation.add_css_class("centurion-home-constellation");
    chrome.append(
        &gtk::Label::builder()
            .label("Your collaborations")
            .css_classes(["title-4"])
            .xalign(0.0)
            .build(),
    );
    chrome.append(&constellation);

    let fleet_section = gtk::Box::new(gtk::Orientation::Vertical, 6);
    fleet_section.append(
        &gtk::Label::builder()
            .label("Fleet Presence")
            .css_classes(["title-4"])
            .xalign(0.0)
            .build(),
    );
    let fleet_body = gtk::Box::new(gtk::Orientation::Vertical, 6);
    fleet_body.add_css_class("centurion-home-fleet");
    fleet_section.append(&fleet_body);
    chrome.append(&fleet_section);

    let mission_banner = gtk::Box::new(gtk::Orientation::Vertical, 6);
    mission_banner.add_css_class("centurion-home-mission");
    let mission_header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    mission_header.append(
        &gtk::Label::builder()
            .label("WHAT YOU'RE BUILDING TOWARD")
            .css_classes(["caption-heading"])
            .xalign(0.0)
            .hexpand(true)
            .build(),
    );
    let mission_edit = gtk::Button::with_label("Edit");
    mission_edit.add_css_class("flat");
    mission_header.append(&mission_edit);
    mission_banner.append(&mission_header);
    let mission_statement = gtk::Label::builder()
        .label("Set a Life Mission to guide your Sovereign.")
        .wrap(true)
        .xalign(0.0)
        .build();
    mission_banner.append(&mission_statement);
    chrome.append(&mission_banner);

    let commitments = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    commitments.add_css_class("centurion-home-commitments");
    chrome.append(&commitments);

    let error_label = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .css_classes(["error"])
        .visible(false)
        .build();
    chrome.append(&error_label);

    let category_body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    category_body.set_margin_start(20);
    category_body.set_margin_end(20);
    category_body.set_margin_bottom(28);

    body.append(&chrome);
    body.append(&category_body);

    let scroll = gtk::ScrolledWindow::builder()
        .child(&body)
        .vexpand(true)
        .hexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .build();
    container.append(&scroll);

    let feed: Rc<RefCell<HomeFeed>> = Rc::new(RefCell::new(HomeFeed::default()));
    let selected = Rc::new(Cell::new(PulseCategory::Live));
    let pill_buttons: Rc<RefCell<Vec<(PulseCategory, gtk::ToggleButton)>>> =
        Rc::new(RefCell::new(Vec::new()));
    let render_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));

    let paint: Rc<dyn Fn()> = Rc::new({
        let feed = feed.clone();
        let selected = selected.clone();
        let constellation = constellation.clone();
        let fleet_body = fleet_body.clone();
        let mission_statement = mission_statement.clone();
        let commitments = commitments.clone();
        let error_label = error_label.clone();
        let category_body = category_body.clone();
        let hooks = hooks.clone();
        let container = container.clone();
        let render_slot = render_slot.clone();
        move || {
            let data = feed.borrow().clone();
            clear_box(&constellation);
            if data.swarms.is_empty() {
                constellation.append(&empty_label(
                    "No active collaborations yet. When your Sovereign works with others, they’ll appear here.",
                ));
            } else {
                for orb in &data.swarms {
                    let chip = gtk::Label::builder()
                        .label(&format!("{} · {}", orb.name, orb.pulse))
                        .css_classes(["centurion-home-orb"])
                        .build();
                    constellation.append(&chip);
                }
            }

            clear_box(&fleet_body);
            if data.fleet_peers.is_empty() {
                fleet_body.append(&empty_label(
                    "No fleet peers yet. Add an address under Settings → Fleet peer to talk across machines.",
                ));
            } else {
                for peer in &data.fleet_peers {
                    let card = card_box();
                    let status = if peer.status.is_empty() {
                        "unknown"
                    } else {
                        peer.status.as_str()
                    };
                    let addr = if peer.address.is_empty() {
                        "no address".to_owned()
                    } else {
                        peer.address.clone()
                    };
                    card.append(
                        &gtk::Label::builder()
                            .label(&format!("{} · {status}", peer.name))
                            .xalign(0.0)
                            .build(),
                    );
                    card.append(
                        &gtk::Label::builder()
                            .label(&addr)
                            .xalign(0.0)
                            .css_classes(["dim-label", "caption"])
                            .build(),
                    );
                    let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                    let ping = gtk::Button::with_label("Ping");
                    ping.add_css_class("flat");
                    let peer_id = if peer.id.is_empty() {
                        peer.name.clone()
                    } else {
                        peer.id.clone()
                    };
                    let refresh_all = {
                        let render_slot = render_slot.clone();
                        Rc::new(move || {
                            if let Some(f) = render_slot.borrow().as_ref() {
                                f();
                            }
                        }) as Rc<dyn Fn()>
                    };
                    let parent_w = container.clone().upcast::<gtk::Widget>();
                    ping.connect_clicked(move |_| {
                        let peer_id = peer_id.clone();
                        let refresh_all = refresh_all.clone();
                        let parent_w = parent_w.clone();
                        run_async_result(parent_w, refresh_all, move || {
                            let response = run_bridge_action(
                                "fleet_ping",
                                serde_json::json!({ "peer_id": peer_id }),
                            )
                            .ok_or_else(|| "Could not reach fleet service.".to_owned())?;
                            if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                                Ok(())
                            } else {
                                Err(response
                                    .get("message")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("Ping failed.")
                                    .to_owned())
                            }
                        });
                    });
                    let ask = gtk::Button::with_label("Ask about this");
                    ask.add_css_class("suggested-action");
                    let on_ask = hooks.on_ask_about.clone();
                    let pname = peer.name.clone();
                    let pstatus = status.to_owned();
                    ask.connect_clicked(move |_| {
                        on_ask(
                            pname.clone(),
                            format!(
                                "Fleet peer {pname} is currently {pstatus}. \
What should we do with them, or what messages are waiting?"
                            ),
                        );
                    });
                    actions.append(&ping);
                    actions.append(&ask);
                    card.append(&actions);
                    fleet_body.append(&card);
                }
            }

            if data.mission.statement.is_empty() {
                mission_statement.set_label("Set a Life Mission to guide your Sovereign.");
            } else {
                mission_statement.set_label(&data.mission.statement);
            }
            clear_box(&commitments);
            for target in &data.mission.targets {
                let chip = gtk::Button::with_label(target);
                chip.add_css_class("flat");
                chip.add_css_class("centurion-home-commitment");
                let title = target.clone();
                let on_ask = hooks.on_ask_about.clone();
                chip.connect_clicked(move |_| {
                    on_ask(
                        title.clone(),
                        format!("Let's talk about my commitment: {title}"),
                    );
                });
                commitments.append(&chip);
            }

            if let Some(err) = &data.error {
                error_label.set_label(err);
                error_label.set_visible(true);
            } else {
                error_label.set_visible(false);
            }

            clear_box(&category_body);
            let cat = selected.get();
            category_body.append(&section_heading(cat.title()));

            let refresh_all = {
                let render_slot = render_slot.clone();
                Rc::new(move || {
                    if let Some(f) = render_slot.borrow().as_ref() {
                        f();
                    }
                }) as Rc<dyn Fn()>
            };

            match cat {
                PulseCategory::Live => {
                    if let Some(live) = &data.live {
                        let card = card_box();
                        let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                        title_row.append(
                            &gtk::Label::builder()
                                .label("●")
                                .css_classes(["centurion-home-pulse-dot"])
                                .build(),
                        );
                        title_row.append(
                            &gtk::Label::builder()
                                .label("Working on now")
                                .css_classes(["title-4"])
                                .xalign(0.0)
                                .hexpand(true)
                                .build(),
                        );
                        title_row.append(
                            &gtk::Label::builder()
                                .label(&format!("{}%", (live.progress * 100.0).round() as i32))
                                .css_classes(["dim-label"])
                                .build(),
                        );
                        card.append(&title_row);
                        card.append(
                            &gtk::Label::builder()
                                .label(&live.summary)
                                .wrap(true)
                                .xalign(0.0)
                                .build(),
                        );
                        card.append(
                            &gtk::Label::builder()
                                .label(&live.detail)
                                .wrap(true)
                                .xalign(0.0)
                                .css_classes(["dim-label"])
                                .build(),
                        );
                        let bar = gtk::ProgressBar::new();
                        bar.set_fraction(live.progress.clamp(0.0, 1.0));
                        card.append(&bar);
                        let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                        let how = gtk::Button::with_label("Show how it's working");
                        how.add_css_class("flat");
                        let live_clone = live.clone();
                        let parent = container.clone();
                        how.connect_clicked(move |_| show_how_dialog(&parent, &live_clone));
                        let ask = gtk::Button::with_label("Ask about this");
                        ask.add_css_class("suggested-action");
                        let on_ask = hooks.on_ask_about.clone();
                        let summary = live.summary.clone();
                        let detail = live.detail.clone();
                        ask.connect_clicked(move |_| {
                            on_ask(
                                summary.clone(),
                                format!(
                                    "You're working on: {summary}\n\nRecent: {detail}\n\nWhat's the status and what do you need from me?"
                                ),
                            );
                        });
                        actions.append(&how);
                        actions.append(&ask);
                        card.append(&actions);
                        category_body.append(&card);
                    } else {
                        let on_ask = hooks.on_ask_about.clone();
                        let on_ask2 = hooks.on_ask_about.clone();
                        let mission_text = data.mission.statement.clone();
                        category_body.append(&empty_cta_box(
                            "Nothing in motion right now. Start with a plan or talk through your mission.",
                            "Propose a plan",
                            move || {
                                on_ask(
                                    "Propose a plan".to_owned(),
                                    "Propose a plan for what we should work on next. \
Outline the goal, steps, and what you need from me before acting."
                                        .to_owned(),
                                );
                            },
                            Some("Discuss mission"),
                            Some(Rc::new(move || {
                                let prompt = if mission_text.is_empty() {
                                    "Help me set a Life Mission — what I'm building toward — \
so you can partner with me on it.".to_owned()
                                } else {
                                    format!(
                                        "Let's discuss my Life Mission:\n\n{mission_text}\n\n\
What should we focus on next?"
                                    )
                                };
                                on_ask2("Life Mission".to_owned(), prompt);
                            }) as Rc<dyn Fn()>),
                        ));
                    }
                }
                PulseCategory::Plans => {
                    let pending: Vec<_> = data
                        .plans
                        .iter()
                        .filter(|p| {
                            matches!(
                                p.status.to_lowercase().as_str(),
                                "pending_review" | "held" | "adjusted" | "proposed"
                            )
                        })
                        .cloned()
                        .collect();
                    let active: Vec<_> = data
                        .plans
                        .iter()
                        .filter(|p| p.status.to_lowercase() == "proceeded")
                        .cloned()
                        .collect();
                    let done: Vec<_> = data
                        .plans
                        .iter()
                        .filter(|p| p.status.to_lowercase() == "completed")
                        .cloned()
                        .collect();
                    if pending.is_empty() && active.is_empty() && done.is_empty() {
                        let on_ask = hooks.on_ask_about.clone();
                        category_body.append(&empty_cta_box(
                            "No plans yet. Ask your Sovereign to propose one, or discuss the mission first.",
                            "Propose a plan",
                            move || {
                                on_ask(
                                    "Propose a plan".to_owned(),
                                    "Propose a plan for what we should work on next. \
Outline the goal, steps, and what you need from me before acting."
                                        .to_owned(),
                                );
                            },
                            None,
                            None,
                        ));
                    } else {
                        for (label, items) in [
                            ("Needs review", pending),
                            ("In progress", active),
                            ("Done", done),
                        ] {
                            if items.is_empty() {
                                continue;
                            }
                            category_body.append(&section_heading(label));
                            for plan in items {
                                let card = card_box();
                                card.append(
                                    &gtk::Label::builder()
                                        .label(&plan.title)
                                        .wrap(true)
                                        .xalign(0.0)
                                        .css_classes(["heading"])
                                        .build(),
                                );
                                if !plan.summary.is_empty() {
                                    card.append(
                                        &gtk::Label::builder()
                                            .label(&plan.summary)
                                            .wrap(true)
                                            .xalign(0.0)
                                            .css_classes(["dim-label"])
                                            .build(),
                                    );
                                }
                                let open = gtk::Button::with_label("Open");
                                open.add_css_class("flat");
                                let parent = container.clone();
                                let plan_c = plan.clone();
                                let refresh = refresh_all.clone();
                                let on_ask = hooks.on_ask_about.clone();
                                open.connect_clicked(move |_| {
                                    show_plan_dialog(
                                        &parent,
                                        &plan_c,
                                        refresh.clone(),
                                        on_ask.clone(),
                                    );
                                });
                                card.append(&open);
                                category_body.append(&card);
                            }
                        }
                    }
                }
                PulseCategory::Wins => {
                    if data.wins.is_empty() {
                        category_body.append(&empty_label("Finished work will land here."));
                    } else {
                        for win in &data.wins {
                            let card = card_box();
                            card.append(
                                &gtk::Label::builder()
                                    .label(&win.summary)
                                    .wrap(true)
                                    .xalign(0.0)
                                    .build(),
                            );
                            card.append(
                                &gtk::Label::builder()
                                    .label(&win.detail)
                                    .wrap(true)
                                    .xalign(0.0)
                                    .css_classes(["dim-label"])
                                    .build(),
                            );
                            let ask = gtk::Button::with_label("Ask about this");
                            ask.add_css_class("flat");
                            let on_ask = hooks.on_ask_about.clone();
                            let summary = win.summary.clone();
                            ask.connect_clicked(move |_| {
                                on_ask(
                                    summary.clone(),
                                    format!("Tell me more about this finished work:\n\n{summary}"),
                                );
                            });
                            card.append(&ask);
                            category_body.append(&card);
                        }
                    }
                }
                PulseCategory::Outputs => {
                    if data.outputs.is_empty() {
                        category_body.append(&empty_label(
                            "Documents and plan write-ups will appear here.",
                        ));
                    } else {
                        for doc in &data.outputs {
                            let card = card_box();
                            let kind = if doc.is_plan { "Plan" } else { "Document" };
                            card.append(
                                &gtk::Label::builder()
                                    .label(&format!("{kind} · {}", doc.title))
                                    .wrap(true)
                                    .xalign(0.0)
                                    .build(),
                            );
                            if !doc.summary.is_empty() {
                                card.append(
                                    &gtk::Label::builder()
                                        .label(&doc.summary)
                                        .wrap(true)
                                        .xalign(0.0)
                                        .css_classes(["dim-label"])
                                        .build(),
                                );
                            }
                            let open = gtk::Button::with_label("Open");
                            open.add_css_class("flat");
                            let parent = container.clone();
                            let doc_c = doc.clone();
                            open.connect_clicked(move |_| show_document_dialog(&parent, &doc_c));
                            card.append(&open);
                            category_body.append(&card);
                        }
                    }
                }
                PulseCategory::Decisions => {
                    if data.decisions.is_empty() {
                        category_body.append(&empty_label(
                            "When your Sovereign needs a choice, it shows up here.",
                        ));
                    } else {
                        for decision in &data.decisions {
                            let card = card_box();
                            card.append(
                                &gtk::Label::builder()
                                    .label(&decision.title)
                                    .wrap(true)
                                    .xalign(0.0)
                                    .build(),
                            );
                            card.append(
                                &gtk::Label::builder()
                                    .label(&decision.context)
                                    .wrap(true)
                                    .xalign(0.0)
                                    .css_classes(["dim-label"])
                                    .build(),
                            );
                            let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                            let proceed = gtk::Button::with_label("Proceed");
                            proceed.add_css_class("suggested-action");
                            let adjust = gtk::Button::with_label("Adjust");
                            adjust.add_css_class("flat");
                            let hold = gtk::Button::with_label("Hold");
                            hold.add_css_class("flat");
                            let reject = gtk::Button::with_label("Reject");
                            reject.add_css_class("flat");

                            let plan_id = decision.plan_id.clone();
                            let signal_id = decision.signal_id.clone();
                            let refresh_p = refresh_all.clone();
                            let parent_w = container.clone().upcast::<gtk::Widget>();
                            proceed.connect_clicked(move |_| {
                                let plan_id = plan_id.clone();
                                let signal_id = signal_id.clone();
                                let refresh_p = refresh_p.clone();
                                let parent_w = parent_w.clone();
                                run_async_result(parent_w, refresh_p, move || {
                                    if let Some(pid) = plan_id.as_ref() {
                                        decide_plan(pid, "approve")?;
                                    }
                                    if let Some(sid) = signal_id.as_ref() {
                                        resolve_signal(sid, "Proceed")?;
                                    }
                                    Ok(())
                                });
                            });

                            let on_ask = hooks.on_ask_about.clone();
                            let title = decision.title.clone();
                            let context = decision.context.clone();
                            adjust.connect_clicked(move |_| {
                                on_ask(
                                    title.clone(),
                                    format!(
                                        "I'd like to adjust this decision.\n\n{title}\n\n{context}\n\nWhat should change?"
                                    ),
                                );
                            });

                            let plan_id = decision.plan_id.clone();
                            let refresh_h = refresh_all.clone();
                            let parent_h = container.clone().upcast::<gtk::Widget>();
                            hold.connect_clicked(move |_| {
                                if let Some(pid) = plan_id.clone() {
                                    let refresh_h = refresh_h.clone();
                                    let parent_h = parent_h.clone();
                                    run_async_result(parent_h, refresh_h, move || {
                                        decide_plan(&pid, "hold")
                                    });
                                }
                            });

                            let plan_id = decision.plan_id.clone();
                            let signal_id = decision.signal_id.clone();
                            let refresh_r = refresh_all.clone();
                            let parent_r = container.clone().upcast::<gtk::Widget>();
                            reject.connect_clicked(move |_| {
                                let plan_id = plan_id.clone();
                                let signal_id = signal_id.clone();
                                let refresh_r = refresh_r.clone();
                                let parent_r = parent_r.clone();
                                run_async_result(parent_r, refresh_r, move || {
                                    if let Some(pid) = plan_id.as_ref() {
                                        decide_plan(pid, "reject")?;
                                    }
                                    if let Some(sid) = signal_id.as_ref() {
                                        resolve_signal(sid, "Reject")?;
                                    }
                                    Ok(())
                                });
                            });

                            actions.append(&proceed);
                            actions.append(&adjust);
                            actions.append(&hold);
                            actions.append(&reject);
                            card.append(&actions);
                            category_body.append(&card);
                        }
                    }
                }
                PulseCategory::Pulse => {
                    if data.thoughts.is_empty() {
                        category_body.append(&empty_label(
                            "Live updates from your Sovereign will stream here.",
                        ));
                    } else {
                        for thought in &data.thoughts {
                            let card = card_box();
                            let meta = if thought.related.is_empty() {
                                thought.kind.clone()
                            } else {
                                format!("{} · {}", thought.kind, thought.related)
                            };
                            card.append(
                                &gtk::Label::builder()
                                    .label(&meta)
                                    .xalign(0.0)
                                    .css_classes(["dim-label", "caption"])
                                    .build(),
                            );
                            card.append(
                                &gtk::Label::builder()
                                    .label(&thought.text)
                                    .wrap(true)
                                    .xalign(0.0)
                                    .build(),
                            );
                            let ask = gtk::Button::with_label("Discuss");
                            ask.add_css_class("flat");
                            let on_ask = hooks.on_ask_about.clone();
                            let text = thought.text.clone();
                            ask.connect_clicked(move |_| {
                                on_ask(text.clone(), format!("About this update:\n\n{text}"));
                            });
                            card.append(&ask);
                            category_body.append(&card);
                        }
                    }
                }
            }
        }
    });

    let refresh_feed: Rc<dyn Fn()> = Rc::new({
        let feed = feed.clone();
        let paint = paint.clone();
        move || {
            let (tx, rx) = mpsc::channel::<HomeFeed>();
            thread::spawn(move || {
                let _ = tx.send(load_home_feed());
            });
            let feed = feed.clone();
            let paint = paint.clone();
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(next) => {
                    *feed.borrow_mut() = next;
                    paint();
                    glib::ControlFlow::Break
                }
                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            });
        }
    });

    *render_slot.borrow_mut() = Some(Rc::new({
        let refresh_feed = refresh_feed.clone();
        let paint = paint.clone();
        move || {
            paint();
            refresh_feed();
        }
    }) as Rc<dyn Fn()>);

    for cat in PulseCategory::ALL {
        let btn = gtk::ToggleButton::with_label(cat.title());
        btn.add_css_class("centurion-home-pill");
        btn.set_active(cat == PulseCategory::Live);
        let selected = selected.clone();
        let pill_buttons_for_toggle = pill_buttons.clone();
        let paint = paint.clone();
        btn.connect_toggled(move |b| {
            if !b.is_active() {
                return;
            }
            selected.set(cat);
            for (other_cat, other) in pill_buttons_for_toggle.borrow().iter() {
                if *other_cat != cat {
                    other.set_active(false);
                }
            }
            paint();
        });
        pill_bar.append(&btn);
        pill_buttons.borrow_mut().push((cat, btn));
    }

    refresh_feed();
    glib::timeout_add_seconds_local(8, {
        let refresh_feed = refresh_feed.clone();
        move || {
            refresh_feed();
            glib::ControlFlow::Continue
        }
    });

    {
        let container = container.clone();
        let feed = feed.clone();
        let render_slot = render_slot.clone();
        mission_edit.connect_clicked(move |_| {
            let current = feed.borrow().mission.statement.clone();
            let refresh = {
                let render_slot = render_slot.clone();
                Rc::new(move || {
                    if let Some(f) = render_slot.borrow().as_ref() {
                        f();
                    }
                }) as Rc<dyn Fn()>
            };
            show_mission_edit_dialog(&container, &current, refresh);
        });
    }

    container
}
