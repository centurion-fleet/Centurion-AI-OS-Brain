//! Phone-like bubble chat for the Linux Brain Chat tab.
//!
//! Drives the local Centurion agent via `centurion_cli.remote_bridge`
//! (same path as iPhone Crypto Chat), with mid-turn tool approvals.

use adw::prelude::*;
use gtk4 as gtk;
use gio;
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

#[derive(Clone, Debug)]
struct ActivityEvent {
    kind: String,
    line: String,
    text: String,
    tool: String,
}

enum WorkerEvent {
    Approval(ApprovalRequest),
    Activity(ActivityEvent),
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

/// Structured topic for Home → Chat discuss so Centurion knows *what* is in play.
#[derive(Clone, Debug)]
pub enum DiscussTopic {
    Plan {
        id: String,
        title: String,
        status: String,
        goal: String,
        summary: String,
        steps: Vec<String>,
        risks: Vec<String>,
    },
    Collab {
        id: String,
        name: String,
        pulse: String,
        objective: String,
    },
    Document {
        title: String,
        summary: String,
        plan_id: Option<String>,
        body_excerpt: String,
    },
    Mission {
        statement: String,
    },
    Commitment {
        id: String,
        title: String,
        description: String,
        active: bool,
        mission_statement: String,
    },
    Horizon {
        layer: String,
        detail: String,
    },
    Generic {
        title: String,
        kind: String,
        detail: String,
    },
}

impl DiscussTopic {
    pub fn banner_label(&self) -> String {
        match self {
            Self::Plan { title, .. } => format!("Discussing plan · {title}"),
            Self::Collab { name, .. } => format!("Discussing collaboration · {name}"),
            Self::Document { title, .. } => format!("Discussing document · {title}"),
            Self::Mission { .. } => "Discussing Life Mission".to_owned(),
            Self::Commitment { title, .. } => format!("Discussing commitment · {title}"),
            Self::Horizon { layer, .. } => format!("Discussing Memory Horizon · {layer}"),
            Self::Generic { title, kind, .. } => {
                if kind.is_empty() {
                    format!("Discussing · {title}")
                } else {
                    format!("Discussing {kind} · {title}")
                }
            }
        }
    }

    pub fn from_title_detail(title: &str, detail: &str) -> Self {
        Self::Generic {
            title: title.to_owned(),
            kind: "topic".to_owned(),
            detail: detail.to_owned(),
        }
    }

    pub fn horizon(layer: &str, detail: &str) -> Self {
        Self::Horizon {
            layer: layer.to_owned(),
            detail: detail.to_owned(),
        }
    }
}

/// Handle for other tabs (Home) to seed the Chat composer with topic context.
#[derive(Clone)]
pub struct ChatHandle {
    input: gtk::Entry,
    active_discuss: Rc<RefCell<Option<DiscussTopic>>>,
    context_banner: gtk::Label,
    context_bar: gtk::Box,
    on_fix_thinking: Rc<RefCell<Option<Rc<dyn Fn()>>>>,
}

impl ChatHandle {
    fn refresh_banner(&self) {
        match self.active_discuss.borrow().as_ref() {
            Some(topic) => {
                self.context_banner.set_label(&topic.banner_label());
                self.context_bar.set_visible(true);
            }
            None => {
                self.context_banner.set_label("");
                self.context_bar.set_visible(false);
            }
        }
    }

    /// Prefill composer and remember structured topic for outbound framing.
    pub fn seed_discuss_topic(&self, topic: DiscussTopic, kickoff: &str) {
        *self.active_discuss.borrow_mut() = Some(topic);
        self.refresh_banner();
        let body = if kickoff.trim().is_empty() {
            String::new()
        } else if kickoff.ends_with('\n') {
            kickoff.to_owned()
        } else {
            format!("{kickoff}\n\n")
        };
        self.input.set_text(&body);
        self.input.grab_focus();
        let len = body.chars().count() as i32;
        self.input.set_position(len);
    }

    /// Back-compat: title + detail prose only (Horizon and similar).
    pub fn seed_discuss(&self, title: &str, detail: &str) {
        let topic = DiscussTopic::from_title_detail(title, detail);
        let kickoff = if detail.trim().is_empty() {
            format!("About “{title}”:\n\n")
        } else {
            detail.to_owned()
        };
        self.seed_discuss_topic(topic, &kickoff);
    }

    pub fn clear_discuss(&self) {
        *self.active_discuss.borrow_mut() = None;
        self.refresh_banner();
    }

    /// Wire Settings Fix Thinking wizard (set after the main window exists).
    pub fn set_on_fix_thinking(&self, handler: Rc<dyn Fn()>) {
        *self.on_fix_thinking.borrow_mut() = Some(handler);
    }
}

fn looks_like_thinking_error(message: &str) -> bool {
    let lower = message.to_lowercase();
    lower.contains("thinking")
        || lower.contains("provider")
        || lower.contains("api key")
        || lower.contains("access code")
        || lower.contains("auth")
        || lower.contains("unauthorized")
        || lower.contains("401")
        || lower.contains("403")
        || lower.contains("model")
        || lower.contains("rate limit")
        || lower.contains("quota")
        || lower.contains("connection dropped")
        || lower.contains("could not reach")
        || lower.contains("openai")
        || lower.contains("anthropic")
        || lower.contains("openrouter")
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ChatIntent {
    Talk,
    ProposeFirst,
}

#[derive(Clone, Debug)]
struct PendingAttachment {
    path: PathBuf,
    filename: String,
}


fn rebuild_attachment_chips(
    attachment_row: &gtk::Box,
    attachments: &Rc<RefCell<Vec<PendingAttachment>>>,
) {
    while let Some(child) = attachment_row.first_child() {
        attachment_row.remove(&child);
    }
    let items = attachments.borrow().clone();
    attachment_row.set_visible(!items.is_empty());
    for (index, item) in items.iter().enumerate() {
        let chip = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        chip.add_css_class("centurion-chat-attach-chip");
        chip.append(
            &gtk::Label::builder()
                .label(&format!("📎 {}", item.filename))
                .build(),
        );
        let remove = gtk::Button::from_icon_name("window-close-symbolic");
        remove.add_css_class("flat");
        remove.set_tooltip_text(Some("Remove attachment"));
        let attachments = attachments.clone();
        let row_for_remove = attachment_row.clone();
        remove.connect_clicked(move |_| {
            {
                let mut list = attachments.borrow_mut();
                if index < list.len() {
                    list.remove(index);
                }
            }
            rebuild_attachment_chips(&row_for_remove, &attachments);
        });
        chip.append(&remove);
        attachment_row.append(&chip);
    }
}

const PLAN_ARTIFACT_FENCE: &str = "plan-artifact";

fn frame_propose_first(user_text: &str) -> String {
    format!(
        "[Sovereign AI Brain — Propose first]\n\
         The user wants a plan before any consequential action.\n\n\
         For this turn only:\n\
         - Draft a concrete plan. Do not implement, send, edit project files, run mutating commands, or take external actions.\n\
         - You may inspect read-only context if needed.\n\
         - Reply briefly in plain language, then end with a fenced JSON block exactly like this:\n\n\
         ```{PLAN_ARTIFACT_FENCE}\n\
         {{\"title\":\"Short plan title\",\"goal\":\"What success looks like\",\"steps\":[\"Step 1\",\"Step 2\"],\"risks\":[\"Risk if any\"],\"open_questions\":[\"Question if any\"],\"summary\":\"One or two sentence summary for Home\"}}\n\
         ```\n\n\
         Omit empty arrays. Keep steps actionable and short.\n\n\
         User message:\n\
         {user_text}"
    )
}

const PLAN_UPDATE_FENCE: &str = "plan-update";

fn frame_plan_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Plan {
        id,
        title,
        status,
        goal,
        summary,
        steps,
        risks,
    } = topic
    else {
        return user_text.to_owned();
    };
    let steps_block = if steps.is_empty() {
        "(none yet)".to_owned()
    } else {
        steps
            .iter()
            .enumerate()
            .map(|(i, s)| format!("{}. {s}", i + 1))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let risks_block = if risks.is_empty() {
        "(none listed)".to_owned()
    } else {
        risks
            .iter()
            .map(|r| format!("- {r}"))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let goal = if goal.is_empty() { "(not set)" } else { goal.as_str() };
    let summary = if summary.is_empty() { "(none)" } else { summary.as_str() };
    let status = if status.is_empty() { "pending_review" } else { status.as_str() };
    format!(
        "[Sovereign AI Brain — Plan discuss]\n\
The user is continuing Chat about this reviewable Plan (not their life Mission).\n\n\
Plan ID: {id}\n\
Title: {title}\n\
Status: {status}\n\
Goal: {goal}\n\
Steps:\n\
{steps_block}\n\
Risks:\n\
{risks_block}\n\
Summary: {summary}\n\n\
Help them refine, proceed guidance, or revise the plan. Do not take irreversible \
external actions unless they clearly ask you to execute after Proceed.\n\n\
If you and the user agree on plan edits, end your reply with a fenced JSON block \
exactly like this (omit fields you are not changing):\n\n\
```{PLAN_UPDATE_FENCE}\n\
{{\"plan_id\":\"{id}\",\"title\":\"Updated title\",\"goal\":\"Updated goal\",\"steps\":[\"Step 1\"],\"risks\":[],\"open_questions\":[],\"summary\":\"Short summary\",\"status\":\"pending_review\"}}\n\
```\n\n\
Allowed status values: pending_review, proceeded, held, adjusted, completed, rejected.\n\n\
User message:\n\
{user_text}"
    )
}

fn frame_collab_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Collab {
        id,
        name,
        pulse,
        objective,
    } = topic
    else {
        return user_text.to_owned();
    };
    let id_line = if id.is_empty() {
        String::new()
    } else {
        format!("Collaboration ID: {id}\n")
    };
    format!(
        "[Sovereign AI Brain — Collaboration discuss]\n\
The user is talking about an active collaboration / swarm on this Brain.\n\n\
{id_line}Name: {name}\n\
Pulse: {pulse}\n\
Objective: {objective}\n\n\
Stay grounded in this collaboration. Ask before irreversible external actions.\n\n\
User message:\n\
{user_text}"
    )
}

fn frame_document_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Document {
        title,
        summary,
        plan_id,
        body_excerpt,
    } = topic
    else {
        return user_text.to_owned();
    };
    let plan_line = plan_id
        .as_ref()
        .filter(|p| !p.is_empty())
        .map(|p| format!("Linked plan ID: {p}\n"))
        .unwrap_or_default();
    let excerpt = if body_excerpt.trim().is_empty() {
        summary.clone()
    } else {
        body_excerpt.chars().take(1200).collect()
    };
    format!(
        "[Sovereign AI Brain — Document discuss]\n\
The user is discussing a document / outcome on Home.\n\n\
Title: {title}\n\
{plan_line}Summary: {summary}\n\n\
Excerpt:\n\
{excerpt}\n\n\
User message:\n\
{user_text}"
    )
}

fn frame_mission_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Mission { statement } = topic else {
        return user_text.to_owned();
    };
    let statement = if statement.trim().is_empty() {
        "(not set yet — help them shape one)"
    } else {
        statement.as_str()
    };
    // New discuss turn only — inject Brain life context into the user message
    // (never mutate the system prompt / prompt cache).
    let life_block = run_bridge_action(
        "life_context_inject",
        serde_json::json!({ "message": user_text }),
    )
    .and_then(|r| {
        if r.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            r.get("formatted_for_ai")
                .and_then(|v| v.as_str())
                .map(|s| s.to_owned())
        } else {
            None
        }
    })
    .filter(|s| !s.trim().is_empty())
    .map(|s| format!("Mission context:\n{s}\n\n"))
    .unwrap_or_default();
    format!(
        "[Sovereign AI Brain — Life Mission discuss]\n\
The user is discussing their Life Mission (direction), not a single reviewable Plan.\n\n\
Current Mission:\n\
{statement}\n\n\
{life_block}Help them clarify direction and next focus. Prefer proposing Plans over silent execution.\n\
Use Must Do / Should Do / Nice to Do vocabulary for targets.\n\n\
User message:\n\
{user_text}"
    )
}

fn frame_generic_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Generic { title, kind, detail } = topic else {
        return user_text.to_owned();
    };
    let detail_block = if detail.trim().is_empty() {
        String::new()
    } else {
        format!("Context:\n{detail}\n\n")
    };
    format!(
        "[Sovereign AI Brain — {kind} discuss]\n\
Topic: {title}\n\n\
{detail_block}Keep this topic in context for the reply.\n\n\
User message:\n\
{user_text}"
    )
}

fn frame_horizon_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Horizon { layer, detail } = topic else {
        return user_text.to_owned();
    };
    format!(
        "[Sovereign AI Brain — Memory Horizon discuss]\n\
Layer: {layer}\n\n\
{detail}\n\n\
Help the user understand and manage this memory layer. Do not invent storage they do not have.\n\n\
User message:\n\
{user_text}"
    )
}

const COMMITMENT_UPDATE_FENCE: &str = "mission-update";

fn frame_commitment_discuss(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Commitment {
        id,
        title,
        description,
        active,
        mission_statement,
    } = topic
    else {
        return user_text.to_owned();
    };
    let mission_line = if mission_statement.trim().is_empty() {
        "(not set yet)"
    } else {
        mission_statement.as_str()
    };
    let desc = if description.trim().is_empty() {
        "(none)"
    } else {
        description.as_str()
    };
    format!(
        "[Sovereign AI Brain — Living Commitment chat]\n\
Life mission: {mission_line}\n\
Commitment: {title}\n\
Description: {desc}\n\
Commitment ID: {id}\n\
Active on Home: {active}\n\n\
The user is discussing or revising this living commitment. You may suggest renames, \
clearer descriptions, or deactivating it. If you apply a change the user agrees to, \
end your reply with a fenced block exactly like this (omit fields you are not changing):\n\n\
```{COMMITMENT_UPDATE_FENCE}\n\
{{\"commitment_id\":\"{id}\",\"title\":\"New title\",\"description\":\"New description\",\"active\":true}}\n\
```\n\n\
User message:\n\
{user_text}"
    )
}

fn extract_commitment_update_block(response: &str) -> Option<String> {
    let open = format!("```{COMMITMENT_UPDATE_FENCE}");
    let start = response.find(&open)?;
    let after = &response[start + open.len()..];
    let close = after.find("```")?;
    Some(after[..close].trim().to_owned())
}

fn strip_commitment_update(response: &str) -> String {
    let open = format!("```{COMMITMENT_UPDATE_FENCE}");
    let Some(start) = response.find(&open) else {
        return response.trim().to_owned();
    };
    let mut result = response[..start].to_owned();
    let after_open = &response[start + open.len()..];
    if let Some(close) = after_open.find("```") {
        result.push_str(&after_open[close + 3..]);
    }
    result.trim().to_owned()
}

fn apply_commitment_update_from_response(response: &str, fallback_id: &str) -> Option<()> {
    let block = extract_commitment_update_block(response)?;
    let value: Value = serde_json::from_str(&block).ok()?;
    let obj = value.as_object()?;
    let mut cid = obj
        .get("commitment_id")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_owned();
    if cid.is_empty() {
        cid = fallback_id.to_owned();
    }
    if cid.is_empty() {
        return None;
    }
    let mission_resp = run_bridge_action("mission_get", serde_json::json!({}))?;
    if mission_resp.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return None;
    }
    let mut mission = mission_resp.get("mission")?.clone();
    let targets = mission
        .get_mut("targets")
        .and_then(|v| v.as_array_mut())?;
    let mut found = false;
    let mut remove_idx = None;
    for (i, target) in targets.iter_mut().enumerate() {
        let tid = target
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_owned();
        let title = target
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_owned();
        if tid != cid && title != cid {
            continue;
        }
        found = true;
        if let Some(t) = obj.get("title").and_then(|v| v.as_str()) {
            if !t.trim().is_empty() {
                target
                    .as_object_mut()?
                    .insert("title".to_owned(), Value::String(t.trim().to_owned()));
            }
        }
        if let Some(d) = obj.get("description").and_then(|v| v.as_str()) {
            target
                .as_object_mut()?
                .insert("description".to_owned(), Value::String(d.trim().to_owned()));
        }
        if obj.get("active").and_then(|v| v.as_bool()) == Some(false) {
            remove_idx = Some(i);
        }
        break;
    }
    if !found {
        return None;
    }
    if let Some(i) = remove_idx {
        targets.remove(i);
    }
    let put = run_bridge_action(
        "mission_put",
        serde_json::json!({ "mission": mission }),
    )?;
    if put.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Some(())
    } else {
        None
    }
}

fn frame_discuss_outbound(user_text: &str, topic: &DiscussTopic) -> String {
    match topic {
        DiscussTopic::Plan { .. } => frame_plan_discuss(user_text, topic),
        DiscussTopic::Collab { .. } => frame_collab_discuss(user_text, topic),
        DiscussTopic::Document { .. } => frame_document_discuss(user_text, topic),
        DiscussTopic::Mission { .. } => frame_mission_discuss(user_text, topic),
        DiscussTopic::Commitment { .. } => frame_commitment_discuss(user_text, topic),
        DiscussTopic::Horizon { .. } => frame_horizon_discuss(user_text, topic),
        DiscussTopic::Generic { .. } => frame_generic_discuss(user_text, topic),
    }
}

fn extract_plan_update_block(response: &str) -> Option<String> {
    let open = format!("```{PLAN_UPDATE_FENCE}");
    let start = response.find(&open)?;
    let after = &response[start + open.len()..];
    let close = after.find("```")?;
    Some(after[..close].trim().to_owned())
}

fn strip_plan_update(response: &str) -> String {
    let open = format!("```{PLAN_UPDATE_FENCE}");
    let Some(start) = response.find(&open) else {
        return response.trim().to_owned();
    };
    let mut result = response[..start].to_owned();
    let after_open = &response[start + open.len()..];
    if let Some(close) = after_open.find("```") {
        result.push_str(&after_open[close + 3..]);
    }
    result.trim().to_owned()
}

fn apply_plan_update_from_response(response: &str, fallback_plan_id: &str) -> Option<()> {
    let block = extract_plan_update_block(response)?;
    let mut value: Value = serde_json::from_str(&block).ok()?;
    let obj = value.as_object_mut()?;
    if obj
        .get("plan_id")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .is_empty()
        && !fallback_plan_id.is_empty()
    {
        obj.insert("plan_id".to_owned(), Value::String(fallback_plan_id.to_owned()));
    }
    // Host put_plan keys on `id`.
    if let Some(pid) = obj
        .get("plan_id")
        .and_then(|v| v.as_str())
        .map(str::to_owned)
    {
        obj.insert("id".to_owned(), Value::String(pid));
    }
    let _ = put_plan_artifact(value);
    Some(())
}

fn extract_plan_artifact_block(response: &str) -> Option<String> {
    let open = format!("```{PLAN_ARTIFACT_FENCE}");
    let start = response.find(&open)?;
    let after = &response[start + open.len()..];
    let close = after.find("```")?;
    Some(after[..close].trim().to_owned())
}

fn strip_plan_artifact(response: &str) -> String {
    let open = format!("```{PLAN_ARTIFACT_FENCE}");
    let Some(start) = response.find(&open) else {
        return response.trim().to_owned();
    };
    let mut result = response[..start].to_owned();
    let after_open = &response[start + open.len()..];
    if let Some(close) = after_open.find("```") {
        result.push_str(&after_open[close + 3..]);
    }
    result.trim().to_owned()
}

fn plan_payload_from_response(response: &str, user_request: &str) -> Value {
    if let Some(block) = extract_plan_artifact_block(response) {
        if let Ok(value) = serde_json::from_str::<Value>(&block) {
            if let Some(obj) = value.as_object() {
                let title = obj
                    .get("title")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim();
                let goal = obj
                    .get("goal")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim();
                let summary = obj
                    .get("summary")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim();
                let steps = obj
                    .get("steps")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default()
                    .into_iter()
                    .filter_map(|s| s.as_str().map(|t| t.trim().to_owned()))
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>();
                let risks = obj
                    .get("risks")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default()
                    .into_iter()
                    .filter_map(|s| s.as_str().map(|t| t.trim().to_owned()))
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>();
                let questions = obj
                    .get("open_questions")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default()
                    .into_iter()
                    .filter_map(|s| s.as_str().map(|t| t.trim().to_owned()))
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>();
                let related = obj
                    .get("related_mission")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim();
                let resolved_title = if !title.is_empty() {
                    title.to_owned()
                } else if !goal.is_empty() {
                    goal.chars().take(72).collect()
                } else {
                    "Proposed plan".to_owned()
                };
                return serde_json::json!({
                    "title": resolved_title,
                    "goal": goal,
                    "summary": if summary.is_empty() { goal } else { summary },
                    "steps": steps,
                    "risks": risks,
                    "open_questions": questions,
                    "related_mission": if related.is_empty() { Value::Null } else { Value::String(related.to_owned()) },
                    "status": "pending_review",
                });
            }
        }
    }

    // Fallback when the model omits the fence.
    let trimmed = response.trim();
    let steps: Vec<String> = trimmed
        .lines()
        .map(str::trim)
        .filter(|line| {
            !line.is_empty()
                && !line.starts_with('#')
                && !line.starts_with("```")
        })
        .take(8)
        .map(|line| {
            line.trim_start_matches(|c: char| {
                c == '-' || c == '*' || c == '.' || c.is_ascii_digit() || c.is_whitespace()
            })
            .trim()
            .to_owned()
        })
        .filter(|s| !s.is_empty())
        .collect();
    let title_seed = user_request.trim();
    let title = if title_seed.is_empty() {
        "Proposed plan".to_owned()
    } else {
        format!("Plan: {}", title_seed.chars().take(60).collect::<String>())
    };
    serde_json::json!({
        "title": title,
        "goal": trimmed.chars().take(240).collect::<String>(),
        "summary": trimmed.chars().take(280).collect::<String>(),
        "steps": steps,
        "risks": [],
        "open_questions": [],
        "status": "pending_review",
    })
}

fn put_plan_artifact(plan: Value) -> Result<Value, String> {
    let response = run_bridge_action("plan_put", serde_json::json!({ "plan": plan }))
        .ok_or_else(|| "Could not save the plan.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(response)
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not save the plan.")
            .to_owned())
    }
}

fn format_attachment_outbound(user_text: &str, attachments: &[PendingAttachment]) -> String {
    if attachments.is_empty() {
        return user_text.to_owned();
    }
    let mut lines = vec![
        "[Attachments — local paths on this brain; use read_file / vision tools as needed]".to_owned(),
    ];
    for item in attachments {
        lines.push(format!("- {} ({})", item.path.display(), item.filename));
    }
    lines.push(String::new());
    if user_text.trim().is_empty() {
        lines.push("Please review the attached files.".to_owned());
    } else {
        lines.push(user_text.to_owned());
    }
    lines.join("\n")
}

fn format_user_display(user_text: &str, attachments: &[PendingAttachment]) -> String {
    if attachments.is_empty() {
        return user_text.to_owned();
    }
    let names = attachments
        .iter()
        .map(|a| a.filename.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    if user_text.trim().is_empty() {
        format!("📎 {names}")
    } else {
        format!("📎 {names}\n\n{user_text}")
    }
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
/// Commits Memory Horizon continuity for the abandoned session first.
pub fn clear_desktop_chat_session() {
    if let Some(sid) = load_session_id() {
        let _ = run_bridge_json(
            "session_end_continuity",
            serde_json::json!({ "session_id": sid }),
        );
    }
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
            // Hide brand-new empty sessions (e.g. after delete used to spawn a
            // replacement). They reappear once the first message is sent.
            let message_count = row
                .get("message_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            if message_count == 0 {
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

fn rename_session(session_id: &str, title: &str) -> Result<String, String> {
    let response = run_bridge_json(
        "session_rename",
        serde_json::json!({ "session_id": session_id, "title": title }),
    )?;
    if response.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not rename that conversation.")
            .to_owned());
    }
    Ok(response
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or(title)
        .to_owned())
}

fn delete_session(session_id: &str) -> Result<(), String> {
    let response = run_bridge_json(
        "session_delete",
        serde_json::json!({ "session_id": session_id }),
    )?;
    if response.get("ok").and_then(|v| v.as_bool()) != Some(true) {
        return Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not delete that conversation.")
            .to_owned());
    }
    Ok(())
}

fn session_row(
    summary: &SessionSummary,
    active: bool,
    is_sending: Rc<RefCell<bool>>,
    on_rename: Rc<dyn Fn(SessionSummary)>,
    on_delete: Rc<dyn Fn(SessionSummary)>,
) -> gtk::ListBoxRow {
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
    box_.set_margin_end(4);

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

    let menu_button = gtk::MenuButton::builder()
        .icon_name("view-more-symbolic")
        .css_classes(["flat", "circular"])
        .tooltip_text("Rename or delete")
        .valign(gtk::Align::Center)
        .build();
    // Stop row activation when opening the menu.
    menu_button.set_focus_on_click(false);

    let popover = gtk::Popover::new();
    let menu_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    menu_box.set_margin_top(4);
    menu_box.set_margin_bottom(4);
    menu_box.set_margin_start(4);
    menu_box.set_margin_end(4);
    let rename_btn = gtk::Button::with_label("Rename…");
    rename_btn.add_css_class("flat");
    rename_btn.set_halign(gtk::Align::Fill);
    let delete_btn = gtk::Button::with_label("Delete…");
    delete_btn.add_css_class("flat");
    delete_btn.add_css_class("destructive-action");
    delete_btn.set_halign(gtk::Align::Fill);
    menu_box.append(&rename_btn);
    menu_box.append(&delete_btn);
    popover.set_child(Some(&menu_box));
    menu_button.set_popover(Some(&popover));

    let summary_rename = summary.clone();
    let on_rename = on_rename.clone();
    let is_sending_rename = is_sending.clone();
    let popover_rename = popover.clone();
    rename_btn.connect_clicked(move |_| {
        if *is_sending_rename.borrow() {
            return;
        }
        popover_rename.popdown();
        on_rename(summary_rename.clone());
    });

    let summary_delete = summary.clone();
    let on_delete = on_delete.clone();
    let is_sending_delete = is_sending.clone();
    let popover_delete = popover.clone();
    delete_btn.connect_clicked(move |_| {
        if *is_sending_delete.borrow() {
            return;
        }
        popover_delete.popdown();
        on_delete(summary_delete.clone());
    });

    // Right-click opens the same menu.
    let right_click = gtk::GestureClick::new();
    right_click.set_button(3);
    let menu_button_rc = menu_button.clone();
    let is_sending_rc = is_sending.clone();
    right_click.connect_pressed(move |_, _, _, _| {
        if *is_sending_rc.borrow() {
            return;
        }
        menu_button_rc.popup();
    });
    row.add_controller(right_click);

    title_row.append(&menu_button);
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
    let line = match serde_json::to_vec(&payload) {
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
        let event_name = value
            .get("centurion_event")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if event_name == "activity" {
            let kind = value
                .get("kind")
                .and_then(|v| v.as_str())
                .unwrap_or("status")
                .to_owned();
            let line = value
                .get("line")
                .and_then(|v| v.as_str())
                .or_else(|| value.get("message").and_then(|v| v.as_str()))
                .or_else(|| value.get("text").and_then(|v| v.as_str()))
                .unwrap_or("")
                .to_owned();
            let text = value
                .get("text")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();
            let tool = value
                .get("tool")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();
            if !line.is_empty() || !text.is_empty() {
                let _ = event_tx.send(WorkerEvent::Activity(ActivityEvent {
                    kind,
                    line: if line.is_empty() {
                        text.clone()
                    } else {
                        line
                    },
                    text,
                    tool,
                }));
            }
            continue;
        }
        if event_name == "approval_request" {
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
        // Ignore unknown event types; keep reading until the final chat reply.
        if !event_name.is_empty() {
            continue;
        }
        // Final reply: prefer payloads that look like a chat result.
        let looks_final = value.get("ok").is_some()
            || value.get("text").is_some()
            || value.get("reply").is_some()
            || value.get("response").is_some()
            || value.get("message").is_some();
        if looks_final {
            final_response = Some(value);
            break;
        }
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
        let caption = if message.content.starts_with("Worked with")
            || message.content.starts_with("Thinking")
        {
            "Activity"
        } else {
            "Status"
        };
        bubble.append(
            &gtk::Label::builder()
                .label(caption)
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
    // Clear on next idle so a late value_changed does not disarm follow_bottom.
    let programmatic = programmatic.clone();
    glib::idle_add_local_once(move || {
        programmatic.set(false);
    });
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
            if !follow_bottom.get() {
                return;
            }
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
    const NEAR_BOTTOM_PX: f64 = 80.0;

    adj.connect_changed({
        let follow_bottom = follow_bottom.clone();
        let programmatic = programmatic.clone();
        move |adj| {
            if !follow_bottom.get() {
                return;
            }
            let target = (adj.upper() - adj.page_size()).max(adj.lower());
            if (adj.value() - target).abs() > 0.5 {
                programmatic.set(true);
                adj.set_value(target);
                let programmatic = programmatic.clone();
                glib::idle_add_local_once(move || {
                    programmatic.set(false);
                });
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
            // they return near the bottom or the next send arms follow again.
            follow_bottom.set(adj.value() >= target - NEAR_BOTTOM_PX);
        }
    });
}

/// Re-pin to bottom whenever transcript layout grows (Cursor-style chase).
fn wire_transcript_size_follow(
    transcript: &impl IsA<gtk::Widget>,
    message_scroll: &gtk::ScrolledWindow,
    message_list: &gtk::ListBox,
    follow_bottom: Rc<Cell<bool>>,
    programmatic: Rc<Cell<bool>>,
) {
    let pending = Rc::new(Cell::new(false));
    transcript.connect_size_allocate({
        let message_scroll = message_scroll.clone();
        let message_list = message_list.clone();
        let follow_bottom = follow_bottom.clone();
        let programmatic = programmatic.clone();
        let pending = pending.clone();
        move |_, _| {
            if !follow_bottom.get() || pending.get() {
                return;
            }
            pending.set(true);
            let message_scroll = message_scroll.clone();
            let message_list = message_list.clone();
            let follow_bottom = follow_bottom.clone();
            let programmatic = programmatic.clone();
            let pending = pending.clone();
            glib::idle_add_local_once(move || {
                pending.set(false);
                if follow_bottom.get() {
                    scroll_chat_to_latest(&message_scroll, &message_list, &programmatic);
                }
            });
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
pub fn build() -> (gtk::Box, ChatHandle) {
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
    message_list.set_margin_bottom(8);

    let activity_card = gtk::Box::new(gtk::Orientation::Vertical, 6);
    activity_card.add_css_class("centurion-chat-activity");
    activity_card.set_margin_top(0);
    activity_card.set_hexpand(true);
    activity_card.set_visible(false);
    let activity_title = gtk::Label::builder()
        .label("Working…")
        .xalign(0.0)
        .css_classes(["caption-heading"])
        .build();
    activity_card.append(&activity_title);
    let thinking_label = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .css_classes(["dim-label"])
        .selectable(true)
        .build();
    let thinking_expander = gtk::Expander::builder()
        .label("Thinking")
        .expanded(true)
        .build();
    thinking_expander.set_child(Some(&thinking_label));
    thinking_expander.set_visible(false);
    activity_card.append(&thinking_expander);
    let activity_tools = gtk::Box::new(gtk::Orientation::Vertical, 4);
    activity_card.append(&activity_tools);

    let transcript_spacer = gtk::Box::new(gtk::Orientation::Vertical, 0);
    transcript_spacer.add_css_class("centurion-chat-transcript-spacer");
    transcript_spacer.set_size_request(-1, 40);
    transcript_spacer.set_hexpand(true);

    // Cursor-style: bubbles + live Activity share one scroll surface; composer stays fixed below.
    let transcript_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    transcript_box.set_hexpand(true);
    transcript_box.append(&message_list);
    transcript_box.append(&activity_card);
    transcript_box.append(&transcript_spacer);

    let message_scroll = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
        .propagate_natural_height(false)
        .build();
    message_scroll.set_child(Some(&transcript_box));
    let follow_bottom = Rc::new(Cell::new(true));
    let programmatic_scroll = Rc::new(Cell::new(false));
    wire_follow_bottom_scroll(
        &message_scroll,
        follow_bottom.clone(),
        programmatic_scroll.clone(),
    );
    wire_transcript_size_follow(
        &transcript_box,
        &message_scroll,
        &message_list,
        follow_bottom.clone(),
        programmatic_scroll.clone(),
    );
    wire_transcript_size_follow(
        &activity_card,
        &message_scroll,
        &message_list,
        follow_bottom.clone(),
        programmatic_scroll.clone(),
    );
    chat_column.append(&message_scroll);

    let activity_tool_count = Rc::new(Cell::new(0usize));
    let activity_has_thinking = Rc::new(Cell::new(false));

    let clear_activity_box = {
        let activity_tools = activity_tools.clone();
        Rc::new(move || {
            while let Some(child) = activity_tools.first_child() {
                activity_tools.remove(&child);
            }
        })
    };

    let reset_activity: Rc<dyn Fn()> = Rc::new({
        let activity_card = activity_card.clone();
        let activity_title = activity_title.clone();
        let thinking_expander = thinking_expander.clone();
        let thinking_label = thinking_label.clone();
        let clear_activity_box = clear_activity_box.clone();
        let activity_tool_count = activity_tool_count.clone();
        let activity_has_thinking = activity_has_thinking.clone();
        move || {
            clear_activity_box();
            thinking_label.set_label("");
            thinking_expander.set_visible(false);
            thinking_expander.set_expanded(true);
            activity_title.set_label("Working…");
            activity_tool_count.set(0);
            activity_has_thinking.set(false);
            activity_card.set_visible(false);
        }
    });

    let show_activity_working: Rc<dyn Fn()> = Rc::new({
        let reset_activity = reset_activity.clone();
        let activity_card = activity_card.clone();
        let activity_title = activity_title.clone();
        let follow_bottom = follow_bottom.clone();
        let message_scroll = message_scroll.clone();
        let message_list = message_list.clone();
        let programmatic_scroll = programmatic_scroll.clone();
        move || {
            reset_activity();
            activity_title.set_label("Working…");
            activity_card.set_visible(true);
            follow_bottom.set(true);
            schedule_scroll_to_latest(
                &message_scroll,
                &message_list,
                &follow_bottom,
                &programmatic_scroll,
            );
        }
    });

    let apply_activity: Rc<dyn Fn(ActivityEvent)> = Rc::new({
        let activity_card = activity_card.clone();
        let activity_title = activity_title.clone();
        let thinking_expander = thinking_expander.clone();
        let thinking_label = thinking_label.clone();
        let activity_tools = activity_tools.clone();
        let activity_tool_count = activity_tool_count.clone();
        let activity_has_thinking = activity_has_thinking.clone();
        let follow_bottom = follow_bottom.clone();
        let message_scroll = message_scroll.clone();
        let message_list = message_list.clone();
        let programmatic_scroll = programmatic_scroll.clone();
        move |event: ActivityEvent| {
            activity_card.set_visible(true);
            match event.kind.as_str() {
                "thinking" => {
                    let text = if event.text.is_empty() {
                        event.line.clone()
                    } else {
                        event.text.clone()
                    };
                    if text.trim().is_empty() {
                        return;
                    }
                    thinking_label.set_label(&text);
                    thinking_expander.set_visible(true);
                    activity_has_thinking.set(true);
                    activity_title.set_label("Thinking…");
                }
                "tool" => {
                    let line = if event.line.is_empty() {
                        format!("⚙️ {}", event.tool)
                    } else {
                        event.line.clone()
                    };
                    activity_tools.append(
                        &gtk::Label::builder()
                            .label(&line)
                            .wrap(true)
                            .xalign(0.0)
                            .css_classes(["dim-label", "centurion-chat-activity-line"])
                            .build(),
                    );
                    activity_tool_count.set(activity_tool_count.get().saturating_add(1));
                    activity_title.set_label("Working…");
                }
                _ => {
                    let line = if event.line.is_empty() {
                        event.text.clone()
                    } else {
                        event.line.clone()
                    };
                    if line.trim().is_empty() {
                        return;
                    }
                    activity_tools.append(
                        &gtk::Label::builder()
                            .label(&line)
                            .wrap(true)
                            .xalign(0.0)
                            .css_classes(["dim-label", "centurion-chat-activity-line"])
                            .build(),
                    );
                }
            }
            follow_bottom.set(true);
            schedule_scroll_to_latest(
                &message_scroll,
                &message_list,
                &follow_bottom,
                &programmatic_scroll,
            );
        }
    });

    let finish_activity_summary: Rc<dyn Fn() -> Option<String>> = Rc::new({
        let reset_activity = reset_activity.clone();
        let activity_tool_count = activity_tool_count.clone();
        let activity_has_thinking = activity_has_thinking.clone();
        move || {
            let tools = activity_tool_count.get();
            let thinking = activity_has_thinking.get();
            reset_activity();
            if tools == 0 && !thinking {
                return None;
            }
            let mut parts = Vec::new();
            if thinking {
                parts.push("thinking".to_owned());
            }
            if tools == 1 {
                parts.push("1 tool".to_owned());
            } else if tools > 1 {
                parts.push(format!("{tools} tools"));
            }
            Some(format!("Worked with {}.", parts.join(" · ")))
        }
    });

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

    let error_row = gtk::Box::new(gtk::Orientation::Vertical, 6);
    error_row.set_margin_start(16);
    error_row.set_margin_end(16);
    error_row.set_margin_bottom(4);
    error_row.set_visible(false);
    let error_label = gtk::Label::builder()
        .wrap(true)
        .xalign(0.0)
        .css_classes(["error"])
        .build();
    let fix_thinking_button = gtk::Button::with_label("Fix Thinking Service");
    fix_thinking_button.add_css_class("suggested-action");
    fix_thinking_button.set_halign(gtk::Align::Start);
    fix_thinking_button.set_visible(false);
    fix_thinking_button.set_tooltip_text(Some(
        "Open the same Fix Thinking wizard as Settings — catalog, access code, apply, probe.",
    ));
    error_row.append(&error_label);
    error_row.append(&fix_thinking_button);
    bottom.append(&error_row);

    let active_discuss: Rc<RefCell<Option<DiscussTopic>>> = Rc::new(RefCell::new(None));
    let context_bar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    context_bar.set_margin_start(16);
    context_bar.set_margin_end(16);
    context_bar.set_margin_bottom(4);
    context_bar.set_visible(false);
    context_bar.add_css_class("centurion-chat-context");
    let context_banner = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .hexpand(true)
        .css_classes(["dim-label", "caption"])
        .build();
    let clear_context = gtk::Button::with_label("Clear topic");
    clear_context.add_css_class("flat");
    clear_context.set_tooltip_text(Some(
        "Stop framing replies around this Home topic",
    ));
    {
        let active_discuss = active_discuss.clone();
        let context_banner = context_banner.clone();
        let context_bar = context_bar.clone();
        clear_context.connect_clicked(move |_| {
            *active_discuss.borrow_mut() = None;
            context_banner.set_label("");
            context_bar.set_visible(false);
        });
    }
    context_bar.append(&context_banner);
    context_bar.append(&clear_context);
    bottom.append(&context_bar);

    let on_fix_thinking: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));
    {
        let on_fix_thinking = on_fix_thinking.clone();
        fix_thinking_button.connect_clicked(move |_| {
            if let Some(handler) = on_fix_thinking.borrow().clone() {
                handler();
            }
        });
    }

    // Intent chips: Talk (default) | Propose first
    let intent = Rc::new(Cell::new(ChatIntent::Talk));
    let intent_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    intent_row.set_margin_start(16);
    intent_row.set_margin_end(16);
    intent_row.set_margin_bottom(4);
    intent_row.add_css_class("centurion-chat-intents");
    let talk_btn = gtk::ToggleButton::with_label("Talk");
    talk_btn.add_css_class("centurion-chat-intent");
    talk_btn.set_active(true);
    let propose_btn = gtk::ToggleButton::with_label("Propose first");
    propose_btn.add_css_class("centurion-chat-intent");
    propose_btn.set_tooltip_text(Some(
        "Ask for a plan only — review it on Home under Plans / Needs your choice.",
    ));
    {
        let intent = intent.clone();
        let propose_btn = propose_btn.clone();
        talk_btn.connect_toggled(move |b| {
            if b.is_active() {
                intent.set(ChatIntent::Talk);
                propose_btn.set_active(false);
            } else if !propose_btn.is_active() {
                b.set_active(true);
            }
        });
    }
    {
        let intent = intent.clone();
        let talk_btn = talk_btn.clone();
        propose_btn.connect_toggled(move |b| {
            if b.is_active() {
                intent.set(ChatIntent::ProposeFirst);
                talk_btn.set_active(false);
            } else if !talk_btn.is_active() {
                b.set_active(true);
            }
        });
    }
    intent_row.append(&talk_btn);
    intent_row.append(&propose_btn);
    bottom.append(&intent_row);

    // Attachment chips
    let attachments: Rc<RefCell<Vec<PendingAttachment>>> = Rc::new(RefCell::new(Vec::new()));
    let attachment_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    attachment_row.set_margin_start(16);
    attachment_row.set_margin_end(16);
    attachment_row.set_margin_bottom(4);
    attachment_row.set_visible(false);
    attachment_row.add_css_class("centurion-chat-attachments");
    bottom.append(&attachment_row);

    let refresh_attachments: Rc<dyn Fn()> = {
        let attachment_row = attachment_row.clone();
        let attachments = attachments.clone();
        Rc::new(move || {
            rebuild_attachment_chips(&attachment_row, &attachments);
        })
    };

    let input_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    input_row.set_margin_start(16);
    input_row.set_margin_end(16);
    input_row.set_margin_top(6);
    input_row.set_margin_bottom(16);
    input_row.set_vexpand(false);

    let attach_button = gtk::Button::from_icon_name("mail-attachment-symbolic");
    attach_button.set_tooltip_text(Some("Attach files"));
    attach_button.add_css_class("flat");
    attach_button.set_valign(gtk::Align::Center);
    attach_button.set_size_request(44, 44);

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

    input_row.append(&attach_button);
    input_row.append(&input);
    input_row.append(&send_button);
    input_row.append(&sending_spinner);
    bottom.append(&input_row);
    chat_column.append(&bottom);

    {
        let attachments = attachments.clone();
        let refresh_attachments = refresh_attachments.clone();
        let input = input.clone();
        attach_button.connect_clicked(move |_| {
            let Some(window) = input.root().and_downcast::<gtk::Window>() else {
                return;
            };
            let dialog = gtk::FileDialog::builder()
                .title("Attach files")
                .modal(true)
                .build();
            let attachments = attachments.clone();
            let refresh_attachments = refresh_attachments.clone();
            dialog.open_multiple(Some(&window), gio::Cancellable::NONE, move |result| {
                let Ok(model) = result else {
                    return;
                };
                let n = model.n_items();
                let mut added = false;
                for i in 0..n {
                    let Some(obj) = model.item(i) else {
                        continue;
                    };
                    let Ok(file) = obj.downcast::<gio::File>() else {
                        continue;
                    };
                    let Some(path) = file.path() else {
                        continue;
                    };
                    let filename = path
                        .file_name()
                        .map(|n| n.to_string_lossy().into_owned())
                        .unwrap_or_else(|| path.display().to_string());
                    let already = attachments.borrow().iter().any(|a| a.path == path);
                    if already {
                        continue;
                    }
                    attachments
                        .borrow_mut()
                        .push(PendingAttachment { path, filename });
                    added = true;
                }
                if added {
                    refresh_attachments();
                }
            });
        });
    }

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

    let refresh_sessions_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> =
        Rc::new(RefCell::new(None));
    let refresh_sessions: Rc<dyn Fn()> = Rc::new({
        let slot = refresh_sessions_slot.clone();
        move || {
            if let Some(refresh) = slot.borrow().clone() {
                refresh();
            }
        }
    });

    let set_error: Rc<dyn Fn(Option<String>)> = Rc::new({
        let error_row = error_row.clone();
        let error_label = error_label.clone();
        let fix_thinking_button = fix_thinking_button.clone();
        move |text: Option<String>| {
            if let Some(message) = text {
                error_label.set_label(&message);
                error_row.set_visible(true);
                fix_thinking_button.set_visible(looks_like_thinking_error(&message));
            } else {
                error_label.set_label("");
                error_row.set_visible(false);
                fix_thinking_button.set_visible(false);
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

    let start_new_chat: Rc<dyn Fn()> = Rc::new({
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let clear_approval = clear_approval.clone();
        let set_sending = set_sending.clone();
        let assistant_name = assistant_name.clone();
        let follow_bottom = follow_bottom.clone();
        let active_discuss = active_discuss.clone();
        let context_banner = context_banner.clone();
        let context_bar = context_bar.clone();
        move || {
            clear_approval();
            set_sending(false);
            set_error(None);
            *assistant_name.borrow_mut() = load_assistant_display_name();
            messages.borrow_mut().clear();
            *active_discuss.borrow_mut() = None;
            context_banner.set_label("");
            context_bar.set_visible(false);
            // Commit continuity for the active chat, then lazy-clear so the next
            // send creates a fresh session without an empty Conversations ghost.
            if let Some(sid) = session_id.borrow().clone() {
                let _ = run_bridge_json(
                    "session_end_continuity",
                    serde_json::json!({ "session_id": sid }),
                );
            }
            *session_id.borrow_mut() = None;
            let path = session_store_path();
            let _ = std::fs::remove_file(&path);
            follow_bottom.set(true);
            refresh_messages();
            refresh_sessions();
        }
    });

    let prompt_rename_session: Rc<dyn Fn(SessionSummary)> = Rc::new({
        let container = container.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let is_sending = is_sending.clone();
        move |summary: SessionSummary| {
            if *is_sending.borrow() {
                return;
            }
            let entry = gtk::Entry::builder()
                .text(&summary.title)
                .hexpand(true)
                .build();
            let dialog = adw::AlertDialog::builder()
                .heading("Rename conversation")
                .body("Choose a name for this chat.")
                .extra_child(&entry)
                .close_response("cancel")
                .default_response("save")
                .build();
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("save", "Save");
            dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
            let refresh_sessions = refresh_sessions.clone();
            let set_error = set_error.clone();
            let session_key = summary.id.clone();
            dialog.connect_response(None, move |_dialog, response| {
                if response != "save" {
                    return;
                }
                let title = entry.text().trim().to_string();
                if title.is_empty() {
                    set_error(Some("Enter a conversation name.".to_owned()));
                    return;
                }
                set_error(None);
                let refresh_sessions = refresh_sessions.clone();
                let set_error = set_error.clone();
                let session_key = session_key.clone();
                let (tx, rx) = mpsc::channel::<Result<String, String>>();
                thread::spawn(move || {
                    let _ = tx.send(rename_session(&session_key, &title));
                });
                glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                    Ok(Ok(_)) => {
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
            dialog.present(Some(&container));
        }
    });

    let prompt_delete_session: Rc<dyn Fn(SessionSummary)> = Rc::new({
        let container = container.clone();
        let refresh_sessions = refresh_sessions.clone();
        let refresh_messages = refresh_messages.clone();
        let set_error = set_error.clone();
        let is_sending = is_sending.clone();
        let session_id = session_id.clone();
        let messages = messages.clone();
        let clear_approval = clear_approval.clone();
        let follow_bottom = follow_bottom.clone();
        let assistant_name = assistant_name.clone();
        move |summary: SessionSummary| {
            if *is_sending.borrow() {
                return;
            }
            let dialog = adw::AlertDialog::builder()
                .heading("Delete conversation?")
                .body(format!(
                    "Delete “{}”? This cannot be undone.",
                    summary.title
                ))
                .close_response("cancel")
                .default_response("cancel")
                .build();
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("delete", "Delete");
            dialog.set_response_appearance("delete", adw::ResponseAppearance::Destructive);
            let refresh_sessions = refresh_sessions.clone();
            let refresh_messages = refresh_messages.clone();
            let set_error = set_error.clone();
            let session_id = session_id.clone();
            let messages = messages.clone();
            let clear_approval = clear_approval.clone();
            let follow_bottom = follow_bottom.clone();
            let assistant_name = assistant_name.clone();
            let target_id = summary.id.clone();
            dialog.connect_response(None, move |_dialog, response| {
                if response != "delete" {
                    return;
                }
                set_error(None);
                let was_active = session_id.borrow().as_deref() == Some(target_id.as_str());
                let refresh_sessions = refresh_sessions.clone();
                let refresh_messages = refresh_messages.clone();
                let set_error = set_error.clone();
                let session_id = session_id.clone();
                let messages = messages.clone();
                let clear_approval = clear_approval.clone();
                let follow_bottom = follow_bottom.clone();
                let assistant_name = assistant_name.clone();
                let target_id = target_id.clone();
                let (tx, rx) = mpsc::channel::<Result<(), String>>();
                thread::spawn(move || {
                    let _ = tx.send(delete_session(&target_id));
                });
                glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                    Ok(Ok(())) => {
                        if was_active {
                            // Remove from stream only — do not spawn a replacement
                            // session (that showed up as "Untitled chat · Just now").
                            clear_approval();
                            messages.borrow_mut().clear();
                            *session_id.borrow_mut() = None;
                            let path = session_store_path();
                            let _ = std::fs::remove_file(&path);
                            follow_bottom.set(true);
                            *assistant_name.borrow_mut() = load_assistant_display_name();
                            refresh_messages();
                        }
                        // After the list refreshes, open the newest remaining chat
                        // if the deleted one was active.
                        let session_id = session_id.clone();
                        let messages = messages.clone();
                        let refresh_messages = refresh_messages.clone();
                        let refresh_sessions = refresh_sessions.clone();
                        let set_error = set_error.clone();
                        let follow_bottom = follow_bottom.clone();
                        let assistant_name = assistant_name.clone();
                        let (list_tx, list_rx) = mpsc::channel::<Vec<SessionSummary>>();
                        thread::spawn(move || {
                            let _ = list_tx.send(list_sessions());
                        });
                        glib::timeout_add_local(Duration::from_millis(50), move || {
                            match list_rx.try_recv() {
                                Ok(remaining) => {
                                    if was_active {
                                        if let Some(next) = remaining.first().cloned() {
                                            let session_id = session_id.clone();
                                            let messages = messages.clone();
                                            let refresh_messages = refresh_messages.clone();
                                            let refresh_sessions = refresh_sessions.clone();
                                            let set_error = set_error.clone();
                                            let follow_bottom = follow_bottom.clone();
                                            let assistant_name = assistant_name.clone();
                                            let (tx, rx) = mpsc::channel::<
                                                Result<(String, Vec<ChatMessage>), String>,
                                            >();
                                            thread::spawn(move || {
                                                let _ = tx.send(resume_session(&next.id));
                                            });
                                            glib::timeout_add_local(
                                                Duration::from_millis(50),
                                                move || match rx.try_recv() {
                                                    Ok(Ok((sid, history))) => {
                                                        save_session_id(&sid);
                                                        *session_id.borrow_mut() = Some(sid);
                                                        *messages.borrow_mut() = history;
                                                        *assistant_name.borrow_mut() =
                                                            load_assistant_display_name();
                                                        follow_bottom.set(true);
                                                        refresh_messages();
                                                        refresh_sessions();
                                                        glib::ControlFlow::Break
                                                    }
                                                    Ok(Err(error)) => {
                                                        set_error(Some(error));
                                                        refresh_sessions();
                                                        glib::ControlFlow::Break
                                                    }
                                                    Err(mpsc::TryRecvError::Empty) => {
                                                        glib::ControlFlow::Continue
                                                    }
                                                    Err(mpsc::TryRecvError::Disconnected) => {
                                                        refresh_sessions();
                                                        glib::ControlFlow::Break
                                                    }
                                                },
                                            );
                                        } else {
                                            refresh_sessions();
                                        }
                                    } else {
                                        refresh_sessions();
                                    }
                                    glib::ControlFlow::Break
                                }
                                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                                Err(mpsc::TryRecvError::Disconnected) => {
                                    refresh_sessions();
                                    glib::ControlFlow::Break
                                }
                            }
                        });
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
            dialog.present(Some(&container));
        }
    });

    *refresh_sessions_slot.borrow_mut() = Some(Rc::new({
        let session_list = session_list.clone();
        let session_stack = session_stack.clone();
        let session_id = session_id.clone();
        let is_sending = is_sending.clone();
        let prompt_rename_session = prompt_rename_session.clone();
        let prompt_delete_session = prompt_delete_session.clone();
        move || {
            let session_list = session_list.clone();
            let session_stack = session_stack.clone();
            let session_id = session_id.clone();
            let is_sending = is_sending.clone();
            let prompt_rename_session = prompt_rename_session.clone();
            let prompt_delete_session = prompt_delete_session.clone();
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
                            let row = session_row(
                                summary,
                                is_active,
                                is_sending.clone(),
                                prompt_rename_session.clone(),
                                prompt_delete_session.clone(),
                            );
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
    }));

    // Initial session + history + sidebar load (bridge stays off the UI thread).
    // Prefer an existing non-empty conversation; do not create a blank DB row
    // just to open Chat (that used to show up as "Untitled chat · Just now").
    {
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let (tx, rx) =
            mpsc::channel::<Result<Option<(String, Vec<ChatMessage>)>, String>>();
        thread::spawn(move || {
            if let Some(sid) = load_session_id() {
                let history = load_history(&sid);
                let listed = list_sessions();
                if listed.iter().any(|s| s.id == sid) || !history.is_empty() {
                    let _ = tx.send(Ok(Some((sid, history))));
                    return;
                }
                // Stale pointer (deleted / empty-only) — drop it.
                let path = session_store_path();
                let _ = std::fs::remove_file(&path);
            }
            if let Some(next) = list_sessions().into_iter().next() {
                match resume_session(&next.id) {
                    Ok(pair) => {
                        let _ = tx.send(Ok(Some(pair)));
                    }
                    Err(err) => {
                        let _ = tx.send(Err(err));
                    }
                }
                return;
            }
            let _ = tx.send(Ok(None));
        });
        glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
            Ok(Ok(Some((sid, history)))) => {
                save_session_id(&sid);
                *session_id.borrow_mut() = Some(sid);
                *messages.borrow_mut() = history;
                refresh_messages();
                refresh_sessions();
                glib::ControlFlow::Break
            }
            Ok(Ok(None)) => {
                *session_id.borrow_mut() = None;
                messages.borrow_mut().clear();
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

    // New chat
    {
        let start_new_chat = start_new_chat.clone();
        let is_sending = is_sending.clone();
        new_chat_button.connect_clicked(move |_| {
            if *is_sending.borrow() {
                return;
            }
            start_new_chat();
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
        let intent = intent.clone();
        let attachments = attachments.clone();
        let refresh_attachments = refresh_attachments.clone();
        let active_discuss = active_discuss.clone();
        let show_activity_working = show_activity_working.clone();
        let apply_activity = apply_activity.clone();
        let finish_activity_summary = finish_activity_summary.clone();
        move || {
            if *is_sending.borrow() {
                return;
            }
            let text = input.text().to_string();
            let pending = attachments.borrow().clone();
            if text.trim().is_empty() && pending.is_empty() {
                return;
            }
            let propose_first = intent.get() == ChatIntent::ProposeFirst;
            // Soul save clears the on-disk session pointer — drop the stale
            // in-memory session so the next turn loads the new SOUL.md cleanly.
            let _ = honor_soul_session_reset(&session_id, &messages);
            // Always refresh the title from disk so Settings → Name shows up.
            *assistant_name.borrow_mut() = load_assistant_display_name();
            title.set_label(&format!("Chat with {}", assistant_name.borrow()));
            input.set_text("");
            attachments.borrow_mut().clear();
            refresh_attachments();
            follow_bottom.set(true);
            messages.borrow_mut().push(ChatMessage {
                role: ChatRole::User,
                content: format_user_display(&text, &pending),
            });
            refresh_messages();
            set_error(None);
            clear_approval();
            show_activity_working();
            set_sending(true);

            let discuss_topic = active_discuss.borrow().clone();
            let mut outbound = format_attachment_outbound(&text, &pending);
            if propose_first {
                // Propose-first is its own framing; drop topic frame for this turn.
                outbound = frame_propose_first(&outbound);
            } else if let Some(ref topic) = discuss_topic {
                outbound = frame_discuss_outbound(&outbound, topic);
            }
            let user_request = text.clone();
            let plan_id_for_update = match &discuss_topic {
                Some(DiscussTopic::Plan { id, .. }) => id.clone(),
                Some(DiscussTopic::Document {
                    plan_id: Some(pid), ..
                }) => pid.clone(),
                _ => String::new(),
            };
            let commitment_id_for_update = match &discuss_topic {
                Some(DiscussTopic::Commitment { id, .. }) => id.clone(),
                _ => String::new(),
            };
            let applying_plan_update = !propose_first && !plan_id_for_update.is_empty();
            let applying_commitment_update =
                !propose_first && !commitment_id_for_update.is_empty();

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
                run_chat_turn(sid, outbound, event_tx, approval_rx);
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
            let apply_activity = apply_activity.clone();
            let finish_activity_summary = finish_activity_summary.clone();
            glib::timeout_add_local(Duration::from_millis(50), move || {
                match event_rx.try_recv() {
                    Ok(WorkerEvent::Approval(request)) => {
                        show_approval(request);
                        glib::ControlFlow::Continue
                    }
                    Ok(WorkerEvent::Activity(event)) => {
                        apply_activity(event);
                        glib::ControlFlow::Continue
                    }
                    Ok(WorkerEvent::Done(result)) => {
                        set_sending(false);
                        clear_approval();
                        *pending_approval_tx.borrow_mut() = None;
                        let summary = finish_activity_summary();
                        match result {
                            Ok(turn) => {
                                save_session_id(&turn.session_id);
                                *session_id.borrow_mut() = Some(turn.session_id);
                                let mut display = if propose_first {
                                    strip_plan_artifact(&turn.text)
                                } else if applying_plan_update {
                                    strip_plan_update(&turn.text)
                                } else if applying_commitment_update {
                                    strip_commitment_update(&turn.text)
                                } else {
                                    turn.text.clone()
                                };
                                if propose_first {
                                    let plan =
                                        plan_payload_from_response(&turn.text, &user_request);
                                    thread::spawn(move || {
                                        let _ = put_plan_artifact(plan);
                                    });
                                    if display.trim().is_empty() {
                                        display = "I've drafted a plan for your review on Home — open Plans, Needs your choice, or Documents when you're ready.".to_owned();
                                    } else if !display.to_lowercase().contains("home")
                                        && !display.to_lowercase().contains("plan")
                                    {
                                        display.push_str(
                                            "\n\nYou can review this plan on Home under Plans, Needs your choice, or Documents.",
                                        );
                                    }
                                } else if applying_plan_update {
                                    let raw = turn.text.clone();
                                    let pid = plan_id_for_update.clone();
                                    thread::spawn(move || {
                                        let _ = apply_plan_update_from_response(&raw, &pid);
                                    });
                                } else if applying_commitment_update {
                                    let raw = turn.text.clone();
                                    let cid = commitment_id_for_update.clone();
                                    thread::spawn(move || {
                                        let _ = apply_commitment_update_from_response(&raw, &cid);
                                    });
                                }
                                if let Some(summary) = summary {
                                    messages.borrow_mut().push(ChatMessage {
                                        role: ChatRole::System,
                                        content: summary,
                                    });
                                }
                                messages.borrow_mut().push(ChatMessage {
                                    role: ChatRole::Assistant,
                                    content: display,
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
                        let _ = finish_activity_summary();
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

    let handle = ChatHandle {
        input: input.clone(),
        active_discuss: active_discuss.clone(),
        context_banner: context_banner.clone(),
        context_bar: context_bar.clone(),
        on_fix_thinking,
    };
    (container, handle)
}
