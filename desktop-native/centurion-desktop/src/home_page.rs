//! Brain Missions tab — Mission Stack + iPhone Pulse parity.
//!
//! Mission Stack (Primary / Supporting / Dreams) sits above the pulse feed
//! from `swarm_snapshot` + `plans_list` (+ legacy `mission_get`).

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

use crate::chat_page::{run_bridge_action, DiscussTopic};

#[derive(Clone)]
pub struct HomeHooks {
    /// Jump to Chat with a structured topic so outbound turns are framed.
    pub on_ask_about: Rc<dyn Fn(DiscussTopic, String)>,
    /// Fires whenever Home recomputes pill “new” totals (for tab badges).
    pub on_attention_changed: Rc<dyn Fn(u32)>,
}

#[derive(Clone)]
pub struct HomeHandle {
    refresh: Rc<dyn Fn()>,
    attention: Rc<Cell<u32>>,
    /// Missions tab visibility — pause WebView / polls when Chat (or Settings) is active.
    notify_tab_visible: Rc<dyn Fn(bool)>,
}

impl HomeHandle {
    pub(crate) fn new(
        refresh: Rc<dyn Fn()>,
        attention: Rc<Cell<u32>>,
        notify_tab_visible: Rc<dyn Fn(bool)>,
    ) -> Self {
        Self {
            refresh,
            attention,
            notify_tab_visible,
        }
    }

    pub fn refresh(&self) {
        (self.refresh)();
    }

    /// Tell Missions whether its stack page is the visible tab.
    pub fn notify_tab_visible(&self, visible: bool) {
        (self.notify_tab_visible)(visible);
    }

    /// Sum of pill new-counts (Live = presence 0/1). Used for the Missions tab badge.
    pub fn attention_count(&self) -> u32 {
        self.attention.get()
    }
}

/// Icon-first discuss affordance (iPhone `bubble.left.and.bubble.right` parity).
fn discuss_icon_button(tooltip: &str) -> gtk::Button {
    let btn = gtk::Button::from_icon_name("mail-message-new-symbolic");
    btn.add_css_class("flat");
    btn.add_css_class("centurion-home-discuss");
    btn.set_tooltip_text(Some(tooltip));
    btn.set_valign(gtk::Align::Center);
    btn
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
    risks: Vec<String>,
    comments: Vec<String>,
    related_mission: String,
}

#[derive(Clone, Debug)]
struct PlanTemplateItem {
    id: String,
    title: String,
    summary: String,
}

#[derive(Clone, Debug, Default)]
struct CommitmentItem {
    id: String,
    title: String,
    description: String,
}

#[derive(Clone, Debug, Default)]
struct MissionInfo {
    statement: String,
    targets: Vec<CommitmentItem>,
}

#[derive(Clone, Debug, Default)]
struct SwarmOrb {
    id: String,
    name: String,
    pulse: String,
    objective: String,
    detail: String,
    signals: Vec<(String, String)>, // id, message
    outcomes: Vec<String>,
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
struct OpsItem {
    id: String,
    title: String,
    detail: String,
    kind: String,
}

#[derive(Clone, Debug, Default)]
struct PluginCard {
    id: String,
    title: String,
    subtitle: String,
    ask_prompt: String,
}

#[derive(Clone, Debug, Default)]
struct HomeFeed {
    live: Option<LiveActivity>,
    wins: Vec<FinishedItem>,
    outputs: Vec<DocumentItem>,
    decisions: Vec<DecisionItem>,
    thoughts: Vec<ThoughtItem>,
    plans: Vec<PlanItem>,
    templates: Vec<PlanTemplateItem>,
    mission: MissionInfo,
    swarms: Vec<SwarmOrb>,
    fleet_peers: Vec<FleetPeerItem>,
    ops: Vec<OpsItem>,
    plugins: Vec<PluginCard>,
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
            let mut detail = json_str(o.get("detail"));
            if detail.is_empty() {
                detail = json_str(o.get("summary"));
            }
            let notes = json_str(o.get("notes"));
            let mut result = json_str(o.get("result"));
            if result.is_empty() {
                result = json_str(o.get("outcome"));
            }
            let mut sections = vec![format!("# {title}"), String::new()];
            if is_plan {
                sections.push("Your Sovereign proposes this plan.".to_owned());
                sections.push(String::new());
            }
            sections.push(format!("Owner: {owner}"));
            sections.push(format!("Status: {status}"));
            if !detail.is_empty() {
                sections.push(String::new());
                sections.push(detail);
            }
            if !result.is_empty() {
                sections.push(String::new());
                sections.push("## Result".to_owned());
                sections.push(result);
            }
            if !notes.is_empty() {
                sections.push(String::new());
                sections.push("## Notes".to_owned());
                sections.push(notes);
            }
            let body = sections.join("\n");
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
            risks: p
                .get("risks")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default()
                .iter()
                .filter_map(|s| s.as_str().map(str::to_owned))
                .collect(),
            comments: Vec::new(),
            related_mission: {
                let a = json_str(p.get("related_mission"));
                if a.is_empty() {
                    json_str(p.get("relatedMission"))
                } else {
                    a
                }
            },
        })
        .collect();

    let mut targets = Vec::new();
    if let Some(arr) = mission.get("targets").and_then(|v| v.as_array()) {
        for item in arr {
            if let Some(obj) = item.as_object() {
                let title = json_str(obj.get("title"));
                if title.is_empty() {
                    continue;
                }
                let mut id = json_str(obj.get("id"));
                if id.is_empty() {
                    id = title.clone();
                }
                targets.push(CommitmentItem {
                    id,
                    title,
                    description: json_str(obj.get("description")),
                });
            } else {
                let text = json_str(Some(item));
                if !text.is_empty() {
                    targets.push(CommitmentItem {
                        id: text.clone(),
                        title: text,
                        description: String::new(),
                    });
                }
            }
        }
    }

    let orb_swarms: Vec<SwarmOrb> = swarms
        .iter()
        .take(6)
        .map(|s| {
            let id = json_str(s.get("id"));
            let objective = json_str(s.get("objective"));
            let open_signals = signals
                .iter()
                .filter(|sig| json_str(sig.get("swarm_id")) == id)
                .filter(|sig| {
                    let st = json_str(sig.get("status")).to_lowercase();
                    st.is_empty() || st == "open" || st == "pending"
                })
                .count();
            let outcome_n = outcomes
                .iter()
                .filter(|o| json_str(o.get("swarm_id")) == id)
                .count();
            let detail = format!(
                "{} open decision{} · {} outcome{}",
                open_signals,
                if open_signals == 1 { "" } else { "s" },
                outcome_n,
                if outcome_n == 1 { "" } else { "s" },
            );
            let signal_items: Vec<(String, String)> = signals
                .iter()
                .filter(|sig| json_str(sig.get("swarm_id")) == id)
                .filter(|sig| {
                    let st = json_str(sig.get("status")).to_lowercase();
                    st.is_empty() || st == "open" || st == "pending"
                })
                .take(6)
                .map(|sig| {
                    (
                        json_str(sig.get("id")),
                        json_str(sig.get("message")),
                    )
                })
                .filter(|(_, msg)| !msg.is_empty())
                .collect();
            let outcome_items: Vec<String> = outcomes
                .iter()
                .filter(|o| json_str(o.get("swarm_id")) == id)
                .take(6)
                .map(|o| json_str(o.get("description")))
                .filter(|d| !d.is_empty())
                .collect();
            SwarmOrb {
                id,
                name: json_str(s.get("display_name")),
                pulse: json_str(s.get("pulse")),
                objective,
                detail,
                signals: signal_items,
                outcomes: outcome_items,
            }
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
        templates: Vec::new(),
        mission: MissionInfo {
            statement: json_str(mission.get("statement")),
            targets,
        },
        swarms: orb_swarms,
        fleet_peers: Vec::new(),
        ops: Vec::new(),
        plugins: Vec::new(),
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
    if let Some(resp) = run_bridge_action("plan_templates_list", serde_json::json!({})) {
        if resp.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            feed.templates = resp
                .get("templates")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
                .map(|t| PlanTemplateItem {
                    id: json_str(t.get("id")),
                    title: json_str(t.get("title")),
                    summary: {
                        let mut s = json_str(t.get("summary"));
                        if s.is_empty() {
                            s = json_str(t.get("goal"));
                        }
                        s
                    },
                })
                .filter(|t| !t.id.is_empty() && !t.title.is_empty())
                .collect();
        }
    }
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

    // Enrich plan bodies via plan_get when list payloads are stubby.
    for plan in feed.plans.iter_mut().take(8) {
        let Some(resp) = run_bridge_action(
            "plan_get",
            serde_json::json!({ "plan_id": plan.id }),
        ) else {
            continue;
        };
        if resp.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            continue;
        }
        let Some(full) = resp.get("plan") else { continue };
        let goal = json_str(full.get("goal"));
        let summary = json_str(full.get("summary"));
        if !goal.is_empty() {
            plan.goal = goal;
        }
        if !summary.is_empty() {
            plan.summary = summary;
        }
        let steps = full
            .get("steps")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(|s| s.as_str().map(str::to_owned))
            .collect::<Vec<_>>();
        if !steps.is_empty() {
            plan.steps = steps;
        }
        let risks = full
            .get("risks")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(|s| s.as_str().map(str::to_owned))
            .collect::<Vec<_>>();
        if !risks.is_empty() {
            plan.risks = risks;
        }
        let mut comment_lines = Vec::new();
        if let Some(arr) = full
            .pointer("/share/comments")
            .or_else(|| full.get("comments"))
            .and_then(|v| v.as_array())
        {
            for c in arr.iter().take(12) {
                let mut body = json_str(c.get("body"));
                if body.is_empty() {
                    body = json_str(c.get("text"));
                }
                if body.is_empty() {
                    continue;
                }
                let author = json_str(c.get("author"));
                comment_lines.push(if author.is_empty() {
                    body
                } else {
                    format!("{author}: {body}")
                });
            }
        }
        if !comment_lines.is_empty() {
            plan.comments = comment_lines;
        }
    }
    for doc in feed.outputs.iter_mut() {
        let Some(plan_id) = doc.plan_id.clone() else { continue };
        if let Some(plan) = feed.plans.iter().find(|p| p.id == plan_id) {
            let mut body = format!("# {}\n\n{}\n", plan.title, plan.summary);
            if !plan.goal.is_empty() {
                body.push_str(&format!("\nGoal: {}\n", plan.goal));
            }
            if !plan.steps.is_empty() {
                body.push_str("\nSteps:\n");
                for step in &plan.steps {
                    body.push_str(&format!("- {step}\n"));
                }
            }
            if !plan.risks.is_empty() {
                body.push_str("\nRisks:\n");
                for risk in &plan.risks {
                    body.push_str(&format!("- {risk}\n"));
                }
            }
            doc.body = body;
            if doc.summary.is_empty() {
                doc.summary = plan.summary.clone();
            }
        }
    }

    if let Some(resp) = run_bridge_action("ops_glance", serde_json::json!({})) {
        if resp.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            let mut ops = Vec::new();
            for job in resp
                .get("cron")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
            {
                let name = json_str(job.get("name"));
                if name.is_empty() {
                    continue;
                }
                let schedule = json_str(job.get("schedule"));
                let next = json_str(job.get("next_run"));
                ops.push(OpsItem {
                    id: json_str(job.get("id")),
                    title: name,
                    detail: if !next.is_empty() {
                        format!("Next: {next}")
                    } else if !schedule.is_empty() {
                        schedule
                    } else {
                        "Scheduled job".to_owned()
                    },
                    kind: "cron".to_owned(),
                });
            }
            for task in resp
                .get("kanban")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
            {
                let title = json_str(task.get("title"));
                if title.is_empty() {
                    continue;
                }
                ops.push(OpsItem {
                    id: json_str(task.get("id")),
                    title,
                    detail: format!("Board · {}", json_str(task.get("status"))),
                    kind: "kanban".to_owned(),
                });
            }
            feed.ops = ops;
        }
    }

    if let Some(resp) = run_bridge_action("client_plugin_cards", serde_json::json!({})) {
        if resp.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            feed.plugins = resp
                .get("cards")
                .and_then(|v| v.as_array())
                .into_iter()
                .flatten()
                .filter(|c| {
                    let surface = json_str(c.get("surface")).to_lowercase();
                    surface.is_empty() || surface == "home" || surface == "both"
                })
                .map(|c| PluginCard {
                    id: json_str(c.get("id")),
                    title: json_str(c.get("title")),
                    subtitle: json_str(c.get("subtitle")),
                    ask_prompt: json_str(c.get("ask_prompt")),
                })
                .filter(|c| !c.title.is_empty())
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

fn fetch_plan_item(plan_id: &str) -> Option<PlanItem> {
    let resp = run_bridge_action("plan_get", serde_json::json!({ "plan_id": plan_id }))?;
    if resp.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return None;
    }
    let full = resp.get("plan")?;
    let mut comment_lines = Vec::new();
    if let Some(arr) = full
        .pointer("/share/comments")
        .or_else(|| full.get("comments"))
        .and_then(|v| v.as_array())
    {
        for c in arr {
            let author = json_str(c.get("author"));
            let body = json_str(c.get("body"));
            if body.is_empty() {
                continue;
            }
            comment_lines.push(if author.is_empty() {
                body
            } else {
                format!("{author}: {body}")
            });
        }
    }
    Some(PlanItem {
        id: json_str(full.get("id")),
        title: json_str(full.get("title")),
        summary: json_str(full.get("summary")),
        status: json_str(full.get("status")),
        goal: json_str(full.get("goal")),
        steps: full
            .get("steps")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(|s| s.as_str().map(str::to_owned))
            .collect(),
        risks: full
            .get("risks")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(|s| s.as_str().map(str::to_owned))
            .collect(),
        comments: comment_lines,
        related_mission: {
            let a = json_str(full.get("related_mission"));
            if a.is_empty() {
                json_str(full.get("relatedMission"))
            } else {
                a
            }
        },
    })
}

fn plan_topic_from_item(plan: &PlanItem) -> DiscussTopic {
    DiscussTopic::Plan {
        id: plan.id.clone(),
        title: plan.title.clone(),
        status: plan.status.clone(),
        goal: plan.goal.clone(),
        summary: plan.summary.clone(),
        steps: plan.steps.clone(),
        risks: plan.risks.clone(),
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

/// Like `run_async_result`, but runs `on_ok` on the UI thread after success (before refresh).
fn run_async_then<F>(
    parent: gtk::Widget,
    refresh: Rc<dyn Fn()>,
    work: F,
    on_ok: Rc<dyn Fn()>,
) where
    F: FnOnce() -> Result<(), String> + Send + 'static,
{
    let (tx, rx) = mpsc::channel::<Result<(), String>>();
    thread::spawn(move || {
        let _ = tx.send(work());
    });
    glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
        Ok(Ok(())) => {
            on_ok();
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

fn pulse_seen_path() -> std::path::PathBuf {
    std::path::PathBuf::from(crate::chat_page::resolve_centurion_home()).join("brain_pulse_seen.json")
}

fn load_pulse_seen() -> Value {
    let path = pulse_seen_path();
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| serde_json::json!({ "seen": {}, "visited_at": {} }))
}

fn save_pulse_seen(value: &Value) {
    let path = pulse_seen_path();
    if let Ok(bytes) = serde_json::to_vec_pretty(value) {
        let _ = std::fs::write(path, bytes);
    }
}

fn pulse_key(cat: PulseCategory) -> &'static str {
    match cat {
        PulseCategory::Live => "live",
        PulseCategory::Plans => "plans",
        PulseCategory::Wins => "wins",
        PulseCategory::Outputs => "outputs",
        PulseCategory::Decisions => "decisions",
        PulseCategory::Pulse => "pulse",
    }
}

fn feed_ids_for_category(data: &HomeFeed, cat: PulseCategory) -> Vec<String> {
    match cat {
        PulseCategory::Live => data
            .live
            .as_ref()
            .map(|l| vec![l.id.clone()])
            .unwrap_or_default()
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect(),
        PulseCategory::Plans => data.plans.iter().map(|p| p.id.clone()).collect(),
        PulseCategory::Wins => data.wins.iter().map(|w| w.id.clone()).collect(),
        PulseCategory::Outputs => data.outputs.iter().map(|d| d.id.clone()).collect(),
        PulseCategory::Decisions => data.decisions.iter().map(|d| d.id.clone()).collect(),
        PulseCategory::Pulse => data.thoughts.iter().map(|t| t.id.clone()).collect(),
    }
}

fn live_presence_badge(data: &HomeFeed) -> usize {
    // iPhone Live pill: presence 0/1 — visiting does not clear while work is active.
    if data.live.is_some() {
        return 1;
    }
    if data.swarms.iter().any(|s| {
        matches!(
            s.pulse.to_lowercase().as_str(),
            "active" | "blocked" | "forming" | "attention" | "waiting"
        )
    }) {
        return 1;
    }
    0
}

fn new_count_for_category(data: &HomeFeed, cat: PulseCategory, seen: &Value) -> usize {
    if cat == PulseCategory::Live {
        return live_presence_badge(data);
    }
    let ids = feed_ids_for_category(data, cat);
    if ids.is_empty() {
        return 0;
    }
    let key = pulse_key(cat);
    // Empty seen ⇒ all current IDs count as new (iPhone lastSeen ≈ 0).
    let seen_ids: std::collections::HashSet<String> = seen
        .pointer(&format!("/seen/{key}"))
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str().map(str::to_owned))
        .collect();
    ids.into_iter().filter(|id| !seen_ids.contains(id)).count()
}

fn total_attention_count(data: &HomeFeed, seen: &Value) -> u32 {
    PulseCategory::ALL
        .iter()
        .map(|cat| new_count_for_category(data, *cat, seen) as u32)
        .sum()
}

/// Categories with new/unread items — used for the in-tab attention banner.
fn attention_breakdown(data: &HomeFeed, seen: &Value) -> Vec<(String, u32)> {
    PulseCategory::ALL
        .iter()
        .filter_map(|cat| {
            let n = new_count_for_category(data, *cat, seen) as u32;
            if n > 0 {
                Some((cat.title().to_owned(), n))
            } else {
                None
            }
        })
        .collect()
}

fn rebuild_attention_banner(banner: &gtk::Box, lines: &[(String, u32)]) {
    clear_box(banner);
    if lines.is_empty() {
        banner.set_visible(false);
        return;
    }
    banner.set_visible(true);
    let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    title_row.append(
        &gtk::Label::builder()
            .label("(!)")
            .css_classes(["centurion-attention-mark"])
            .build(),
    );
    title_row.append(
        &gtk::Label::builder()
            .label("New since you last looked")
            .css_classes(["centurion-attention-banner-title"])
            .xalign(0.0)
            .hexpand(true)
            .build(),
    );
    banner.append(&title_row);
    for (name, n) in lines {
        banner.append(
            &gtk::Label::builder()
                .label(&format!("• {name} ({n}) — open that pill to review"))
                .css_classes(["centurion-attention-item"])
                .xalign(0.0)
                .wrap(true)
                .build(),
        );
    }
}

fn mark_category_seen(data: &HomeFeed, cat: PulseCategory) {
    let mut store = load_pulse_seen();
    let key = pulse_key(cat);
    let ids = feed_ids_for_category(data, cat);
    let seen = store
        .as_object_mut()
        .map(|o| o.entry("seen".to_owned()).or_insert_with(|| serde_json::json!({})));
    if let Some(Value::Object(map)) = seen {
        map.insert(
            key.to_owned(),
            Value::Array(ids.into_iter().map(Value::String).collect()),
        );
    }
    if let Some(obj) = store.as_object_mut() {
        let visited = obj
            .entry("visited_at".to_owned())
            .or_insert_with(|| serde_json::json!({}));
        if let Some(vmap) = visited.as_object_mut() {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            vmap.insert(key.to_owned(), Value::from(now));
        }
    }
    save_pulse_seen(&store);
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

pub fn show_mission_edit_dialog(
    parent: &impl IsA<gtk::Widget>,
    current: &str,
    refresh: Rc<dyn Fn()>,
) {
    let entry = gtk::TextView::builder()
        .wrap_mode(gtk::WrapMode::WordChar)
        .hexpand(true)
        .vexpand(true)
        .build();
    // Present first with whatever we already have (often empty). Fill from the
    // bridge afterward so Settings Edit never blocks on Python/bridge warmup.
    if !current.is_empty() {
        entry.buffer().set_text(current);
    }
    let scrolled = gtk::ScrolledWindow::builder()
        .child(&entry)
        .min_content_height(120)
        .hexpand(true)
        .build();
    let dialog = adw::AlertDialog::builder()
        .heading("Life Mission")
        .body(if current.is_empty() {
            "Loading your current mission…"
        } else {
            "What are you building toward? Your Sovereign uses this to stay aligned."
        })
        .extra_child(&scrolled)
        .close_response("cancel")
        .default_response("save")
        .build();
    dialog.add_response("cancel", "Cancel");
    dialog.add_response("save", "Save");
    dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
    if current.is_empty() {
        let entry_fill = entry.clone();
        let dialog_fill = dialog.clone();
        crate::chat_page::run_bridge_action_async(
            "mission_get",
            serde_json::json!({}),
            move |payload| {
                let statement = payload
                    .and_then(|r| {
                        if r.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                            r.get("mission")
                                .and_then(|m| m.get("statement"))
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_owned())
                        } else {
                            None
                        }
                    })
                    .unwrap_or_default();
                // Only fill if the user hasn't started typing yet.
                let (start, end) = entry_fill.buffer().bounds();
                let existing = entry_fill.buffer().text(&start, &end, false);
                if existing.trim().is_empty() && !statement.is_empty() {
                    entry_fill.buffer().set_text(&statement);
                }
                dialog_fill.set_body(
                    "What are you building toward? Your Sovereign uses this to stay aligned.",
                );
            },
        );
    }
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

fn find_app_window(widget: &impl IsA<gtk::Widget>) -> Option<adw::ApplicationWindow> {
    widget
        .root()
        .and_then(|r| r.downcast::<adw::ApplicationWindow>().ok())
}

fn load_decision_first_pref() -> bool {
    let path = std::path::PathBuf::from(crate::chat_page::resolve_centurion_home())
        .join("brain_decision_first");
    std::fs::read_to_string(path)
        .map(|s| s.trim() == "1" || s.trim().eq_ignore_ascii_case("true"))
        .unwrap_or(true)
}

fn show_collab_detail_dialog(
    parent: &impl IsA<gtk::Widget>,
    orb: &SwarmOrb,
    on_ask: Rc<dyn Fn(DiscussTopic, String)>,
    refresh: Rc<dyn Fn()>,
) {
    let body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    if !orb.objective.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label(&format!("Objective: {}", orb.objective))
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
    }
    body.append(
        &gtk::Label::builder()
            .label(&format!("Pulse: {}", orb.pulse))
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );
    if !orb.detail.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label(&orb.detail)
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
    }
    if !orb.signals.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label("Open decisions")
                .xalign(0.0)
                .css_classes(["heading"])
                .margin_top(6)
                .build(),
        );
        for (signal_id, message) in &orb.signals {
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
            row.append(
                &gtk::Label::builder()
                    .label(message)
                    .wrap(true)
                    .xalign(0.0)
                    .hexpand(true)
                    .build(),
            );
            if !signal_id.is_empty() {
                let resolve = gtk::Button::with_label("Resolve");
                resolve.add_css_class("flat");
                let note_btn = gtk::Button::with_label("Note");
                note_btn.add_css_class("flat");
                let hold_btn = gtk::Button::with_label("Hold");
                hold_btn.add_css_class("flat");
                let parent_w = parent.clone().upcast::<gtk::Widget>();
                let refresh_r = refresh.clone();
                let signal_id_r = signal_id.clone();
                let message = message.clone();
                resolve.connect_clicked(move |_| {
                    let parent_w = parent_w.clone();
                    let refresh = refresh_r.clone();
                    let signal_id = signal_id_r.clone();
                    let note = format!("Resolved from Home: {message}");
                    run_async_result(parent_w, refresh, move || resolve_signal(&signal_id, &note));
                });
                let parent_n = parent.clone().upcast::<gtk::Widget>();
                let refresh_n = refresh.clone();
                let signal_id_n = signal_id.clone();
                note_btn.connect_clicked(move |_| {
                    prompt_signal_note(
                        &parent_n,
                        signal_id_n.clone(),
                        "Add note",
                        "Note for this collaboration decision",
                        refresh_n.clone(),
                    );
                });
                let parent_h = parent.clone().upcast::<gtk::Widget>();
                let refresh_h = refresh.clone();
                let signal_id_h = signal_id.clone();
                hold_btn.connect_clicked(move |_| {
                    let parent_h = parent_h.clone();
                    let refresh_h = refresh_h.clone();
                    let signal_id = signal_id_h.clone();
                    run_async_result(parent_h, refresh_h, move || {
                        resolve_signal(&signal_id, "Hold")
                    });
                });
                row.append(&resolve);
                row.append(&note_btn);
                row.append(&hold_btn);
            }
            body.append(&row);
        }
    }
    if !orb.outcomes.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label("Outcomes")
                .xalign(0.0)
                .css_classes(["heading"])
                .margin_top(6)
                .build(),
        );
        for outcome in &orb.outcomes {
            body.append(
                &gtk::Label::builder()
                    .label(&format!("• {outcome}"))
                    .wrap(true)
                    .xalign(0.0)
                    .build(),
            );
        }
    }
    let dialog = adw::AlertDialog::builder()
        .heading(&orb.name)
        .body("Collaboration detail")
        .extra_child(&body)
        .close_response("close")
        .default_response("discuss")
        .build();
    dialog.add_response("close", "Close");
    dialog.add_response("note", "Add note");
    dialog.add_response("discuss", "Discuss");
    dialog.set_response_appearance("discuss", adw::ResponseAppearance::Suggested);
    let orb_id = orb.id.clone();
    let name = orb.name.clone();
    let objective = orb.objective.clone();
    let pulse = orb.pulse.clone();
    let first_signal = orb
        .signals
        .iter()
        .find(|(id, _)| !id.is_empty())
        .map(|(id, _)| id.clone());
    let parent_w = parent.clone().upcast::<gtk::Widget>();
    let refresh_n = refresh.clone();
    dialog.connect_response(None, move |_d, response| match response {
        "discuss" => {
            on_ask(
                DiscussTopic::Collab {
                    id: orb_id.clone(),
                    name: name.clone(),
                    pulse: pulse.clone(),
                    objective: objective.clone(),
                },
                format!(
                    "Let's discuss collaboration “{name}” (pulse: {pulse}).\n\nObjective: {objective}\n\nWhat should we do next?"
                ),
            );
        }
        "note" => {
            if let Some(sid) = first_signal.clone() {
                prompt_signal_note(
                    &parent_w,
                    sid,
                    "Add collaboration note",
                    "Note attached to the open decision",
                    refresh_n.clone(),
                );
            } else {
                on_ask(
                    DiscussTopic::Collab {
                        id: orb_id.clone(),
                        name: name.clone(),
                        pulse: pulse.clone(),
                        objective: objective.clone(),
                    },
                    format!(
                        "Note on collaboration “{name}” (pulse: {pulse}).\n\nObjective: {objective}\n\n"
                    ),
                );
            }
        }
        _ => {}
    });
    dialog.present(Some(parent));
}

pub fn show_connect_collab_dialog(parent: &impl IsA<gtk::Widget>, refresh: Rc<dyn Fn()>) {
    // Portal Mission Control (ctk_proj tokens) is frozen. Local boards only.
    let box_ = gtk::Box::new(gtk::Orientation::Vertical, 10);
    let board_title = gtk::Entry::builder()
        .placeholder_text("Board title")
        .hexpand(true)
        .build();
    box_.append(&board_title);
    let dialog = adw::AlertDialog::builder()
        .heading("Local collaboration board")
        .body(
            "Create a local board on this Brain. Portal Mission Control tokens \
             are not used — Life Missions stay offline in life.db.",
        )
        .extra_child(&box_)
        .close_response("cancel")
        .default_response("board")
        .build();
    dialog.add_response("cancel", "Cancel");
    dialog.add_response("board", "Create board");
    dialog.set_response_appearance("board", adw::ResponseAppearance::Suggested);
    let parent_w = parent.clone().upcast::<gtk::Widget>();
    dialog.connect_response(None, move |_d, response| {
        if response != "board" {
            return;
        }
        let board_v = board_title.text().trim().to_owned();
        let refresh = refresh.clone();
        let parent_w = parent_w.clone();
        run_async_result(parent_w, refresh, move || {
            let payload = run_bridge_action(
                "swarm_create_board",
                serde_json::json!({
                    "name": if board_v.is_empty() {
                        "Desk collaboration".to_owned()
                    } else {
                        board_v
                    },
                    "objective": "Desk collaboration board",
                }),
            )
            .ok_or_else(|| "Could not reach the collaboration service.".to_owned())?;
            if payload.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                Ok(())
            } else {
                Err(payload
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Could not create local board.")
                    .to_owned())
            }
        });
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

fn copy_text_to_clipboard(text: &str) {
    if let Some(display) = gtk::gdk::Display::default() {
        display.clipboard().set_text(text);
    }
}

fn comment_on_plan(plan_id: &str, body: &str) -> Result<(), String> {
    let response = run_bridge_action(
        "plan_comment",
        serde_json::json!({
            "plan_id": plan_id,
            "body": body,
            "author": "desk",
        }),
    )
    .ok_or_else(|| "Could not add comment.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Comment failed.")
            .to_owned())
    }
}

fn save_plan_template(plan_id: &str) -> Result<(), String> {
    let response = run_bridge_action(
        "plan_save_template",
        serde_json::json!({ "plan_id": plan_id }),
    )
    .ok_or_else(|| "Could not save template.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not save as template.")
            .to_owned())
    }
}

fn instantiate_plan_template(template_id: &str) -> Result<(), String> {
    let response = run_bridge_action(
        "plan_template_instantiate",
        serde_json::json!({ "template_id": template_id }),
    )
    .ok_or_else(|| "Could not create plan from template.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Template instantiate failed.")
            .to_owned())
    }
}

fn prompt_plan_comment(
    parent: &impl IsA<gtk::Widget>,
    plan_id: String,
    refresh: Rc<dyn Fn()>,
) {
    let entry = gtk::Entry::builder()
        .placeholder_text("Add a review comment")
        .hexpand(true)
        .build();
    let ask = adw::AlertDialog::builder()
        .heading("Comment on plan")
        .extra_child(&entry)
        .close_response("cancel")
        .default_response("send")
        .build();
    ask.add_response("cancel", "Cancel");
    ask.add_response("send", "Add comment");
    ask.set_response_appearance("send", adw::ResponseAppearance::Suggested);
    let parent_for_cb = parent.clone().upcast::<gtk::Widget>();
    let parent_for_present = parent.clone().upcast::<gtk::Widget>();
    ask.connect_response(None, move |_d, response| {
        if response != "send" {
            return;
        }
        let body_text = entry.text().trim().to_owned();
        if body_text.is_empty() {
            show_home_error(&parent_for_cb, "Enter a comment first.");
            return;
        }
        let plan_id = plan_id.clone();
        let parent_for_async = parent_for_cb.clone();
        let refresh = refresh.clone();
        run_async_result(parent_for_async, refresh, move || {
            comment_on_plan(&plan_id, &body_text)
        });
    });
    ask.present(Some(&parent_for_present));
}

fn prompt_signal_note(
    parent: &impl IsA<gtk::Widget>,
    signal_id: String,
    heading: &str,
    placeholder: &str,
    refresh: Rc<dyn Fn()>,
) {
    let entry = gtk::Entry::builder()
        .placeholder_text(placeholder)
        .hexpand(true)
        .build();
    let ask = adw::AlertDialog::builder()
        .heading(heading)
        .extra_child(&entry)
        .close_response("cancel")
        .default_response("send")
        .build();
    ask.add_response("cancel", "Cancel");
    ask.add_response("send", "Save note");
    ask.set_response_appearance("send", adw::ResponseAppearance::Suggested);
    let parent_for_cb = parent.clone().upcast::<gtk::Widget>();
    let parent_for_present = parent.clone().upcast::<gtk::Widget>();
    ask.connect_response(None, move |_d, response| {
        if response != "send" {
            return;
        }
        let note = entry.text().trim().to_owned();
        if note.is_empty() {
            show_home_error(&parent_for_cb, "Enter a note first.");
            return;
        }
        let signal_id = signal_id.clone();
        let parent_for_async = parent_for_cb.clone();
        let refresh = refresh.clone();
        run_async_result(parent_for_async, refresh, move || {
            resolve_signal(&signal_id, &note)
        });
    });
    ask.present(Some(&parent_for_present));
}

fn show_document_dialog(
    parent: &impl IsA<gtk::Widget>,
    doc: &DocumentItem,
    on_ask: Rc<dyn Fn(DiscussTopic, String)>,
    refresh: Rc<dyn Fn()>,
    plans: &[PlanItem],
) {
    // Plan-linked documents open the full plan review surface.
    if let Some(pid) = doc.plan_id.as_ref() {
        if let Some(plan) = plans.iter().find(|p| &p.id == pid) {
            show_plan_dialog(parent, plan, refresh, on_ask);
            return;
        }
        if let Some(plan) = fetch_plan_item(pid) {
            show_plan_dialog(parent, &plan, refresh, on_ask);
            return;
        }
    }
    // Outcome docs: title / id heuristic → known plan, then plan_get.
    let title_l = doc.title.to_lowercase();
    if let Some(plan) = plans.iter().find(|p| {
        (!p.id.is_empty() && title_l.contains(&p.id.to_lowercase()))
            || (!p.title.is_empty()
                && (title_l == p.title.to_lowercase()
                    || title_l.contains(&p.title.to_lowercase())
                    || p.title.to_lowercase().contains(&title_l)))
    }) {
        show_plan_dialog(parent, plan, refresh, on_ask);
        return;
    }
    // If the doc id looks like plan:<id>, try plan_get.
    if let Some(pid) = doc
        .id
        .strip_prefix("plan:")
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if let Some(plan) = fetch_plan_item(pid) {
            show_plan_dialog(parent, &plan, refresh, on_ask);
            return;
        }
    }

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
        .default_response("discuss")
        .build();
    dialog.add_response("close", "Close");
    dialog.add_response("copy", "Copy");
    dialog.add_response("share", "Share");
    dialog.add_response("discuss", "Discuss");
    if doc.plan_id.is_some() {
        dialog.add_response("comment", "Comment");
    }
    dialog.set_response_appearance("discuss", adw::ResponseAppearance::Suggested);
    let title = doc.title.clone();
    let body = doc.body.clone();
    let summary = doc.summary.clone();
    let plan_id = doc.plan_id.clone();
    let parent_w = parent.clone().upcast::<gtk::Widget>();
    let refresh = refresh.clone();
    dialog.connect_response(None, move |_d, response| match response {
        "copy" | "share" => {
            copy_text_to_clipboard(&body);
            let done = adw::AlertDialog::builder()
                .heading(if response == "share" {
                    "Ready to share"
                } else {
                    "Copied"
                })
                .body("Document text is on the clipboard — paste into email, chat, or notes.")
                .close_response("ok")
                .build();
            done.add_response("ok", "OK");
            done.present(Some(&parent_w));
        }
                "discuss" => {
            on_ask(
                DiscussTopic::Document {
                    id: None,
                    mission_id: None,
                    doc_type: None,
                    title: title.clone(),
                    summary: summary.clone(),
                    plan_id: plan_id.clone(),
                    body_excerpt: body.clone(),
                },
                format!(
                    "Let's discuss this document.\n\n{title}\n\n{summary}\n\nWhat should we do with it?"
                ),
            );
        }
        "comment" => {
            if let Some(pid) = plan_id.clone() {
                prompt_plan_comment(&parent_w, pid, refresh.clone());
            }
        }
        _ => {}
    });
    dialog.present(Some(parent));
}

fn show_plan_dialog(
    parent: &impl IsA<gtk::Widget>,
    plan: &PlanItem,
    refresh: Rc<dyn Fn()>,
    on_ask: Rc<dyn Fn(DiscussTopic, String)>,
) {
    let body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    if !plan.related_mission.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label(&format!("From mission · {}", plan.related_mission))
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
    }
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
    for risk in &plan.risks {
        body.append(
            &gtk::Label::builder()
                .label(&format!("Risk: {risk}"))
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
    }
    if !plan.comments.is_empty() {
        body.append(
            &gtk::Label::builder()
                .label("Comments")
                .xalign(0.0)
                .css_classes(["heading"])
                .margin_top(6)
                .build(),
        );
        for comment in &plan.comments {
            body.append(
                &gtk::Label::builder()
                    .label(comment)
                    .wrap(true)
                    .xalign(0.0)
                    .css_classes(["dim-label"])
                    .build(),
            );
        }
    }
    let dialog = adw::AlertDialog::builder()
        .heading(&plan.title)
        .body(&format!("Status: {}", plan.status))
        .extra_child(&body)
        .close_response("close")
        .default_response("discuss")
        .build();
    dialog.add_response("close", "Close");
    dialog.add_response("discuss", "Discuss");
    dialog.add_response("share", "Share");
    dialog.add_response("comment", "Comment");
    dialog.add_response("template", "Save template");
    dialog.set_response_appearance("discuss", adw::ResponseAppearance::Suggested);
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
    let goal = plan.goal.clone();
    let status = plan.status.clone();
    let steps = plan.steps.clone();
    let risks = plan.risks.clone();
    let parent_w = parent.clone().upcast::<gtk::Widget>();
    let parent_share = parent.clone().upcast::<gtk::Widget>();
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
                "discuss" => {
            let summary_text = if summary.is_empty() {
                "(no summary yet)".to_owned()
            } else {
                summary.clone()
            };
            on_ask(
                DiscussTopic::Plan {
                    id: plan_id.clone(),
                    title: title.clone(),
                    status: status.clone(),
                    goal: goal.clone(),
                    summary: summary.clone(),
                    steps: steps.clone(),
                    risks: risks.clone(),
                },
                format!(
                    "Let's discuss this plan.\n\nTitle: {title}\n\n{summary_text}\n\nGoal: {goal}\n\nWhat should change or stay?"
                ),
            );
        }
        "adjust" => {
            let plan_id = plan_id.clone();
            let refresh = refresh.clone();
            let parent_w = parent_w.clone();
            let on_ask = on_ask.clone();
            let title = title.clone();
            let summary = summary.clone();
            let status = status.clone();
            let goal = goal.clone();
            let steps = steps.clone();
            let risks = risks.clone();
            // Await request_changes, then open discuss with full plan identity.
            let on_ok = Rc::new({
                let plan_id = plan_id.clone();
                let title = title.clone();
                let summary = summary.clone();
                let status = status.clone();
                let goal = goal.clone();
                let steps = steps.clone();
                let risks = risks.clone();
                let on_ask = on_ask.clone();
                move || {
                    on_ask(
                        DiscussTopic::Plan {
                            id: plan_id.clone(),
                            title: title.clone(),
                            status: status.clone(),
                            goal: goal.clone(),
                            summary: summary.clone(),
                            steps: steps.clone(),
                            risks: risks.clone(),
                        },
                        format!(
                            "I'd like to adjust this plan.\n\n{}\n\nWhat should change?",
                            summary
                        ),
                    );
                }
            }) as Rc<dyn Fn()>;
            let plan_id_work = plan_id.clone();
            run_async_then(parent_w, refresh, move || {
                decide_plan(&plan_id_work, "request_changes")
            }, on_ok);
        }
        "comment" => {
            prompt_plan_comment(&parent_share, plan_id.clone(), refresh.clone());
        }
        "template" => {
            let plan_id = plan_id.clone();
            let refresh = refresh.clone();
            let parent_w = parent_w.clone();
            run_async_result(parent_w, refresh, move || save_plan_template(&plan_id));
        }
        "share" => {
            let plan_id = plan_id.clone();
            let parent_for_cb = parent_share.clone();
            let parent_for_present = parent_share.clone();
            let refresh = refresh.clone();
            let entry = gtk::Entry::builder()
                .placeholder_text("Reviewer customer id")
                .hexpand(true)
                .build();
            let ask = adw::AlertDialog::builder()
                .heading("Share plan")
                .body("Enter the reviewer customer id for co-review.")
                .extra_child(&entry)
                .close_response("cancel")
                .default_response("send")
                .build();
            ask.add_response("cancel", "Cancel");
            ask.add_response("send", "Share");
            ask.set_response_appearance("send", adw::ResponseAppearance::Suggested);
            ask.connect_response(None, move |_d, response| {
                if response != "send" {
                    return;
                }
                let reviewer = entry.text().trim().to_owned();
                if reviewer.is_empty() {
                    show_home_error(&parent_for_cb, "Reviewer customer id is required.");
                    return;
                }
                let plan_id = plan_id.clone();
                let parent_for_async = parent_for_cb.clone();
                let refresh = refresh.clone();
                run_async_result(parent_for_async, refresh, move || {
                    let response = run_bridge_action(
                        "plan_share",
                        serde_json::json!({
                            "plan_id": plan_id,
                            "reviewer_customer_id": reviewer,
                        }),
                    )
                    .ok_or_else(|| "Could not share plan.".to_owned())?;
                    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                        Ok(())
                    } else {
                        Err(response
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Share failed.")
                            .to_owned())
                    }
                });
            });
            ask.present(Some(&parent_for_present));
        }
        _ => {}
    });
    dialog.present(Some(parent));
}

fn target_type_label(ttype: &str) -> &'static str {
    match ttype {
        "shouldHave" | "should" => "Should Do",
        "niceToHave" | "nice" => "Nice to Do",
        _ => "Must Do",
    }
}

fn mission_display_title(mission: &Value) -> String {
    mission
        .get("title")
        .or_else(|| mission.get("statement"))
        .and_then(|v| v.as_str())
        .unwrap_or("Mission")
        .trim()
        .to_owned()
}

fn mission_discuss_topic(mission: &Value, target: Option<&Value>) -> DiscussTopic {
    let statement = mission
        .get("statement")
        .or_else(|| mission.get("title"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_owned();
    let title = mission
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned());
    let id = mission
        .get("id")
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned());
    let (target_id, target_title, target_type, target_description, target_status, sequence_number) =
        match target {
            Some(t) => (
                t.get("id").and_then(|v| v.as_str()).map(|s| s.to_owned()),
                t.get("title").and_then(|v| v.as_str()).map(|s| s.to_owned()),
                t.get("target_type")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_owned()),
                t.get("description")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_owned()),
                t.get("status")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_owned()),
                t.get("sequence_number")
                    .and_then(|v| v.as_i64())
                    .or_else(|| {
                        t.get("sequence_number")
                            .and_then(|v| v.as_u64())
                            .map(|n| n as i64)
                    }),
            ),
            None => (None, None, None, None, None, None),
        };
    DiscussTopic::Mission {
        statement,
        id,
        title,
        target_id,
        target_title,
        target_type,
        target_description,
        target_status,
        sequence_number,
    }
}

fn show_mission_detail_dialog(
    parent: &gtk::Widget,
    mission: Value,
    on_ask: Rc<dyn Fn(DiscussTopic, String)>,
) {
    let Some(window) = parent.root().and_downcast::<gtk::Window>() else {
        return;
    };
    let title = mission_display_title(&mission);
    let statement = mission
        .get("statement")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_owned();
    let situation = mission
        .get("situation")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_owned();
    let why = mission
        .get("why")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_owned();
    let purpose = mission
        .get("purpose")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_owned();
    let phase = mission
        .get("phase")
        .and_then(|v| v.as_str())
        .unwrap_or("executing")
        .to_owned();

    let body = gtk::Box::new(gtk::Orientation::Vertical, 10);
    body.set_margin_top(8);
    body.set_margin_bottom(8);
    body.set_margin_start(4);
    body.set_margin_end(4);

    let add_section = |box_: &gtk::Box, heading: &str, text: &str| {
        box_.append(
            &gtk::Label::builder()
                .label(heading)
                .css_classes(["caption-heading"])
                .xalign(0.0)
                .build(),
        );
        let content = if text.trim().is_empty() {
            "—"
        } else {
            text
        };
        box_.append(
            &gtk::Label::builder()
                .label(content)
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
    };
    add_section(&body, "Phase", &phase);
    add_section(&body, "Where I’m At", &situation);
    add_section(&body, "Why", &why);
    add_section(
        &body,
        "Success Looks Like",
        if purpose.trim().is_empty() {
            &statement
        } else {
            &purpose
        },
    );

    let targets = mission
        .get("targets")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    for kind in ["essential", "shouldHave", "niceToHave"] {
        let group: Vec<Value> = targets
            .iter()
            .filter(|t| t.get("target_type").and_then(|v| v.as_str()).unwrap_or("essential") == kind)
            .cloned()
            .collect();
        if group.is_empty() {
            continue;
        }
        body.append(
            &gtk::Label::builder()
                .label(target_type_label(kind))
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(8)
                .build(),
        );
        for t in group {
            let ttitle = t
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("Target")
                .to_owned();
            let focus = t
                .get("focus_target")
                .and_then(|v| v.as_bool().or_else(|| v.as_i64().map(|n| n != 0)))
                .unwrap_or(false);
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
            let mark = if focus { "◎" } else { "•" };
            row.append(
                &gtk::Label::builder()
                    .label(&format!("{mark} {ttitle}"))
                    .wrap(true)
                    .xalign(0.0)
                    .hexpand(true)
                    .build(),
            );
            let discuss = discuss_icon_button("Discuss this target");
            let on_ask_t = on_ask.clone();
            let mission_t = mission.clone();
            let target_t = t.clone();
            discuss.connect_clicked(move |_| {
                let topic = mission_discuss_topic(&mission_t, Some(&target_t));
                let name = mission_display_title(&mission_t);
                on_ask_t(
                    topic,
                    format!("Let's discuss the target “{ttitle}” on mission “{name}”."),
                );
            });
            row.append(&discuss);
            body.append(&row);
        }
    }

    let scroll = gtk::ScrolledWindow::builder()
        .child(&body)
        .min_content_height(280)
        .min_content_width(420)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .build();

    let dialog = adw::AlertDialog::builder()
        .heading(&title)
        .body("Mission detail — Discuss opens Chat with mission context.")
        .extra_child(&scroll)
        .close_response("close")
        .default_response("discuss")
        .build();
    dialog.add_response("close", "Close");
    dialog.add_response("discuss", "Discuss");
    dialog.set_response_appearance("discuss", adw::ResponseAppearance::Suggested);
    let on_ask_d = on_ask.clone();
    let mission_d = mission.clone();
    dialog.connect_response(None, move |_d, response| {
        if response == "discuss" {
            let topic = mission_discuss_topic(&mission_d, None);
            let name = mission_display_title(&mission_d);
            on_ask_d(
                topic,
                format!("Let's discuss my Mission: {name}\n\nWhat should we focus on next?"),
            );
        }
    });
    dialog.present(Some(&window));
}

fn rebuild_mission_stack_section(
    stack_box: &gtk::Box,
    parent: &gtk::Box,
    on_ask: Rc<dyn Fn(DiscussTopic, String)>,
    on_refresh: Rc<dyn Fn()>,
) {
    clear_box(stack_box);
    stack_box.append(
        &gtk::Label::builder()
            .label("MISSION STACK")
            .css_classes(["caption-heading"])
            .xalign(0.0)
            .build(),
    );

    let payload = run_bridge_action("life_stack_get", serde_json::json!({}));
    let stack = payload
        .as_ref()
        .filter(|p| p.get("ok").and_then(|v| v.as_bool()) == Some(true))
        .and_then(|p| p.get("stack").cloned());
    let Some(stack) = stack else {
        stack_box.append(&empty_label(
            "Could not load Mission Stack. Check that Centurion is installed on this Brain.",
        ));
        return;
    };

    let subjects = run_bridge_action("life_subjects_list", serde_json::json!({}))
        .and_then(|r| {
            r.get("subjects")
                .and_then(|v| v.as_array())
                .cloned()
        })
        .unwrap_or_default();

    if let Some(primary) = stack.get("primary").cloned() {
        stack_box.append(
            &gtk::Label::builder()
                .label("Primary Mission")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(4)
                .build(),
        );
        stack_box.append(&mission_stack_row(
            parent,
            primary,
            Some("Primary"),
            on_ask.clone(),
            on_refresh.clone(),
            false,
        ));
    } else {
        stack_box.append(&empty_label(
            "No Primary Mission yet — use Settings → Mission Discovery to set one.",
        ));
    }

    let supporting = stack
        .get("supporting")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if !supporting.is_empty() {
        stack_box.append(
            &gtk::Label::builder()
                .label("Supporting Missions")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(10)
                .build(),
        );
        for m in supporting.into_iter().take(12) {
            stack_box.append(&mission_stack_row(
                parent,
                m,
                None,
                on_ask.clone(),
                on_refresh.clone(),
                true,
            ));
        }
    }

    let dreams = stack
        .get("dreams")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if !dreams.is_empty() {
        stack_box.append(
            &gtk::Label::builder()
                .label("Dreams")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(10)
                .build(),
        );
        for d in dreams.into_iter().take(12) {
            let title = d
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("Dream")
                .to_owned();
            let desc = d
                .get("description")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();
            let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
            let labels = gtk::Box::new(gtk::Orientation::Vertical, 2);
            labels.set_hexpand(true);
            labels.append(
                &gtk::Label::builder()
                    .label(&title)
                    .xalign(0.0)
                    .wrap(true)
                    .css_classes(["heading"])
                    .build(),
            );
            if !desc.trim().is_empty() {
                labels.append(
                    &gtk::Label::builder()
                        .label(&desc)
                        .xalign(0.0)
                        .wrap(true)
                        .css_classes(["dim-label", "caption"])
                        .build(),
                );
            }
            row.append(&labels);
            let promote = gtk::Button::with_label("Promote");
            promote.set_valign(gtk::Align::Center);
            promote.add_css_class("flat");
            let dream_id = d
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();
            let on_refresh_p = on_refresh.clone();
            promote.connect_clicked(move |_| {
                if dream_id.is_empty() {
                    return;
                }
                let _ = run_bridge_action(
                    "life_dream_promote",
                    serde_json::json!({ "dream_id": dream_id }),
                );
                on_refresh_p();
            });
            row.append(&promote);
            stack_box.append(&row);
        }
    }

    if !subjects.is_empty() {
        stack_box.append(
            &gtk::Label::builder()
                .label("Subjects")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(10)
                .build(),
        );
        for s in subjects.into_iter().take(20) {
            let name = s.get("name").and_then(|v| v.as_str()).unwrap_or("?");
            stack_box.append(
                &gtk::Label::builder()
                    .label(&format!("• {name}"))
                    .xalign(0.0)
                    .build(),
            );
        }
    }
}

fn mission_stack_row(
    parent: &gtk::Box,
    mission: Value,
    badge: Option<&str>,
    on_ask: Rc<dyn Fn(DiscussTopic, String)>,
    on_refresh: Rc<dyn Fn()>,
    allow_make_primary: bool,
) -> gtk::Box {
    let row = gtk::Box::new(gtk::Orientation::Vertical, 4);
    row.add_css_class("centurion-mission-row");
    row.set_margin_top(4);
    row.set_margin_bottom(4);

    let title = mission_display_title(&mission);
    let phase = mission
        .get("phase")
        .and_then(|v| v.as_str())
        .unwrap_or("executing");
    let completed = mission
        .get("completed_target_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let total = mission
        .get("target_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(0)
        .max(1);
    let focus = mission
        .get("targets")
        .and_then(|v| v.as_array())
        .and_then(|arr| {
            arr.iter().find(|t| {
                t.get("focus_target")
                    .and_then(|v| v.as_bool().or_else(|| v.as_i64().map(|n| n != 0)))
                    .unwrap_or(false)
            })
        });
    let focus_line = focus
        .and_then(|t| t.get("title").and_then(|v| v.as_str()))
        .map(|t| format!("Focus · {t}"))
        .unwrap_or_default();

    let head = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title_col = gtk::Box::new(gtk::Orientation::Vertical, 2);
    title_col.set_hexpand(true);
    let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    title_row.append(
        &gtk::Label::builder()
            .label(&title)
            .xalign(0.0)
            .wrap(true)
            .css_classes(["heading"])
            .hexpand(true)
            .build(),
    );
    if let Some(badge) = badge {
        title_row.append(
            &gtk::Label::builder()
                .label(badge)
                .css_classes(["caption", "centurion-mission-badge"])
                .build(),
        );
    }
    title_col.append(&title_row);
    title_col.append(
        &gtk::Label::builder()
            .label(&format!("{phase} · {completed}/{total} targets"))
            .xalign(0.0)
            .css_classes(["dim-label", "caption"])
            .build(),
    );
    if !focus_line.is_empty() {
        title_col.append(
            &gtk::Label::builder()
                .label(&focus_line)
                .xalign(0.0)
                .css_classes(["dim-label", "caption"])
                .build(),
        );
    }
    head.append(&title_col);

    let open = gtk::Button::with_label("Open");
    open.set_valign(gtk::Align::Center);
    open.add_css_class("suggested-action");
    let parent_w: gtk::Widget = parent.clone().upcast();
    let mission_o = mission.clone();
    let on_ask_o = on_ask.clone();
    open.connect_clicked(move |_| {
        show_mission_detail_dialog(&parent_w, mission_o.clone(), on_ask_o.clone());
    });
    head.append(&open);

    let discuss = discuss_icon_button("Discuss this Mission");
    let on_ask_d = on_ask.clone();
    let mission_d = mission.clone();
    discuss.connect_clicked(move |_| {
        let topic = mission_discuss_topic(&mission_d, None);
        let name = mission_display_title(&mission_d);
        on_ask_d(
            topic,
            format!("Let's discuss my Mission: {name}\n\nWhat should we focus on next?"),
        );
    });
    head.append(&discuss);

    if allow_make_primary {
        let make = gtk::Button::with_label("Make Primary");
        make.set_valign(gtk::Align::Center);
        make.add_css_class("flat");
        let mid = mission
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_owned();
        let on_refresh_m = on_refresh.clone();
        make.connect_clicked(move |_| {
            if mid.is_empty() {
                return;
            }
            let _ = run_bridge_action(
                "life_stack_set_primary",
                serde_json::json!({ "mission_id": mid }),
            );
            on_refresh_m();
        });
        head.append(&make);
    }

    row.append(&head);
    row
}

/// Build the Missions tab (Mission Stack + pulse).
pub fn build(hooks: HomeHooks) -> (gtk::Box, HomeHandle) {
    let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
    container.set_vexpand(true);
    container.set_hexpand(true);
    container.add_css_class("centurion-home");
    container.add_css_class("centurion-missions");

    let header = gtk::Box::new(gtk::Orientation::Vertical, 4);
    header.set_margin_top(16);
    header.set_margin_start(20);
    header.set_margin_end(20);
    header.set_margin_bottom(8);
    header.append(
        &gtk::Label::builder()
            .label("Missions")
            .css_classes(["title-1"])
            .xalign(0.0)
            .build(),
    );
    header.append(
        &gtk::Label::builder()
            .label("What you’re building toward, and what needs you.")
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );
    container.append(&header);

    let attention_banner = gtk::Box::new(gtk::Orientation::Vertical, 4);
    attention_banner.add_css_class("centurion-attention-banner");
    attention_banner.set_margin_start(20);
    attention_banner.set_margin_end(20);
    attention_banner.set_margin_bottom(8);
    attention_banner.set_visible(false);
    container.append(&attention_banner);

    let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
    body.set_hexpand(true);

    // Mission Stack first (dominant), then pulse (commitments / orbs / pills / feed).
    // Fleet / Extensions / Scheduled & board / Connect live under Settings.
    let chrome = gtk::Box::new(gtk::Orientation::Vertical, 10);
    chrome.set_margin_start(20);
    chrome.set_margin_end(20);
    chrome.set_margin_top(4);
    chrome.set_margin_bottom(8);

    let mission_stack_box = gtk::Box::new(gtk::Orientation::Vertical, 6);
    mission_stack_box.add_css_class("centurion-mission-stack");
    chrome.append(&mission_stack_box);

    let commitments = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    commitments.add_css_class("centurion-home-commitments");
    chrome.append(&commitments);

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

    let error_label = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .css_classes(["error"])
        .visible(false)
        .build();
    chrome.append(&error_label);

    let pill_bar = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    pill_bar.add_css_class("centurion-home-pills");
    pill_bar.set_margin_top(4);
    pill_bar.set_margin_bottom(8);
    let pill_scroll = gtk::ScrolledWindow::builder()
        .child(&pill_bar)
        .hscrollbar_policy(gtk::PolicyType::Automatic)
        .vscrollbar_policy(gtk::PolicyType::Never)
        .hexpand(true)
        .build();

    let category_body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    category_body.set_margin_start(20);
    category_body.set_margin_end(20);
    category_body.set_margin_bottom(28);

    body.append(&chrome);
    body.append(&pill_scroll);
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
    let applied_decision_first = Rc::new(Cell::new(false));
    let attention = Rc::new(Cell::new(0u32));
    // Toggle + title label + numeric capsule badge (iPhone CenturionPillNav parity).
    let pill_buttons: Rc<RefCell<Vec<(PulseCategory, gtk::ToggleButton, gtk::Label, gtk::Label)>>> =
        Rc::new(RefCell::new(Vec::new()));
    let render_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));

    let paint: Rc<dyn Fn()> = Rc::new({
        let feed = feed.clone();
        let selected = selected.clone();
        let constellation = constellation.clone();
        let mission_stack_box = mission_stack_box.clone();
        let commitments = commitments.clone();
        let error_label = error_label.clone();
        let category_body = category_body.clone();
        let hooks = hooks.clone();
        let container = container.clone();
        let render_slot = render_slot.clone();
        let pill_buttons = pill_buttons.clone();
        let attention = attention.clone();
        let attention_banner = attention_banner.clone();
        move || {
            let data = feed.borrow().clone();
            clear_box(&constellation);
            if data.swarms.is_empty() {
                constellation.append(&empty_label(
                    "No active collaborations yet. When your Sovereign works with others, they’ll appear here.",
                ));
            } else {
                for orb in &data.swarms {
                    let chip = gtk::Button::new();
                    chip.add_css_class("flat");
                    chip.add_css_class("centurion-home-orb");
                    let chip_row = gtk::Box::new(gtk::Orientation::Horizontal, 4);
                    chip_row.append(&gtk::Image::from_icon_name("mail-message-new-symbolic"));
                    chip_row.append(&gtk::Label::new(Some(&format!("{} · {}", orb.name, orb.pulse))));
                    chip.set_child(Some(&chip_row));
                    chip.set_tooltip_text(Some("Open collaboration"));
                    let parent = container.clone();
                    let on_ask = hooks.on_ask_about.clone();
                    let orb_clone = orb.clone();
                    // Clone before the click Fn so the paint Fn can bind many chips.
                    let refresh = {
                        let render_slot = render_slot.clone();
                        Rc::new(move || {
                            if let Some(f) = render_slot.borrow().as_ref() {
                                f();
                            }
                        }) as Rc<dyn Fn()>
                    };
                    chip.connect_clicked(move |_| {
                        show_collab_detail_dialog(
                            &parent,
                            &orb_clone,
                            on_ask.clone(),
                            refresh.clone(),
                        );
                    });
                    constellation.append(&chip);
                }
            }

            // Last-seen "new" badges (iPhone pulse_note_* parity).
            // Mark selected first so Home tab total drops that pill (Live presence stays).
            let selected_cat = selected.get();
            mark_category_seen(&data, selected_cat);
            let seen = load_pulse_seen();
            for (cat, _btn, _title, badge) in pill_buttons.borrow().iter() {
                let n = if *cat == selected_cat {
                    0
                } else {
                    new_count_for_category(&data, *cat, &seen)
                };
                if n > 0 {
                    badge.set_label(&n.to_string());
                    badge.set_visible(true);
                } else {
                    badge.set_visible(false);
                }
            }
            let total = total_attention_count(&data, &seen);
            attention.set(total);
            (hooks.on_attention_changed)(total);
            rebuild_attention_banner(&attention_banner, &attention_breakdown(&data, &seen));

            let refresh_stack = {
                let render_slot = render_slot.clone();
                Rc::new(move || {
                    if let Some(f) = render_slot.borrow().as_ref() {
                        f();
                    }
                }) as Rc<dyn Fn()>
            };
            rebuild_mission_stack_section(
                &mission_stack_box,
                &container,
                hooks.on_ask_about.clone(),
                refresh_stack,
            );

            clear_box(&commitments);
            let mission_statement_for_chips = data.mission.statement.clone();
            for target in &data.mission.targets {
                let chip = gtk::Button::new();
                chip.add_css_class("flat");
                chip.add_css_class("centurion-home-commitment");
                let chip_row = gtk::Box::new(gtk::Orientation::Horizontal, 4);
                chip_row.append(&gtk::Image::from_icon_name("mail-message-new-symbolic"));
                chip_row.append(&gtk::Label::new(Some(&target.title)));
                chip.set_child(Some(&chip_row));
                chip.set_tooltip_text(Some("Ask about this commitment"));
                let on_ask = hooks.on_ask_about.clone();
                let commitment = target.clone();
                let mission_statement = mission_statement_for_chips.clone();
                chip.connect_clicked(move |_| {
                    on_ask(
                        DiscussTopic::Commitment {
                            id: commitment.id.clone(),
                            title: commitment.title.clone(),
                            description: commitment.description.clone(),
                            active: true,
                            mission_statement: mission_statement.clone(),
                        },
                        format!(
                            "Let's talk about my commitment: {}

{}",
                            commitment.title, commitment.description
                        ),
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
                        let ask = discuss_icon_button("Ask about this");
                        ask.add_css_class("suggested-action");
                        let on_ask = hooks.on_ask_about.clone();
                        let live_id = live.id.clone();
                        let summary = live.summary.clone();
                        let detail = live.detail.clone();
                        ask.connect_clicked(move |_| {
                            on_ask(
                                DiscussTopic::Collab {
                                    id: live_id.clone(),
                                    name: summary.clone(),
                                    pulse: "active".to_owned(),
                                    objective: detail.clone(),
                                },
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
                                    DiscussTopic::Generic {
                                        title: "Propose a plan".to_owned(),
                                        kind: "plan".to_owned(),
                                        detail: String::new(),
                                    },
                                    "Propose a plan for what we should work on next. Outline the goal, steps, and what you need from me before acting."
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
                                on_ask2(
                                    DiscussTopic::Mission {
                                        statement: mission_text.clone(),
                                        id: None,
                                        title: None,
                                        target_id: None,
                                        target_title: None,
                                        target_type: None,
                                        target_description: None,
                                        target_status: None,
                                        sequence_number: None,
                                    },
                                    prompt,
                                );
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
                                    DiscussTopic::Generic {
                                        title: "Propose a plan".to_owned(),
                                        kind: "plan".to_owned(),
                                        detail: String::new(),
                                    },
                                    "Propose a plan for what we should work on next. Outline the goal, steps, and what you need from me before acting."
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
                                if !plan.related_mission.is_empty() {
                                    card.append(
                                        &gtk::Label::builder()
                                            .label(&format!(
                                                "From mission · {}",
                                                plan.related_mission
                                            ))
                                            .wrap(true)
                                            .xalign(0.0)
                                            .css_classes(["caption", "dim-label"])
                                            .build(),
                                    );
                                }
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
                                let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
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
                                let discuss = discuss_icon_button("Discuss this plan");
                                let on_ask_d = hooks.on_ask_about.clone();
                                let plan_d = plan.clone();
                                discuss.connect_clicked(move |_| {
                                    on_ask_d(
                                        plan_topic_from_item(&plan_d),
                                        format!(
                                            "Let's discuss this plan.\n\nTitle: {}\n\n{}\n\nGoal: {}\n\nWhat should change or stay?",
                                            plan_d.title,
                                            if plan_d.summary.is_empty() {
                                                "(no summary yet)"
                                            } else {
                                                plan_d.summary.as_str()
                                            },
                                            plan_d.goal
                                        ),
                                    );
                                });
                                actions.append(&open);
                                actions.append(&discuss);
                                card.append(&actions);
                                category_body.append(&card);
                            }
                        }
                    }
                    if !data.templates.is_empty() {
                        category_body.append(&section_heading("Templates"));
                        for tmpl in &data.templates {
                            let card = card_box();
                            card.append(
                                &gtk::Label::builder()
                                    .label(&tmpl.title)
                                    .wrap(true)
                                    .xalign(0.0)
                                    .css_classes(["heading"])
                                    .build(),
                            );
                            if !tmpl.summary.is_empty() {
                                card.append(
                                    &gtk::Label::builder()
                                        .label(&tmpl.summary)
                                        .wrap(true)
                                        .xalign(0.0)
                                        .css_classes(["dim-label"])
                                        .build(),
                                );
                            }
                            let use_btn = gtk::Button::with_label("Use template");
                            use_btn.add_css_class("flat");
                            let parent = container.clone().upcast::<gtk::Widget>();
                            let refresh = refresh_all.clone();
                            let template_id = tmpl.id.clone();
                            use_btn.connect_clicked(move |_| {
                                let parent = parent.clone();
                                let refresh = refresh.clone();
                                let template_id = template_id.clone();
                                run_async_result(parent, refresh, move || {
                                    instantiate_plan_template(&template_id)
                                });
                            });
                            card.append(&use_btn);
                            category_body.append(&card);
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
                            let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                            let ask = discuss_icon_button("Ask about this");
                            let on_ask = hooks.on_ask_about.clone();
                            let summary = win.summary.clone();
                            let detail = win.detail.clone();
                            ask.connect_clicked(move |_| {
                                on_ask(
                                    DiscussTopic::Generic {
                                        title: summary.clone(),
                                        kind: "finished work".to_owned(),
                                        detail: detail.clone(),
                                    },
                                    format!(
                                        "Tell me more about this finished work:\n\n{summary}\n\n{detail}"
                                    ),
                                );
                            });
                            actions.append(&ask);
                            card.append(&actions);
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
                            let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                            let open = gtk::Button::with_label("Open");
                            open.add_css_class("flat");
                            let parent = container.clone();
                            let doc_c = doc.clone();
                            let on_ask = hooks.on_ask_about.clone();
                            let refresh = refresh_all.clone();
                            let plans_snapshot = data.plans.clone();
                            open.connect_clicked(move |_| {
                                show_document_dialog(
                                    &parent,
                                    &doc_c,
                                    on_ask.clone(),
                                    refresh.clone(),
                                    &plans_snapshot,
                                );
                            });
                            let discuss = discuss_icon_button("Discuss this document");
                            let on_ask_d = hooks.on_ask_about.clone();
                            let title = doc.title.clone();
                            let summary = doc.summary.clone();
                            let body = doc.body.clone();
                            let plan_id = doc.plan_id.clone();
                            discuss.connect_clicked(move |_| {
                                on_ask_d(
                                    DiscussTopic::Document {
                                        id: None,
                                        mission_id: None,
                                        doc_type: None,
                                        title: title.clone(),
                                        summary: summary.clone(),
                                        plan_id: plan_id.clone(),
                                        body_excerpt: body.clone(),
                                    },
                                    format!(
                                        "Let's discuss this document.\n\n{title}\n\n{summary}\n\nWhat should we do with it?"
                                    ),
                                );
                            });
                            actions.append(&open);
                            actions.append(&discuss);
                            card.append(&actions);
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
                            let comment = gtk::Button::with_label(
                                if decision.plan_id.is_some() {
                                    "Comment"
                                } else {
                                    "Note"
                                },
                            );
                            comment.add_css_class("flat");

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
                            let plan_id_adj = decision.plan_id.clone();
                            let refresh_adj = refresh_all.clone();
                            let parent_adj = container.clone().upcast::<gtk::Widget>();
                            let plans_for_adj = data.plans.clone();
                            adjust.connect_clicked(move |_| {
                                let kickoff = format!(
                                    "I'd like to adjust this decision.\n\n{title}\n\n{context}\n\nWhat should change?"
                                );
                                if let Some(pid) = plan_id_adj.clone() {
                                    let plan_from_feed = plans_for_adj
                                        .iter()
                                        .find(|p| p.id == pid)
                                        .cloned();
                                    let refresh_adj = refresh_adj.clone();
                                    let parent_adj = parent_adj.clone();
                                    let on_ask = on_ask.clone();
                                    let title = title.clone();
                                    let context = context.clone();
                                    let kickoff_ok = kickoff.clone();
                                    // Clone before on_ok move — Fedora rustc E0382 if pid is
                                    // captured by the Fn and then cloned for decide_plan.
                                    let pid_work = pid.clone();
                                    let on_ok = Rc::new({
                                        let pid = pid.clone();
                                        move || {
                                            let topic = if let Some(ref plan) = plan_from_feed {
                                                plan_topic_from_item(plan)
                                            } else if let Some(plan) = fetch_plan_item(&pid) {
                                                plan_topic_from_item(&plan)
                                            } else {
                                                DiscussTopic::Plan {
                                                    id: pid.clone(),
                                                    title: title.clone(),
                                                    status: "adjusted".to_owned(),
                                                    goal: String::new(),
                                                    summary: context.clone(),
                                                    steps: Vec::new(),
                                                    risks: Vec::new(),
                                                }
                                            };
                                            on_ask(topic, kickoff_ok.clone());
                                        }
                                    }) as Rc<dyn Fn()>;
                                    run_async_then(
                                        parent_adj,
                                        refresh_adj,
                                        move || decide_plan(&pid_work, "request_changes"),
                                        on_ok,
                                    );
                                } else {
                                    on_ask(
                                        DiscussTopic::Generic {
                                            title: title.clone(),
                                            kind: "decision".to_owned(),
                                            detail: context.clone(),
                                        },
                                        kickoff,
                                    );
                                }
                            });

                            let plan_id = decision.plan_id.clone();
                            let signal_id = decision.signal_id.clone();
                            let refresh_h = refresh_all.clone();
                            let parent_h = container.clone().upcast::<gtk::Widget>();
                            hold.connect_clicked(move |_| {
                                let plan_id = plan_id.clone();
                                let signal_id = signal_id.clone();
                                let refresh_h = refresh_h.clone();
                                let parent_h = parent_h.clone();
                                run_async_result(parent_h, refresh_h, move || {
                                    if let Some(pid) = plan_id.as_ref() {
                                        decide_plan(pid, "hold")?;
                                    }
                                    if let Some(sid) = signal_id.as_ref() {
                                        resolve_signal(sid, "Hold")?;
                                    }
                                    Ok(())
                                });
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
                            let discuss = discuss_icon_button("Discuss this decision");
                            let on_ask_d = hooks.on_ask_about.clone();
                            let title_d = decision.title.clone();
                            let context_d = decision.context.clone();
                            let plan_for_d = decision.plan_id.clone().and_then(|pid| {
                                data.plans.iter().find(|p| p.id == pid).cloned()
                            });
                            discuss.connect_clicked(move |_| {
                                if let Some(ref plan) = plan_for_d {
                                    on_ask_d(
                                        plan_topic_from_item(plan),
                                        format!(
                                            "Let's discuss this decision.\n\n{title_d}\n\n{context_d}\n\nWhat should we do?"
                                        ),
                                    );
                                } else {
                                    on_ask_d(
                                        DiscussTopic::Generic {
                                            title: title_d.clone(),
                                            kind: "decision".to_owned(),
                                            detail: context_d.clone(),
                                        },
                                        format!(
                                            "Let's discuss this decision.\n\n{title_d}\n\n{context_d}\n\nWhat should we do?"
                                        ),
                                    );
                                }
                            });
                            actions.append(&discuss);
                            if let Some(pid) = decision.plan_id.clone() {
                                let parent_c = container.clone();
                                let refresh_c = refresh_all.clone();
                                comment.connect_clicked(move |_| {
                                    prompt_plan_comment(&parent_c, pid.clone(), refresh_c.clone());
                                });
                                actions.append(&comment);
                            } else if let Some(sid) = decision.signal_id.clone() {
                                let parent_c = container.clone();
                                let refresh_c = refresh_all.clone();
                                comment.connect_clicked(move |_| {
                                    prompt_signal_note(
                                        &parent_c,
                                        sid.clone(),
                                        "Add note",
                                        "Note for this decision",
                                        refresh_c.clone(),
                                    );
                                });
                                actions.append(&comment);
                            }
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
                            let ask = discuss_icon_button("Discuss this update");
                            let on_ask = hooks.on_ask_about.clone();
                            let text = thought.text.clone();
                            let kind = thought.kind.clone();
                            ask.connect_clicked(move |_| {
                                on_ask(
                                    DiscussTopic::Generic {
                                        title: kind.clone(),
                                        kind: "update".to_owned(),
                                        detail: text.clone(),
                                    },
                                    format!("Let's discuss this update:\n\n{text}"),
                                );
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
        let selected = selected.clone();
        let applied_decision_first = applied_decision_first.clone();
        let pill_buttons = pill_buttons.clone();
        move || {
            let (tx, rx) = mpsc::channel::<HomeFeed>();
            thread::spawn(move || {
                let _ = tx.send(load_home_feed());
            });
            let feed = feed.clone();
            let paint = paint.clone();
            let selected = selected.clone();
            let applied_decision_first = applied_decision_first.clone();
            let pill_buttons = pill_buttons.clone();
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(next) => {
                    *feed.borrow_mut() = next;
                    if !applied_decision_first.get() && load_decision_first_pref() {
                        applied_decision_first.set(true);
                        let data = feed.borrow();
                        let initial = if !data.decisions.is_empty() {
                            PulseCategory::Decisions
                        } else if data.plans.iter().any(|p| {
                            matches!(
                                p.status.to_lowercase().as_str(),
                                "pending_review" | "held" | "adjusted" | "proposed"
                            )
                        }) {
                            PulseCategory::Plans
                        } else {
                            PulseCategory::Live
                        };
                        drop(data);
                        selected.set(initial);
                        for (cat, btn, _title, _badge) in pill_buttons.borrow().iter() {
                            btn.set_active(*cat == initial);
                        }
                    } else if !applied_decision_first.get() {
                        applied_decision_first.set(true);
                    }
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
        let btn = gtk::ToggleButton::new();
        btn.add_css_class("centurion-home-pill");
        btn.set_active(cat == PulseCategory::Live);
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let title = gtk::Label::builder()
            .label(cat.title())
            .css_classes(["centurion-home-pill-title"])
            .build();
        let badge = gtk::Label::builder()
            .label("")
            .css_classes(["centurion-home-pill-badge"])
            .visible(false)
            .build();
        row.append(&title);
        row.append(&badge);
        btn.set_child(Some(&row));
        let selected = selected.clone();
        let pill_buttons_for_toggle = pill_buttons.clone();
        let paint = paint.clone();
        let feed_for_seen = feed.clone();
        btn.connect_toggled(move |b| {
            if !b.is_active() {
                return;
            }
            selected.set(cat);
            mark_category_seen(&feed_for_seen.borrow(), cat);
            for (other_cat, other, _title, _badge) in pill_buttons_for_toggle.borrow().iter() {
                if *other_cat != cat {
                    other.set_active(false);
                }
            }
            paint();
        });
        pill_bar.append(&btn);
        pill_buttons
            .borrow_mut()
            .push((cat, btn, title, badge));
    }

    refresh_feed();
    glib::timeout_add_seconds_local(8, {
        let refresh_feed = refresh_feed.clone();
        move || {
            refresh_feed();
            glib::ControlFlow::Continue
        }
    });

    let handle = HomeHandle::new(
        refresh_feed.clone(),
        attention.clone(),
        Rc::new(|_: bool| {}),
    );
    (container, handle)
}
