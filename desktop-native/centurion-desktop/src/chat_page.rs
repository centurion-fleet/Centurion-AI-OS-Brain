//! Phone-like bubble chat for the Linux Brain Chat tab.
//!
//! Drives the local Centurion agent via `centurion_cli.remote_bridge`
//! (same path as iPhone Crypto Chat), with mid-turn tool approvals.

use adw::prelude::*;
use gtk4 as gtk;
use gtk4::gdk::{self, Key, ModifierType};
use gdk::prelude::*;
use gio;
use libadwaita as adw;
use serde_json::Value;
use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::process::Command;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
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
    /// Frozen activity trail for System rows after a turn (Cursor-like work history).
    activity: Option<ActivityArchive>,
}

#[derive(Clone, Debug, Default)]
struct ActivityArchive {
    summary: String,
    thinking: String,
    tool_lines: Vec<String>,
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
    message_count: u64,
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
        /// Offline life.db mission id when known (for context inject).
        id: Option<String>,
        title: Option<String>,
        target_id: Option<String>,
        target_title: Option<String>,
        target_type: Option<String>,
        target_description: Option<String>,
        target_status: Option<String>,
        sequence_number: Option<i64>,
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
            Self::Mission {
                title,
                target_title,
                ..
            } => {
                let mission = title
                    .as_deref()
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or("Life Mission");
                match target_title
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                {
                    Some(t) => format!("Discussing Mission · {mission} · {t}"),
                    None => format!("Discussing Mission · {mission}"),
                }
            }
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

    /// Conversations sidebar title for this topic (find-or-create on Discuss).
    pub fn session_title(&self) -> String {
        let raw = match self {
            Self::Plan { title, .. } => title.clone(),
            Self::Collab { name, .. } => name.clone(),
            Self::Document { title, .. } => title.clone(),
            Self::Mission {
                title,
                target_title,
                statement,
                ..
            } => {
                let mission = title
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .or_else(|| {
                        let s = statement.trim();
                        if s.is_empty() {
                            None
                        } else {
                            Some(s)
                        }
                    })
                    .unwrap_or("Life Mission");
                let mission = truncate_chars(mission, 48);
                match target_title
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                {
                    Some(t) => format!("{mission} · {}", truncate_chars(t, 32)),
                    None => mission,
                }
            }
            Self::Commitment { title, .. } => title.clone(),
            Self::Horizon { layer, .. } => format!("Memory Horizon · {layer}"),
            Self::Generic { title, .. } => title.clone(),
        };
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            "Discussion".to_owned()
        } else {
            truncate_chars(trimmed, 64)
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

fn truncate_chars(s: &str, max: usize) -> String {
    let mut out: String = s.chars().take(max).collect();
    if s.chars().count() > max {
        out.push('…');
    }
    out
}

/// Handle for other tabs (Home) to seed the Chat composer with topic context.
#[derive(Clone)]
pub struct ChatHandle {
    input: ComposerInput,
    active_discuss: Rc<RefCell<Option<DiscussTopic>>>,
    context_banner: gtk::Label,
    context_bar: gtk::Box,
    on_fix_thinking: Rc<RefCell<Option<Rc<dyn Fn()>>>>,
    /// Pending tool-approval prompts (drives Chat tab badge).
    attention: Rc<Cell<u32>>,
    on_attention_changed: Rc<RefCell<Option<Rc<dyn Fn(u32)>>>>,
    /// Find-or-create a conversation titled for the topic. Returns true when an
    /// existing transcript was resumed (skip dumping a fresh kickoff).
    open_topic_session: Rc<RefCell<Option<Rc<dyn Fn(String) -> bool>>>>,
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

    /// Open/create a Chat conversation named for this topic, then prefill discuss.
    pub fn seed_discuss_topic(&self, topic: DiscussTopic, kickoff: &str) {
        let title = topic.session_title();
        let resumed = self
            .open_topic_session
            .borrow()
            .as_ref()
            .map(|open| open(title))
            .unwrap_or(false);
        *self.active_discuss.borrow_mut() = Some(topic);
        self.refresh_banner();
        if resumed {
            // Continuing the topic thread — don't paste kickoff into an old chat.
            self.input.clear();
            self.input.grab_focus();
            return;
        }
        let body = if kickoff.trim().is_empty() {
            String::new()
        } else if kickoff.ends_with('\n') {
            kickoff.to_owned()
        } else {
            format!("{kickoff}\n\n")
        };
        self.input.set_text(&body);
        self.input.place_cursor_end();
        self.input.grab_focus();
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

    pub fn attention_count(&self) -> u32 {
        self.attention.get()
    }

    pub fn set_on_attention_changed(&self, handler: Rc<dyn Fn(u32)>) {
        *self.on_attention_changed.borrow_mut() = Some(handler);
        if let Some(cb) = self.on_attention_changed.borrow().as_ref() {
            cb(self.attention.get());
        }
    }

    fn set_open_topic_session(&self, handler: Rc<dyn Fn(String) -> bool>) {
        *self.open_topic_session.borrow_mut() = Some(handler);
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
    /// Normal typed conversation (not voice). Renamed from Talk to avoid mic confusion.
    Chat,
    /// Cursor-like Plan mode: structured proposal this turn (mission-proposal or plan-artifact).
    Plan,
}

#[derive(Clone, Debug)]
struct ProposedTarget {
    title: String,
    target_type: String,
    description: String,
}

#[derive(Clone, Debug)]
struct PendingMissionProposal {
    title: String,
    goal: String,
    summary: String,
    steps: Vec<String>,
    risks: Vec<String>,
    open_questions: Vec<String>,
    related_mission: String,
    mission_id: String,
    target_id: String,
    targets: Vec<ProposedTarget>,
}

#[derive(Clone, Debug)]
struct PendingAttachment {
    path: PathBuf,
    filename: String,
}

#[derive(Clone, Debug)]
struct QueuedFollowUp {
    text: String,
    attachments: Vec<PendingAttachment>,
    plan_mode: bool,
}

const COMPOSER_MIN_HEIGHT: i32 = 88;
const COMPOSER_MAX_HEIGHT: i32 = 220;
const COMPOSER_PLACEHOLDER: &str =
    "Add a follow-up…  ·  Enter to send  ·  Shift+Enter for new line";
const TRANSCRIPT_SPACER_PX: i32 = 112;

/// Multiline Cursor-like composer (TextView + scroll + placeholder overlay).
#[derive(Clone)]
struct ComposerInput {
    view: gtk::TextView,
    scroll: gtk::ScrolledWindow,
    overlay: gtk::Overlay,
    placeholder: gtk::Label,
}

impl ComposerInput {
    fn build() -> Self {
        let view = gtk::TextView::builder()
            .wrap_mode(gtk::WrapMode::WordChar)
            .accepts_tab(false)
            .hexpand(true)
            .vexpand(true)
            .left_margin(12)
            .right_margin(12)
            .top_margin(10)
            .bottom_margin(10)
            .css_classes(["centurion-chat-entry"])
            .can_focus(true)
            .build();

        let scroll = gtk::ScrolledWindow::builder()
            .child(&view)
            .hexpand(true)
            .vexpand(false)
            .min_content_height(COMPOSER_MIN_HEIGHT)
            .max_content_height(COMPOSER_MAX_HEIGHT)
            .propagate_natural_height(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::Automatic)
            .css_classes(["centurion-chat-entry-scroll"])
            .build();
        scroll.set_size_request(-1, COMPOSER_MIN_HEIGHT);

        let placeholder = gtk::Label::builder()
            .label(COMPOSER_PLACEHOLDER)
            .xalign(0.0)
            .yalign(0.0)
            .wrap(true)
            .sensitive(false)
            .can_target(false)
            .css_classes(["centurion-chat-placeholder"])
            .margin_start(14)
            .margin_top(12)
            .margin_end(14)
            .build();

        let overlay = gtk::Overlay::new();
        overlay.set_child(Some(&scroll));
        overlay.add_overlay(&placeholder);
        overlay.set_hexpand(true);

        let composer = Self {
            view,
            scroll,
            overlay,
            placeholder,
        };
        composer.refresh_placeholder();
        composer
    }

    fn root(&self) -> &gtk::Overlay {
        &self.overlay
    }

    fn view(&self) -> &gtk::TextView {
        &self.view
    }

    fn text(&self) -> String {
        let buffer = self.view.buffer();
        let start = buffer.start_iter();
        let end = buffer.end_iter();
        buffer.text(&start, &end, false).to_string()
    }

    fn set_text(&self, text: &str) {
        self.view.buffer().set_text(text);
        self.refresh_placeholder();
        self.update_grow();
    }

    fn clear(&self) {
        self.set_text("");
    }

    fn place_cursor_end(&self) {
        let buffer = self.view.buffer();
        let end = buffer.end_iter();
        buffer.place_cursor(&end);
    }

    fn grab_focus(&self) {
        self.view.grab_focus();
    }

    #[allow(dead_code)]
    fn set_sensitive(&self, sensitive: bool) {
        self.view.set_sensitive(sensitive);
    }

    fn refresh_placeholder(&self) {
        self.placeholder.set_visible(self.text().is_empty());
    }

    fn update_grow(&self) {
        let buffer = self.view.buffer();
        let line_count = buffer.line_count().max(1);
        // ~22px per line + padding; clamp to min/max.
        let desired = (28 + line_count * 22).clamp(COMPOSER_MIN_HEIGHT, COMPOSER_MAX_HEIGHT);
        self.scroll.set_size_request(-1, desired);
        self.scroll.set_min_content_height(desired.min(COMPOSER_MAX_HEIGHT));
    }
}

fn chat_drafts_dir() -> PathBuf {
    let dir = PathBuf::from(resolve_centurion_home()).join("chat_drafts");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn push_attachment_unique(
    attachments: &Rc<RefCell<Vec<PendingAttachment>>>,
    path: PathBuf,
) -> bool {
    let filename = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string());
    let already = attachments.borrow().iter().any(|a| a.path == path);
    if already {
        return false;
    }
    attachments
        .borrow_mut()
        .push(PendingAttachment { path, filename });
    true
}

fn save_clipboard_texture_as_attachment(
    texture: &gdk::Texture,
    attachments: &Rc<RefCell<Vec<PendingAttachment>>>,
) -> bool {
    let bytes = texture.save_to_png_bytes();
    let name = format!(
        "paste-{}.png",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    );
    let path = chat_drafts_dir().join(&name);
    if std::fs::write(&path, bytes.as_ref()).is_err() {
        return false;
    }
    push_attachment_unique(attachments, path)
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
const MISSION_PROPOSAL_FENCE: &str = "mission-proposal";

fn frame_plan_artifact_mode(user_text: &str) -> String {
    format!(
        "[Sovereign AI Brain — Plan mode]\n\
         The user wants a reviewable plan before any consequential action.\n\n\
         For this turn only:\n\
         - Draft a concrete plan. Do not implement, send, edit project files, run mutating commands, or take external actions.\n\
         - Do not call plans put / life_missions put_* to persist this proposal — the Brain UI will save only after the user confirms.\n\
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

fn frame_mission_plan_mode(user_text: &str, topic: &DiscussTopic) -> String {
    let DiscussTopic::Mission {
        statement,
        id,
        title,
        target_id,
        target_title,
        target_type,
        target_description,
        target_status,
        sequence_number,
    } = topic
    else {
        return frame_plan_artifact_mode(user_text);
    };
    let statement = if statement.trim().is_empty() {
        "(not set yet — help them shape one)"
    } else {
        statement.as_str()
    };
    let mission_label = title
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(statement);
    let type_label = match target_type.as_deref().map(str::trim).unwrap_or("") {
        "essential" => "Must Do",
        "shouldHave" => "Should Do",
        "niceToHave" => "Nice to Do",
        other if !other.is_empty() => other,
        _ => "Target",
    };
    let mut target_block = String::new();
    if let Some(t) = target_title.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        target_block.push_str(&format!("Focus target ({type_label}): {t}\n"));
        if let Some(desc) = target_description
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            target_block.push_str(&format!("Target description: {desc}\n"));
        }
        if let Some(st) = target_status
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            target_block.push_str(&format!("Target status: {st}\n"));
        }
        if let Some(n) = sequence_number {
            target_block.push_str(&format!("Sequence #: {n}\n"));
        }
        if let Some(tid) = target_id.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            target_block.push_str(&format!("target_id: {tid}\n"));
        }
    }
    let mission_id_line = id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|mid| format!("mission_id: {mid}\n"))
        .unwrap_or_default();
    let related_mission = id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(mission_label);
    format!(
        "[Sovereign AI Brain — Mission Plan mode]\n\
The user wants a structured proposal for this Life Mission before anything is saved.\n\n\
Mission: {mission_label}\n\
{mission_id_line}Statement:\n\
{statement}\n\
{target_block}\n\
For this turn only:\n\
- Draft a concrete proposal (plan + optional Must/Should/Nice targets). Do not implement or take external actions.\n\
- Do NOT call plans put or life_missions put_* to persist — the Brain shows Save as Plan / Add as targets / Save both / Other / Dismiss chips. Wait for the user.\n\
- Reply briefly in plain language, then end with a fenced JSON block exactly like this:\n\n\
```{MISSION_PROPOSAL_FENCE}\n\
{{\"title\":\"Short proposal title\",\"goal\":\"What success looks like\",\"summary\":\"One or two sentence summary\",\"steps\":[\"Step 1\",\"Step 2\"],\"risks\":[],\"open_questions\":[],\"related_mission\":\"{related_mission}\",\"targets\":[{{\"title\":\"Target title\",\"target_type\":\"essential\",\"description\":\"Optional detail\"}}]}}\n\
```\n\n\
target_type must be essential (Must Do), shouldHave (Should Do), or niceToHave (Nice to Do). Omit empty arrays. Keep steps short.\n\n\
User message:\n\
{user_text}"
    )
}

/// Plan mode framing — preserves Mission discuss context when active.
fn frame_plan_mode(user_text: &str, topic: Option<&DiscussTopic>) -> String {
    match topic {
        Some(t @ DiscussTopic::Mission { .. }) => frame_mission_plan_mode(user_text, t),
        Some(other) => {
            // Keep topic grounding, then ask for a Home Plan artifact.
            let grounded = frame_discuss_outbound(user_text, other);
            frame_plan_artifact_mode(&grounded)
        }
        None => frame_plan_artifact_mode(user_text),
    }
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
Prefer the plans tool (put / decide / complete) to persist changes locally — \
never ask for Portal tokens. If you and the user agree on plan edits, you may \
also end your reply with a fenced JSON block \
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
    let DiscussTopic::Mission {
        statement,
        id,
        title,
        target_id,
        target_title,
        target_type,
        target_description,
        target_status,
        sequence_number,
    } = topic
    else {
        return user_text.to_owned();
    };
    let statement = if statement.trim().is_empty() {
        "(not set yet — help them shape one)"
    } else {
        statement.as_str()
    };
    let mission_label = title
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(statement);
    let type_label = match target_type.as_deref().map(str::trim).unwrap_or("") {
        "essential" => "Must Do",
        "shouldHave" => "Should Do",
        "niceToHave" => "Nice to Do",
        other if !other.is_empty() => other,
        _ => "Target",
    };
    let mut target_block = String::new();
    if let Some(t) = target_title.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        target_block.push_str(&format!("Focus target ({type_label}): {t}\n"));
        if let Some(desc) = target_description
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            target_block.push_str(&format!("Target description: {desc}\n"));
        }
        if let Some(st) = target_status
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            target_block.push_str(&format!("Target status: {st}\n"));
        }
        if let Some(n) = sequence_number {
            target_block.push_str(&format!("Sequence #: {n}\n"));
        }
        if let Some(tid) = target_id.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            target_block.push_str(&format!("target_id: {tid}\n"));
        }
    }
    let mission_id_line = id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|mid| format!("mission_id: {mid}\n"))
        .unwrap_or_default();
    // Life context is injected inside remote_bridge via `life_inject` on the
    // chat request (one round-trip) — do not sync-spawn here on the UI thread.
    format!(
        "[Sovereign AI Brain — Mission discuss]\n\
The user is discussing a Life Mission (direction), not a single reviewable Plan.\n\n\
Mission: {mission_label}\n\
{mission_id_line}Statement:\n\
{statement}\n\
{target_block}\n\
Help them clarify direction and next focus for THIS context. \
When they want to update the mission or this target *and the user clearly asked to save now*, \
use life_missions (put_mission / put_target / set_focus) — local life.db only. \
Never ask for Portal tokens, mc.json, or ctk_proj. \
Use Must Do / Should Do / Nice to Do vocabulary for targets.\n\n\
When you propose a bundle of next steps / new targets / a reviewable plan, do NOT silent-persist. \
End with a ```{MISSION_PROPOSAL_FENCE} JSON fence (title, goal, summary, steps, risks, \
open_questions, related_mission, targets[]) and wait — the Brain shows choice chips \
(Save as Plan / Add as targets / Save both / Other / Dismiss). Do not call plans put \
or put_target for that proposal until the user confirms via those chips.\n\n\
User message:\n\
{user_text}"
    )
}

/// Build optional `life_inject` payload for Mission Discuss (handled in Python).
fn life_inject_for_topic(user_text: &str, topic: &DiscussTopic) -> Option<Value> {
    let DiscussTopic::Mission {
        id,
        target_id,
        ..
    } = topic
    else {
        return None;
    };
    let mut inject = serde_json::json!({ "message": user_text });
    if id.is_some() || target_id.is_some() {
        inject["current_view"] = serde_json::json!({
            "mission_id": id,
            "target_id": target_id,
        });
    }
    Some(inject)
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
    strip_fenced_block(response, PLAN_ARTIFACT_FENCE)
}

fn extract_fenced_block(response: &str, fence: &str) -> Option<String> {
    let open = format!("```{fence}");
    let start = response.find(&open)?;
    let after = &response[start + open.len()..];
    let close = after.find("```")?;
    Some(after[..close].trim().to_owned())
}

fn strip_fenced_block(response: &str, fence: &str) -> String {
    let open = format!("```{fence}");
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

fn strip_mission_proposal(response: &str) -> String {
    strip_fenced_block(response, MISSION_PROPOSAL_FENCE)
}

fn strip_proposal_fences(response: &str) -> String {
    let mut out = strip_mission_proposal(response);
    out = strip_plan_artifact(&out);
    out
}

fn string_list_from_json(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|s| s.as_str().map(|t| t.trim().to_owned()))
        .filter(|s| !s.is_empty())
        .collect()
}

fn normalize_target_type(raw: &str) -> String {
    match raw.trim() {
        "essential" | "must" | "mustDo" | "Must Do" | "must_do" => "essential".to_owned(),
        "shouldHave" | "should" | "shouldDo" | "Should Do" | "should_do" => {
            "shouldHave".to_owned()
        }
        "niceToHave" | "nice" | "niceDo" | "Nice to Do" | "nice_to_have" => {
            "niceToHave".to_owned()
        }
        other if !other.is_empty() => other.to_owned(),
        _ => "shouldHave".to_owned(),
    }
}

fn mission_proposal_from_json(
    value: &Value,
    topic: Option<&DiscussTopic>,
) -> Option<PendingMissionProposal> {
    let obj = value.as_object()?;
    let title = obj
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_owned();
    let goal = obj
        .get("goal")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_owned();
    let summary = obj
        .get("summary")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_owned();
    let steps = string_list_from_json(obj.get("steps"));
    let risks = string_list_from_json(obj.get("risks"));
    let open_questions = string_list_from_json(obj.get("open_questions"));
    let mut targets: Vec<ProposedTarget> = obj
        .get("targets")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item| {
            let t = item.as_object()?;
            let title = t
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_owned();
            if title.is_empty() {
                return None;
            }
            Some(ProposedTarget {
                title,
                target_type: normalize_target_type(
                    t.get("target_type")
                        .or_else(|| t.get("type"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("shouldHave"),
                ),
                description: t
                    .get("description")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_owned(),
            })
        })
        .collect();
    if targets.is_empty() && !steps.is_empty() {
        targets = steps
            .iter()
            .take(6)
            .map(|step| ProposedTarget {
                title: step.clone(),
                target_type: "shouldHave".to_owned(),
                description: String::new(),
            })
            .collect();
    }
    let (mission_id, mission_title, target_id) = match topic {
        Some(DiscussTopic::Mission {
            id,
            title: mt,
            statement,
            target_id,
            ..
        }) => (
            id.clone().unwrap_or_default(),
            mt.clone()
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| statement.clone()),
            target_id.clone().unwrap_or_default(),
        ),
        _ => (String::new(), String::new(), String::new()),
    };
    let related = obj
        .get("related_mission")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_owned();
    let related_mission = if !related.is_empty() {
        related
    } else if !mission_title.is_empty() {
        mission_title
    } else if !mission_id.is_empty() {
        mission_id.clone()
    } else {
        String::new()
    };
    let resolved_title = if !title.is_empty() {
        title
    } else if !goal.is_empty() {
        goal.chars().take(72).collect()
    } else if !steps.is_empty() {
        steps[0].chars().take(72).collect()
    } else {
        "Mission proposal".to_owned()
    };
    if resolved_title.is_empty() && steps.is_empty() && targets.is_empty() {
        return None;
    }
    Some(PendingMissionProposal {
        title: resolved_title,
        goal: goal.clone(),
        summary: if summary.is_empty() {
            goal
        } else {
            summary
        },
        steps,
        risks,
        open_questions,
        related_mission,
        mission_id,
        target_id,
        targets,
    })
}

fn parse_mission_proposal(
    response: &str,
    topic: Option<&DiscussTopic>,
) -> Option<PendingMissionProposal> {
    if let Some(block) = extract_fenced_block(response, MISSION_PROPOSAL_FENCE) {
        if let Ok(value) = serde_json::from_str::<Value>(&block) {
            if let Some(p) = mission_proposal_from_json(&value, topic) {
                return Some(p);
            }
        }
    }
    // Plan-mode fallback: treat plan-artifact as a mission proposal when discussing a mission.
    if matches!(topic, Some(DiscussTopic::Mission { .. })) {
        if let Some(block) = extract_plan_artifact_block(response) {
            if let Ok(value) = serde_json::from_str::<Value>(&block) {
                return mission_proposal_from_json(&value, topic);
            }
        }
    }
    None
}

fn proposal_to_plan_value(proposal: &PendingMissionProposal) -> Value {
    serde_json::json!({
        "title": proposal.title,
        "goal": proposal.goal,
        "summary": if proposal.summary.is_empty() { &proposal.goal } else { &proposal.summary },
        "steps": proposal.steps,
        "risks": proposal.risks,
        "open_questions": proposal.open_questions,
        "related_mission": if proposal.related_mission.is_empty() {
            Value::Null
        } else {
            Value::String(proposal.related_mission.clone())
        },
        "status": "pending_review",
    })
}

fn put_life_target(
    mission_id: &str,
    title: &str,
    description: &str,
    target_type: &str,
) -> Result<(), String> {
    if mission_id.trim().is_empty() {
        return Err(
            "This mission has no id yet — open Mission Deck and save the mission first.".to_owned(),
        );
    }
    let response = run_bridge_action(
        "life_target_put",
        serde_json::json!({
            "target": {
                "mission_id": mission_id,
                "title": title,
                "description": description,
                "target_type": target_type,
                "status": "not_started",
            }
        }),
    )
    .ok_or_else(|| "Could not save the target.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not save the target.")
            .to_owned())
    }
}

fn post_mission_thought(mission_id: &str, target_id: &str, summary: &str, detail: &str) {
    if mission_id.trim().is_empty() || summary.trim().is_empty() {
        return;
    }
    let mut payload = serde_json::json!({
        "thought": {
            "mission_id": mission_id,
            "summary": summary,
            "detail": detail,
            "activity_type": "thought",
        }
    });
    if !target_id.trim().is_empty() {
        payload["thought"]["target_id"] = Value::String(target_id.to_owned());
    }
    let _ = run_bridge_action("life_thought_post", payload);
}

fn persist_proposal_as_plan(proposal: &PendingMissionProposal) -> Result<(), String> {
    put_plan_artifact(proposal_to_plan_value(proposal)).map(|_| ())
}

fn persist_proposal_as_targets(proposal: &PendingMissionProposal) -> Result<usize, String> {
    if proposal.targets.is_empty() {
        return Err("No targets in this proposal.".to_owned());
    }
    let mut saved = 0usize;
    for t in &proposal.targets {
        put_life_target(
            &proposal.mission_id,
            &t.title,
            &t.description,
            &t.target_type,
        )?;
        saved += 1;
    }
    Ok(saved)
}

fn run_provider_cli_json(args: &[&str]) -> Option<Value> {
    let rest: Vec<&str> = args.iter().copied().filter(|a| *a != "--json").collect();
    let mut command_args = vec!["provider", "--json"];
    command_args.extend_from_slice(&rest);
    let mut command = Command::new(resolve_centurion_cli());
    configure_bridge_command(&mut command);
    let output = command.args(command_args).output().ok()?;
    serde_json::from_slice(&output.stdout).ok()
}

fn provider_status_label() -> String {
    let Some(response) = run_provider_cli_json(&["status", "--skip-probe"]) else {
        return "Model…".to_owned();
    };
    let Some(status) = response.get("status") else {
        return "Model…".to_owned();
    };
    let model = status
        .get("model")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let provider = status
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if !model.is_empty() {
        let short = model.split('/').next_back().unwrap_or(model);
        if !provider.is_empty() && provider != short {
            return format!("{provider} · {short}");
        }
        return short.to_owned();
    }
    if !provider.is_empty() {
        return provider.to_owned();
    }
    "Model…".to_owned()
}

fn provider_catalog_connectors() -> Vec<(String, String, bool)> {
    let Some(response) = run_provider_cli_json(&["catalog"]) else {
        return Vec::new();
    };
    let Some(rows) = response
        .get("catalog")
        .and_then(|c| c.get("text_models"))
        .and_then(|v| v.as_array())
        .cloned()
    else {
        return Vec::new();
    };
    rows.into_iter()
        .filter_map(|row| {
            let id = row.get("id")?.as_str()?.to_owned();
            let display = row
                .get("display_name")
                .and_then(|v| v.as_str())
                .unwrap_or(id.as_str())
                .to_owned();
            let needs_key = row
                .get("needs_key")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            Some((id, display, needs_key))
        })
        .collect()
}

fn apply_provider_connector(connector_id: &str) -> Result<(), String> {
    let response = run_provider_cli_json(&["apply-connector", connector_id])
        .ok_or_else(|| "Could not reach the provider CLI.".to_owned())?;
    if response.get("ok").and_then(|v| v.as_bool()) == Some(true) {
        Ok(())
    } else {
        Err(response
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Could not switch model.")
            .to_owned())
    }
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

fn create_named_session(title: &str, previous_session_id: Option<&str>) -> Result<String, String> {
    let mut payload = serde_json::json!({ "title": title });
    if let Some(prev) = previous_session_id.map(str::trim).filter(|s| !s.is_empty()) {
        payload["previous_session_id"] = serde_json::json!(prev);
    }
    let response = run_bridge_json("session_new", payload)?;
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

fn find_session_by_title(title: &str) -> Option<SessionSummary> {
    let needle = title.trim();
    if needle.is_empty() {
        return None;
    }
    list_sessions_including_empty()
        .into_iter()
        .find(|s| s.title.trim().eq_ignore_ascii_case(needle))
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
            Some(ChatMessage { role, content, activity: None })
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
    list_sessions_filtered(false)
}

/// Include zero-message sessions so Discuss find-or-create can reuse a titled
/// thread that was opened but not yet sent to.
fn list_sessions_including_empty() -> Vec<SessionSummary> {
    list_sessions_filtered(true)
}

fn list_sessions_filtered(include_empty: bool) -> Vec<SessionSummary> {
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
            // Hide brand-new empty sessions in the sidebar. Discuss matching still
            // needs them so we don't open duplicates before the first send.
            let message_count = row
                .get("message_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            if !include_empty && message_count == 0 {
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
                message_count,
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
    life_inject: Option<Value>,
    event_tx: mpsc::Sender<WorkerEvent>,
    approval_rx: mpsc::Receiver<ApprovalDecision>,
    cancel: Arc<AtomicBool>,
) {
    use std::io::{BufRead, BufReader, Write};
    use std::net::Shutdown;

    let mut payload = serde_json::json!({
        "id": "desktop-chat",
        "action": "chat",
        "text": text,
        "session_id": session_id,
        "events": true,
    });
    if let Some(inject) = life_inject {
        payload["life_inject"] = inject;
    }
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

    let mut stream = match crate::bridge_client::connect_bridge() {
        Ok(stream) => stream,
        Err(e) => {
            let _ = event_tx.send(WorkerEvent::Done(Err(e)));
            return;
        }
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(200)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(30)));
    if let Err(e) = stream.write_all(&line).and_then(|_| stream.flush()) {
        let _ = event_tx.send(WorkerEvent::Done(Err(format!("Could not send message: {e}"))));
        return;
    }

    let reader_stream = match stream.try_clone() {
        Ok(s) => s,
        Err(e) => {
            let _ = event_tx.send(WorkerEvent::Done(Err(format!(
                "Centurion chat bridge clone failed: {e}"
            ))));
            return;
        }
    };
    let mut reader = BufReader::new(reader_stream);
    let mut final_response: Option<Value> = None;
    let mut buf = String::new();

    loop {
        if cancel.load(Ordering::SeqCst) {
            let _ = stream.shutdown(Shutdown::Both);
            let _ = event_tx.send(WorkerEvent::Done(Err("Stopped.".to_owned())));
            return;
        }
        while let Ok(decision) = approval_rx.try_recv() {
            let payload = serde_json::json!({
                "action": "approval_respond",
                "session_key": decision.session_key,
                "choice": decision.choice,
            });
            if let Ok(mut bytes) = serde_json::to_vec(&payload) {
                bytes.push(b'\n');
                let _ = stream.write_all(&bytes);
                let _ = stream.flush();
            }
        }

        buf.clear();
        match reader.read_line(&mut buf) {
            Ok(0) => break,
            Ok(_) => {}
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                continue;
            }
            Err(_) => break,
        }
        let trimmed = buf.trim();
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
            match approval_rx.recv_timeout(Duration::from_secs(600)) {
                Ok(decision) => {
                    let payload = serde_json::json!({
                        "action": "approval_respond",
                        "session_key": decision.session_key,
                        "choice": decision.choice,
                    });
                    if let Ok(mut bytes) = serde_json::to_vec(&payload) {
                        bytes.push(b'\n');
                        let _ = stream.write_all(&bytes);
                        let _ = stream.flush();
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
                        let _ = stream.write_all(&bytes);
                        let _ = stream.flush();
                    }
                }
            }
            continue;
        }
        if !event_name.is_empty() {
            continue;
        }
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

    let _ = stream.shutdown(Shutdown::Both);

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

fn humanize_tool_name(tool: &str) -> String {
    let t = tool.trim();
    if t.is_empty() {
        return "Tool".to_owned();
    }
    match t {
        "terminal" | "run_terminal_cmd" | "Shell" => "Terminal".to_owned(),
        "read_file" | "Read" => "Read file".to_owned(),
        "write_file" | "Write" | "patch" | "StrReplace" => "Edit file".to_owned(),
        "web_search" | "WebSearch" | "search_files" => "Search".to_owned(),
        "browser_navigate" => "Browse".to_owned(),
        "delegate_task" => "Delegate".to_owned(),
        other => {
            let pretty = other.replace('_', " ");
            let mut chars = pretty.chars();
            match chars.next() {
                Some(c) => format!("{}{}", c.to_uppercase(), chars.as_str()),
                None => "Tool".to_owned(),
            }
        }
    }
}

fn humanize_activity_title(tool: &str, line: &str) -> String {
    let tool_l = tool.to_lowercase();
    let line_l = line.to_lowercase();
    if tool_l.contains("terminal") || line_l.contains("terminal") || line.starts_with("$") {
        return "Running terminal…".to_owned();
    }
    if tool_l.contains("search") || line_l.contains("search") || line_l.contains("grep") {
        return "Searching…".to_owned();
    }
    if tool_l.contains("read") || line_l.starts_with("read") {
        return "Reading…".to_owned();
    }
    if tool_l.contains("write") || tool_l.contains("patch") || line_l.contains("edit") {
        return "Editing…".to_owned();
    }
    if tool_l.contains("web") || tool_l.contains("browser") {
        return "Browsing…".to_owned();
    }
    if !tool.trim().is_empty() {
        return format!("{}…", humanize_tool_name(tool));
    }
    "Working…".to_owned()
}

fn build_tool_card(title: &str, detail: &str) -> gtk::Box {
    let card = gtk::Box::new(gtk::Orientation::Vertical, 2);
    card.add_css_class("centurion-chat-tool-card");
    let header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    header.append(
        &gtk::Image::from_icon_name("utilities-terminal-symbolic"),
    );
    let title_label = gtk::Label::builder()
        .label(title)
        .xalign(0.0)
        .hexpand(true)
        .css_classes(["centurion-chat-tool-card-title"])
        .ellipsize(gtk::pango::EllipsizeMode::End)
        .build();
    header.append(&title_label);
    card.append(&header);
    let body_text = detail.trim();
    if !body_text.is_empty() && body_text != title {
        let preview: String = body_text.chars().take(600).collect();
        let expander = gtk::Expander::builder()
            .label("Output")
            .expanded(false)
            .build();
        let body = gtk::Label::builder()
            .label(&preview)
            .wrap(true)
            .wrap_mode(gtk::pango::WrapMode::Char)
            .xalign(0.0)
            .selectable(true)
            .css_classes(["centurion-chat-tool-card-body"])
            .build();
        expander.set_child(Some(&body));
        card.append(&expander);
    }
    card
}

fn build_archived_activity_widget(archive: &ActivityArchive) -> gtk::Box {
    let card = gtk::Box::new(gtk::Orientation::Vertical, 6);
    card.add_css_class("centurion-chat-activity");
    card.set_hexpand(true);
    card.append(
        &gtk::Label::builder()
            .label(&archive.summary)
            .xalign(0.0)
            .css_classes(["caption-heading"])
            .build(),
    );
    if !archive.thinking.trim().is_empty() {
        let thinking_label = gtk::Label::builder()
            .label(archive.thinking.trim())
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .selectable(true)
            .build();
        let expander = gtk::Expander::builder()
            .label("Thought briefly")
            .expanded(false)
            .build();
        expander.set_child(Some(&thinking_label));
        card.append(&expander);
    }
    for line in &archive.tool_lines {
        let title = line.lines().next().unwrap_or(line.as_str());
        let detail = if line.len() > title.len() {
            line[title.len()..].trim_start_matches('\n')
        } else {
            ""
        };
        card.append(&build_tool_card(title, detail));
    }
    card
}

fn message_row(
    message: &ChatMessage,
    assistant_name: &str,
    actions: Option<MessageRowActions>,
) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.set_activatable(false);
    row.set_selectable(false);

    let outer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    outer.set_margin_top(4);
    outer.set_margin_bottom(4);
    outer.set_hexpand(true);

    let bubble = gtk::Box::new(gtk::Orientation::Vertical, 6);
    // Size to content, not the full window — Cursor-like readable column.
    bubble.set_hexpand(false);
    bubble.add_css_class("centurion-chat-bubble");

    if let Some(archive) = message.activity.as_ref() {
        bubble.set_halign(gtk::Align::Fill);
        bubble.set_hexpand(true);
        bubble.append(&build_archived_activity_widget(archive));
        outer.append(&bubble);
        row.set_child(Some(&outer));
        return row;
    }

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
            || message.content.starts_with("Thought")
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

    bubble.append(&formatted_message_body(&message.content));

    if message.role == ChatRole::Assistant {
        if let Some(actions) = actions {
            let action_row = gtk::Box::new(gtk::Orientation::Horizontal, 4);
            action_row.add_css_class("centurion-chat-msg-actions");
            action_row.set_halign(gtk::Align::Start);
            let copy_btn = gtk::Button::from_icon_name("edit-copy-symbolic");
            copy_btn.add_css_class("flat");
            copy_btn.set_tooltip_text(Some("Copy message"));
            let content = message.content.clone();
            copy_btn.connect_clicked(move |btn| {
                btn.clipboard().set_text(&content);
            });
            action_row.append(&copy_btn);
            if let Some(on_regen) = actions.on_regenerate {
                let regen = gtk::Button::from_icon_name("view-refresh-symbolic");
                regen.add_css_class("flat");
                regen.set_tooltip_text(Some("Regenerate"));
                regen.connect_clicked(move |_| on_regen());
                action_row.append(&regen);
            }
            bubble.append(&action_row);
        }
    }

    match message.role {
        ChatRole::User => {
            bubble.set_halign(gtk::Align::End);
            bubble.add_css_class("centurion-chat-user");
            let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            spacer.set_hexpand(true);
            outer.append(&spacer);
            outer.append(&bubble);
        }
        ChatRole::Assistant => {
            bubble.set_halign(gtk::Align::Start);
            bubble.add_css_class("centurion-chat-bot");
            outer.append(&bubble);
            let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            spacer.set_hexpand(true);
            outer.append(&spacer);
        }
        ChatRole::System => {
            bubble.set_halign(gtk::Align::Fill);
            bubble.set_hexpand(true);
            bubble.add_css_class("centurion-chat-system");
            outer.append(&bubble);
        }
    }

    row.set_child(Some(&outer));
    row
}

#[derive(Clone)]
struct MessageRowActions {
    on_regenerate: Option<Rc<dyn Fn()>>,
}

fn pango_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// Turn markdown into a human-friendly GTK widget tree (not raw `**` / `##` / fences).
fn formatted_message_body(markdown: &str) -> gtk::Box {
    use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};

    let body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    body.set_hexpand(false);

    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);
    let parser = Parser::new_ext(markdown, options);

    let mut blocks: Vec<MessageBlock> = Vec::new();
    let mut inline = String::new();
    let mut list_depth: usize = 0;
    let mut list_ordered: Vec<bool> = Vec::new();
    let mut list_index: Vec<u32> = Vec::new();
    let mut in_code_block = false;
    let mut code_lang = String::new();
    let mut code_buf = String::new();
    let mut heading_level: Option<u8> = None;

    let flush_inline = |inline: &mut String, blocks: &mut Vec<MessageBlock>, heading: Option<u8>| {
        let trimmed = inline.trim_end();
        if trimmed.is_empty() {
            inline.clear();
            return;
        }
        blocks.push(MessageBlock::Paragraph {
            markup: trimmed.to_string(),
            heading,
        });
        inline.clear();
    };

    for event in parser {
        match event {
            Event::Start(Tag::Paragraph) => {}
            Event::End(TagEnd::Paragraph) => {
                flush_inline(&mut inline, &mut blocks, None);
            }
            Event::Start(Tag::Heading { level, .. }) => {
                flush_inline(&mut inline, &mut blocks, None);
                heading_level = Some(match level {
                    HeadingLevel::H1 => 1,
                    HeadingLevel::H2 => 2,
                    HeadingLevel::H3 => 3,
                    HeadingLevel::H4 => 4,
                    HeadingLevel::H5 => 5,
                    HeadingLevel::H6 => 6,
                });
            }
            Event::End(TagEnd::Heading(_)) => {
                let level = heading_level.take();
                flush_inline(&mut inline, &mut blocks, level);
            }
            Event::Start(Tag::List(start)) => {
                flush_inline(&mut inline, &mut blocks, None);
                list_depth += 1;
                list_ordered.push(start.is_some());
                list_index.push(start.unwrap_or(1) as u32);
            }
            Event::End(TagEnd::List(_)) => {
                flush_inline(&mut inline, &mut blocks, None);
                list_depth = list_depth.saturating_sub(1);
                list_ordered.pop();
                list_index.pop();
            }
            Event::Start(Tag::Item) => {
                flush_inline(&mut inline, &mut blocks, None);
                let indent = "  ".repeat(list_depth.saturating_sub(1));
                let bullet = if list_ordered.last().copied().unwrap_or(false) {
                    let n = list_index.last().copied().unwrap_or(1);
                    if let Some(idx) = list_index.last_mut() {
                        *idx += 1;
                    }
                    format!("{n}. ")
                } else {
                    "• ".to_owned()
                };
                inline.push_str(&indent);
                inline.push_str(&bullet);
            }
            Event::End(TagEnd::Item) => {
                flush_inline(&mut inline, &mut blocks, None);
            }
            Event::Start(Tag::CodeBlock(kind)) => {
                flush_inline(&mut inline, &mut blocks, None);
                in_code_block = true;
                code_buf.clear();
                code_lang = match kind {
                    CodeBlockKind::Fenced(lang) => lang.to_string(),
                    CodeBlockKind::Indented => String::new(),
                };
            }
            Event::End(TagEnd::CodeBlock) => {
                in_code_block = false;
                let code = code_buf.trim_end_matches('\n').to_string();
                blocks.push(MessageBlock::Code {
                    text: code,
                    lang: code_lang.clone(),
                });
                code_buf.clear();
                code_lang.clear();
            }
            Event::Start(Tag::Emphasis) => inline.push_str("<i>"),
            Event::End(TagEnd::Emphasis) => inline.push_str("</i>"),
            Event::Start(Tag::Strong) => inline.push_str("<b>"),
            Event::End(TagEnd::Strong) => inline.push_str("</b>"),
            Event::Start(Tag::Strikethrough) => inline.push_str("<s>"),
            Event::End(TagEnd::Strikethrough) => inline.push_str("</s>"),
            Event::Start(Tag::Link { dest_url, .. }) => {
                inline.push_str("<span foreground=\"#ffb347\"><u>");
                // Keep URL for title attribute via comment in markup — show as text after.
                let _ = dest_url;
            }
            Event::End(TagEnd::Link) => inline.push_str("</u></span>"),
            Event::Code(code) => {
                inline.push_str("<tt>");
                inline.push_str(&pango_escape(&code));
                inline.push_str("</tt>");
            }
            Event::Text(text) => {
                if in_code_block {
                    code_buf.push_str(&text);
                } else {
                    inline.push_str(&pango_escape(&text));
                }
            }
            Event::SoftBreak => {
                if in_code_block {
                    code_buf.push('\n');
                } else {
                    inline.push(' ');
                }
            }
            Event::HardBreak => {
                if in_code_block {
                    code_buf.push('\n');
                } else {
                    inline.push('\n');
                }
            }
            Event::Rule => {
                flush_inline(&mut inline, &mut blocks, None);
                blocks.push(MessageBlock::Rule);
            }
            Event::TaskListMarker(checked) => {
                inline.push_str(if checked { "☑ " } else { "☐ " });
            }
            _ => {}
        }
    }
    flush_inline(&mut inline, &mut blocks, None);

    if blocks.is_empty() {
        // Plain fallback (no markdown structure detected).
        body.append(&chat_text_label(
            &pango_escape(markdown.trim()),
            false,
            None,
        ));
        return body;
    }

    for block in blocks {
        match block {
            MessageBlock::Paragraph { markup, heading } => {
                body.append(&chat_text_label(&markup, false, heading));
            }
            MessageBlock::Code { text, lang } => {
                let block = gtk::Box::new(gtk::Orientation::Vertical, 0);
                block.add_css_class("centurion-chat-code-block");
                let header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                header.add_css_class("centurion-chat-code-header");
                let lang_label = if lang.is_empty() {
                    "code".to_owned()
                } else {
                    lang
                };
                header.append(
                    &gtk::Label::builder()
                        .label(&lang_label)
                        .xalign(0.0)
                        .hexpand(true)
                        .css_classes(["caption", "dim-label", "centurion-chat-code-lang"])
                        .build(),
                );
                let copy_btn = gtk::Button::with_label("Copy");
                copy_btn.add_css_class("flat");
                copy_btn.set_tooltip_text(Some("Copy code"));
                let code_for_copy = text.clone();
                copy_btn.connect_clicked(move |btn| {
                    btn.clipboard().set_text(&code_for_copy);
                });
                header.append(&copy_btn);
                block.append(&header);
                let code_label = gtk::Label::builder()
                    .label(&text)
                    .wrap(true)
                    .wrap_mode(gtk::pango::WrapMode::Char)
                    .xalign(0.0)
                    .selectable(true)
                    .max_width_chars(64)
                    .css_classes(["centurion-chat-code"])
                    .build();
                block.append(&code_label);
                body.append(&block);
            }
            MessageBlock::Rule => {
                body.append(
                    &gtk::Separator::builder()
                        .orientation(gtk::Orientation::Horizontal)
                        .build(),
                );
            }
        }
    }

    body
}

enum MessageBlock {
    Paragraph { markup: String, heading: Option<u8> },
    Code { text: String, lang: String },
    Rule,
}

fn chat_text_label(markup: &str, monospace: bool, heading: Option<u8>) -> gtk::Label {
    let final_markup = if let Some(level) = heading {
        let size = match level {
            1 => "large",
            2 => "medium",
            _ => "small",
        };
        format!("<span size=\"{size}\" weight=\"bold\">{markup}</span>")
    } else if monospace {
        format!("<tt>{markup}</tt>")
    } else {
        markup.to_string()
    };

    let mut classes = vec!["centurion-chat-text".to_owned()];
    if monospace {
        classes.push("centurion-chat-code".to_owned());
    }
    if let Some(level) = heading {
        classes.push(format!("centurion-chat-h{level}"));
    }
    let class_refs: Vec<&str> = classes.iter().map(String::as_str).collect();
    gtk::Label::builder()
        .use_markup(true)
        .label(&final_markup)
        .wrap(true)
        .wrap_mode(gtk::pango::WrapMode::WordChar)
        .xalign(0.0)
        .selectable(true)
        .max_width_chars(52)
        .css_classes(class_refs.as_slice())
        .build()
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

    for delay_ms in [16u64, 120] {
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
    transcript_spacer.set_size_request(-1, TRANSCRIPT_SPACER_PX);
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

    // Jump-to-latest when user scrolls up during a run (Cursor escape hatch).
    let jump_latest = gtk::Button::with_label("Jump to latest");
    jump_latest.add_css_class("centurion-chat-jump-latest");
    jump_latest.set_halign(gtk::Align::Center);
    jump_latest.set_valign(gtk::Align::End);
    jump_latest.set_margin_bottom(12);
    jump_latest.set_visible(false);
    let scroll_overlay = gtk::Overlay::new();
    scroll_overlay.set_child(Some(&message_scroll));
    scroll_overlay.add_overlay(&jump_latest);
    scroll_overlay.set_vexpand(true);
    scroll_overlay.set_hexpand(true);
    {
        let follow_bottom = follow_bottom.clone();
        let message_scroll = message_scroll.clone();
        let message_list = message_list.clone();
        let programmatic_scroll = programmatic_scroll.clone();
        let jump_latest = jump_latest.clone();
        jump_latest.connect_clicked(move |btn| {
            follow_bottom.set(true);
            btn.set_visible(false);
            schedule_scroll_to_latest(
                &message_scroll,
                &message_list,
                &follow_bottom,
                &programmatic_scroll,
            );
        });
    }
    {
        let jump_latest = jump_latest.clone();
        let follow_bottom = follow_bottom.clone();
        let adj = message_scroll.vadjustment();
        adj.connect_value_changed(move |_| {
            jump_latest.set_visible(!follow_bottom.get());
        });
    }
    // Stick-to-bottom is driven by Adjustment::changed / value_changed above.
    // Do not use connect_size_allocate (GTK3) or connect_notify("allocation")
    // + Send wrappers — those break Fedora 44 / glib-rs 0.22 Brain rebuilds.
    chat_column.append(&scroll_overlay);

    let activity_tool_count = Rc::new(Cell::new(0usize));
    let activity_has_thinking = Rc::new(Cell::new(false));
    let activity_thinking_text = Rc::new(RefCell::new(String::new()));
    let activity_tool_lines = Rc::new(RefCell::new(Vec::<String>::new()));

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
        let activity_thinking_text = activity_thinking_text.clone();
        let activity_tool_lines = activity_tool_lines.clone();
        move || {
            clear_activity_box();
            thinking_label.set_label("");
            thinking_expander.set_label(Some("Thinking"));
            thinking_expander.set_visible(false);
            thinking_expander.set_expanded(true);
            activity_title.set_label("Working…");
            activity_tool_count.set(0);
            activity_has_thinking.set(false);
            activity_thinking_text.borrow_mut().clear();
            activity_tool_lines.borrow_mut().clear();
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
        let activity_thinking_text = activity_thinking_text.clone();
        let activity_tool_lines = activity_tool_lines.clone();
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
                    thinking_expander.set_label(Some("Thinking"));
                    thinking_expander.set_visible(true);
                    thinking_expander.set_expanded(true);
                    activity_has_thinking.set(true);
                    *activity_thinking_text.borrow_mut() = text;
                    activity_title.set_label("Thinking…");
                }
                "tool" => {
                    let title = if event.tool.trim().is_empty() {
                        event.line.lines().next().unwrap_or("Tool").to_owned()
                    } else {
                        humanize_tool_name(&event.tool)
                    };
                    let detail = if event.line.is_empty() {
                        event.text.clone()
                    } else {
                        event.line.clone()
                    };
                    let archive_line = if detail.trim().is_empty() || detail == title {
                        title.clone()
                    } else {
                        format!("{title}\n{detail}")
                    };
                    activity_tool_lines.borrow_mut().push(archive_line);
                    activity_tools.append(&build_tool_card(&title, &detail));
                    activity_tool_count.set(activity_tool_count.get().saturating_add(1));
                    activity_title.set_label(&humanize_activity_title(&event.tool, &detail));
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
                    activity_tool_lines.borrow_mut().push(line.clone());
                    activity_tools.append(&build_tool_card("Status", &line));
                    activity_title.set_label("Working…");
                }
            }
            if follow_bottom.get() {
                schedule_scroll_to_latest(
                    &message_scroll,
                    &message_list,
                    &follow_bottom,
                    &programmatic_scroll,
                );
            }
        }
    });

    // Freeze the live activity card on Done so thinking stays readable in the
    // scroll surface until the next turn replaces it (show_activity_working).
    // Also return an ActivityArchive for persisting into the message stream.
    let finish_activity_summary: Rc<dyn Fn() -> Option<ActivityArchive>> = Rc::new({
        let activity_card = activity_card.clone();
        let activity_title = activity_title.clone();
        let thinking_expander = thinking_expander.clone();
        let activity_tool_count = activity_tool_count.clone();
        let activity_has_thinking = activity_has_thinking.clone();
        let activity_thinking_text = activity_thinking_text.clone();
        let activity_tool_lines = activity_tool_lines.clone();
        move || {
            let tools = activity_tool_count.get();
            let thinking = activity_has_thinking.get();
            if tools == 0 && !thinking {
                activity_card.set_visible(false);
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
            let summary = format!("Worked with {}.", parts.join(" · "));
            activity_title.set_label(&summary);
            if thinking {
                thinking_expander.set_label(Some("Thought briefly"));
                thinking_expander.set_expanded(false);
                thinking_expander.set_visible(true);
            }
            activity_card.set_visible(true);
            Some(ActivityArchive {
                summary,
                thinking: activity_thinking_text.borrow().clone(),
                tool_lines: activity_tool_lines.borrow().clone(),
            })
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
    let approval_heading = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    approval_heading.append(
        &gtk::Label::builder()
            .label("(!)")
            .css_classes(["centurion-attention-mark"])
            .build(),
    );
    let approval_title = gtk::Label::builder()
        .label("Your Sovereign needs approval")
        .css_classes(["title-4"])
        .xalign(0.0)
        .hexpand(true)
        .build();
    approval_heading.append(&approval_title);
    let approval_detail = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .build();
    let approval_buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    approval_box.append(&approval_heading);
    approval_box.append(&approval_detail);
    approval_box.append(&approval_buttons);
    bottom.append(&approval_box);

    // Mission proposal choice chips (Save as Plan / targets / Other / Dismiss).
    let proposal_box = gtk::Box::new(gtk::Orientation::Vertical, 8);
    proposal_box.set_margin_start(16);
    proposal_box.set_margin_end(16);
    proposal_box.set_margin_top(8);
    proposal_box.set_margin_bottom(4);
    proposal_box.set_visible(false);
    proposal_box.add_css_class("centurion-chat-approval");
    let proposal_title = gtk::Label::builder()
        .label("Save this proposal?")
        .css_classes(["title-4"])
        .xalign(0.0)
        .wrap(true)
        .build();
    let proposal_detail = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .css_classes(["dim-label"])
        .build();
    let proposal_buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    proposal_buttons.set_homogeneous(false);
    proposal_box.append(&proposal_title);
    proposal_box.append(&proposal_detail);
    proposal_box.append(&proposal_buttons);
    bottom.append(&proposal_box);

    let pending_proposal: Rc<RefCell<Option<PendingMissionProposal>>> =
        Rc::new(RefCell::new(None));
    let keep_proposal_context: Rc<Cell<bool>> = Rc::new(Cell::new(false));

    let clear_proposal_ui: Rc<dyn Fn()> = Rc::new({
        let proposal_box = proposal_box.clone();
        let proposal_buttons = proposal_buttons.clone();
        let proposal_detail = proposal_detail.clone();
        move || {
            while let Some(child) = proposal_buttons.first_child() {
                proposal_buttons.remove(&child);
            }
            proposal_detail.set_label("");
            proposal_box.set_visible(false);
        }
    });

    let clear_pending_proposal: Rc<dyn Fn()> = Rc::new({
        let pending_proposal = pending_proposal.clone();
        let keep_proposal_context = keep_proposal_context.clone();
        let clear_proposal_ui = clear_proposal_ui.clone();
        move || {
            *pending_proposal.borrow_mut() = None;
            keep_proposal_context.set(false);
            clear_proposal_ui();
        }
    });

    // Filled after composer + refresh_messages / set_error exist.
    let show_proposal_choices: Rc<RefCell<Option<Rc<dyn Fn(PendingMissionProposal)>>>> =
        Rc::new(RefCell::new(None));

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

    // Cursor-like chrome: queue strip → chips → input → toolbar (mode · model · attach · send).
    let intent = Rc::new(Cell::new(ChatIntent::Chat));
    let message_queue: Rc<RefCell<Vec<QueuedFollowUp>>> = Rc::new(RefCell::new(Vec::new()));

    let queue_strip = gtk::Box::new(gtk::Orientation::Vertical, 6);
    queue_strip.set_margin_start(0);
    queue_strip.set_margin_end(0);
    queue_strip.set_visible(false);
    queue_strip.add_css_class("centurion-chat-queue-strip");
    let queue_header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let queue_label = gtk::Label::builder()
        .label("Queued")
        .xalign(0.0)
        .hexpand(true)
        .css_classes(["caption-heading"])
        .build();
    let strip_stop = gtk::Button::with_label("Stop");
    strip_stop.add_css_class("centurion-chat-stop");
    strip_stop.set_tooltip_text(Some("Stop this turn"));
    strip_stop.set_visible(false);
    queue_header.append(&queue_label);
    queue_header.append(&strip_stop);
    let queue_items = gtk::Box::new(gtk::Orientation::Vertical, 4);
    queue_strip.append(&queue_header);
    queue_strip.append(&queue_items);
    bottom.append(&queue_strip);

    let mode_btn = gtk::MenuButton::builder()
        .label("Chat")
        .css_classes(["centurion-chat-pill"])
        .tooltip_text("Chat = typed conversation. Plan = ask for a structured proposal this turn. (Not voice.)")
        .halign(gtk::Align::Start)
        .build();
    {
        let popover = gtk::Popover::new();
        let list = gtk::Box::new(gtk::Orientation::Vertical, 4);
        list.set_margin_start(8);
        list.set_margin_end(8);
        list.set_margin_top(8);
        list.set_margin_bottom(8);
        let chat_item = gtk::Button::with_label("Chat — typed conversation");
        chat_item.add_css_class("flat");
        chat_item.set_halign(gtk::Align::Start);
        let plan_item = gtk::Button::with_label("Plan — structured proposal");
        plan_item.add_css_class("flat");
        plan_item.set_halign(gtk::Align::Start);
        {
            let intent = intent.clone();
            let mode_btn = mode_btn.clone();
            let popover = popover.clone();
            chat_item.connect_clicked(move |_| {
                intent.set(ChatIntent::Chat);
                mode_btn.set_label("Chat");
                popover.popdown();
            });
        }
        {
            let intent = intent.clone();
            let mode_btn = mode_btn.clone();
            let popover = popover.clone();
            plan_item.connect_clicked(move |_| {
                intent.set(ChatIntent::Plan);
                mode_btn.set_label("Plan");
                popover.popdown();
            });
        }
        list.append(&chat_item);
        list.append(&plan_item);
        popover.set_child(Some(&list));
        mode_btn.set_popover(Some(&popover));
    }

    let model_btn = gtk::MenuButton::builder()
        .label("Selecting model…")
        .css_classes(["centurion-chat-pill"])
        .tooltip_text("Switch thinking model (same as Settings)")
        .halign(gtk::Align::Start)
        .build();

    let refresh_model_label: Rc<dyn Fn()> = Rc::new({
        let model_btn = model_btn.clone();
        move || {
            let (tx, rx) = mpsc::channel::<String>();
            thread::spawn(move || {
                let _ = tx.send(provider_status_label());
            });
            let model_btn = model_btn.clone();
            glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                Ok(label) => {
                    let shown = if label.trim().is_empty() {
                        "Model…".to_owned()
                    } else {
                        label
                    };
                    model_btn.set_label(&shown);
                    glib::ControlFlow::Break
                }
                Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            });
        }
    });
    refresh_model_label();

    let model_error_slot: Rc<RefCell<Option<Rc<dyn Fn(Option<String>)>>>> =
        Rc::new(RefCell::new(None));
    // Populate model popover asynchronously (catalog + apply).
    {
        let model_btn = model_btn.clone();
        let on_fix_thinking = on_fix_thinking.clone();
        let refresh_model_label = refresh_model_label.clone();
        let model_error_slot = model_error_slot.clone();
        let (tx, rx) = mpsc::channel::<Vec<(String, String, bool)>>();
        thread::spawn(move || {
            let _ = tx.send(provider_catalog_connectors());
        });
        glib::timeout_add_local(Duration::from_millis(80), move || match rx.try_recv() {
            Ok(connectors) => {
                let popover = gtk::Popover::new();
                let list = gtk::Box::new(gtk::Orientation::Vertical, 4);
                list.set_margin_start(8);
                list.set_margin_end(8);
                list.set_margin_top(8);
                list.set_margin_bottom(8);
                if connectors.is_empty() {
                    list.append(
                        &gtk::Label::builder()
                            .label("No models in catalog")
                            .css_classes(["dim-label"])
                            .build(),
                    );
                } else {
                    for (id, display, needs_key) in connectors {
                        let row = gtk::Button::with_label(&display);
                        row.add_css_class("flat");
                        row.set_halign(gtk::Align::Start);
                        let on_fix_thinking = on_fix_thinking.clone();
                        let refresh_model_label = refresh_model_label.clone();
                        let model_error_slot = model_error_slot.clone();
                        let popover_c = popover.clone();
                        let model_btn_c = model_btn.clone();
                        row.connect_clicked(move |_| {
                            popover_c.popdown();
                            model_btn_c.set_label("Switching…");
                            let id = id.clone();
                            let refresh_model_label = refresh_model_label.clone();
                            let model_error_slot = model_error_slot.clone();
                            let on_fix_thinking = on_fix_thinking.clone();
                            let needs_key = needs_key;
                            let (tx, rx) = mpsc::channel::<Result<(), String>>();
                            thread::spawn(move || {
                                let result = apply_provider_connector(&id);
                                let _ = tx.send(result);
                            });
                            glib::timeout_add_local(Duration::from_millis(50), move || {
                                match rx.try_recv() {
                                    Ok(Ok(())) => {
                                        refresh_model_label();
                                        glib::ControlFlow::Break
                                    }
                                    Ok(Err(err)) => {
                                        let lower = err.to_lowercase();
                                        let looks_like_key = needs_key
                                            || lower.contains("key")
                                            || lower.contains("access code")
                                            || lower.contains("credential")
                                            || lower.contains("unauthorized");
                                        if looks_like_key {
                                            if let Some(handler) =
                                                on_fix_thinking.borrow().clone()
                                            {
                                                handler();
                                            }
                                        } else if let Some(set_error) =
                                            model_error_slot.borrow().clone()
                                        {
                                            set_error(Some(err));
                                        }
                                        refresh_model_label();
                                        glib::ControlFlow::Break
                                    }
                                    Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                                    Err(mpsc::TryRecvError::Disconnected) => {
                                        refresh_model_label();
                                        glib::ControlFlow::Break
                                    }
                                }
                            });
                        });
                        list.append(&row);
                    }
                }
                let open_fix = gtk::Button::with_label("More… (access codes)");
                open_fix.add_css_class("flat");
                let on_fix_thinking = on_fix_thinking.clone();
                let popover_c = popover.clone();
                open_fix.connect_clicked(move |_| {
                    popover_c.popdown();
                    if let Some(handler) = on_fix_thinking.borrow().clone() {
                        handler();
                    }
                });
                list.append(&open_fix);
                popover.set_child(Some(&list));
                model_btn.set_popover(Some(&popover));
                glib::ControlFlow::Break
            }
            Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        });
    }

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

    let input = ComposerInput::build();
    let input_wrap = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    input_wrap.set_margin_start(16);
    input_wrap.set_margin_end(16);
    input_wrap.set_margin_top(4);
    input_wrap.set_margin_bottom(4);
    input_wrap.append(input.root());
    bottom.append(&input_wrap);

    let toolbar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    toolbar.add_css_class("centurion-chat-toolbar");
    toolbar.set_margin_start(16);
    toolbar.set_margin_end(16);
    toolbar.set_margin_bottom(14);
    toolbar.set_margin_top(2);

    let attach_button = gtk::Button::from_icon_name("mail-attachment-symbolic");
    attach_button.set_tooltip_text(Some("Attach files · drag & drop · paste image"));
    attach_button.add_css_class("centurion-chat-attach-btn");
    attach_button.set_valign(gtk::Align::Center);
    attach_button.set_size_request(44, 44);

    let send_button = gtk::Button::with_label("Send");
    send_button.add_css_class("suggested-action");
    send_button.set_tooltip_text(Some("Send · Enter"));
    send_button.set_valign(gtk::Align::Center);
    send_button.set_size_request(88, 40);

    let stop_button = gtk::Button::with_label("Stop");
    stop_button.add_css_class("centurion-chat-stop");
    stop_button.set_tooltip_text(Some("Stop this turn"));
    stop_button.set_valign(gtk::Align::Center);
    stop_button.set_size_request(88, 40);
    stop_button.set_visible(false);

    let sending_spinner = gtk::Spinner::new();
    sending_spinner.set_visible(false);
    sending_spinner.set_valign(gtk::Align::Center);

    let toolbar_spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    toolbar_spacer.set_hexpand(true);

    toolbar.append(&mode_btn);
    toolbar.append(&model_btn);
    toolbar.append(&toolbar_spacer);
    toolbar.append(&attach_button);
    toolbar.append(&send_button);
    toolbar.append(&stop_button);
    toolbar.append(&sending_spinner);
    bottom.append(&toolbar);
    chat_column.append(&bottom);

    let refresh_queue_strip_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> =
        Rc::new(RefCell::new(None));
    let refresh_queue_strip: Rc<dyn Fn()> = Rc::new({
        let slot = refresh_queue_strip_slot.clone();
        move || {
            if let Some(refresh) = slot.borrow().clone() {
                refresh();
            }
        }
    });
    *refresh_queue_strip_slot.borrow_mut() = Some(Rc::new({
        let queue_strip = queue_strip.clone();
        let queue_label = queue_label.clone();
        let queue_items = queue_items.clone();
        let message_queue = message_queue.clone();
        let strip_stop = strip_stop.clone();
        let is_sending = is_sending.clone();
        let refresh_queue_strip = refresh_queue_strip.clone();
        move || {
            while let Some(child) = queue_items.first_child() {
                queue_items.remove(&child);
            }
            let items = message_queue.borrow().clone();
            let n = items.len();
            let busy = *is_sending.borrow();
            strip_stop.set_visible(busy);
            if n == 0 {
                queue_label.set_label(if busy { "Working…" } else { "Queued" });
                queue_strip.set_visible(busy);
                return;
            }
            queue_label.set_label(&format!(
                "{} Queued",
                if n == 1 {
                    "1".to_owned()
                } else {
                    n.to_string()
                }
            ));
            for (index, item) in items.iter().enumerate() {
                let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                row.add_css_class("centurion-chat-queue-item");
                let preview = {
                    let t = item.text.trim();
                    let mut s: String = t.chars().take(80).collect();
                    if t.chars().count() > 80 {
                        s.push('…');
                    }
                    if s.is_empty() {
                        format!("{} attachment(s)", item.attachments.len())
                    } else {
                        s
                    }
                };
                row.append(
                    &gtk::Label::builder()
                        .label(&preview)
                        .xalign(0.0)
                        .hexpand(true)
                        .ellipsize(gtk::pango::EllipsizeMode::End)
                        .build(),
                );
                let remove = gtk::Button::from_icon_name("edit-delete-symbolic");
                remove.add_css_class("flat");
                remove.set_tooltip_text(Some("Remove from queue"));
                let message_queue = message_queue.clone();
                let refresh_queue_strip = refresh_queue_strip.clone();
                remove.connect_clicked(move |_| {
                    {
                        let mut q = message_queue.borrow_mut();
                        if index < q.len() {
                            q.remove(index);
                        }
                    }
                    refresh_queue_strip();
                });
                row.append(&remove);
                queue_items.append(&row);
            }
            queue_strip.set_visible(true);
        }
    }));

    let turn_cancel: Rc<RefCell<Option<Arc<AtomicBool>>>> = Rc::new(RefCell::new(None));

    {
        let attachments = attachments.clone();
        let refresh_attachments = refresh_attachments.clone();
        let input = input.clone();
        attach_button.connect_clicked(move |_| {
            let Some(window) = input.view().root().and_downcast::<gtk::Window>() else {
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
                    if push_attachment_unique(&attachments, path) {
                        added = true;
                    }
                }
                if added {
                    refresh_attachments();
                }
            });
        });
    }

    // Drag-and-drop files onto the composer.
    {
        let attachments = attachments.clone();
        let refresh_attachments = refresh_attachments.clone();
        let drop = gtk::DropTarget::new(glib::Type::INVALID, gdk::DragAction::COPY);
        drop.set_types(&[gio::File::static_type(), gdk::FileList::static_type()]);
        drop.connect_drop(move |_, value, _, _| {
            let mut added = false;
            if let Ok(list) = value.get::<gdk::FileList>() {
                for file in list.files() {
                    if let Some(path) = file.path() {
                        if push_attachment_unique(&attachments, path) {
                            added = true;
                        }
                    }
                }
            } else if let Ok(file) = value.get::<gio::File>() {
                if let Some(path) = file.path() {
                    if push_attachment_unique(&attachments, path) {
                        added = true;
                    }
                }
            }
            if added {
                refresh_attachments();
            }
            added
        });
        input.root().add_controller(drop);
    }

    // Placeholder + auto-grow on buffer changes.
    {
        let input = input.clone();
        input.view().buffer().connect_changed(move |_| {
            input.refresh_placeholder();
            input.update_grow();
        });
    }

    paned.set_end_child(Some(&chat_column));
    container.append(&paned);

    let regenerate_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));

    let refresh_messages: Rc<dyn Fn()> = Rc::new({
        let message_list = message_list.clone();
        let messages = messages.clone();
        let message_scroll = message_scroll.clone();
        let assistant_name = assistant_name.clone();
        let title = title.clone();
        let follow_bottom = follow_bottom.clone();
        let programmatic_scroll = programmatic_scroll.clone();
        let regenerate_slot = regenerate_slot.clone();
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
                        activity: None,
                    },
                    &name,
                    None,
                ));
            } else {
                let last_assistant_idx = msgs
                    .iter()
                    .rposition(|m| m.role == ChatRole::Assistant && m.activity.is_none());
                for (idx, message) in msgs.iter().enumerate() {
                    let actions = if Some(idx) == last_assistant_idx {
                        Some(MessageRowActions {
                            on_regenerate: regenerate_slot.borrow().clone(),
                        })
                    } else if message.role == ChatRole::Assistant && message.activity.is_none() {
                        Some(MessageRowActions {
                            on_regenerate: None,
                        })
                    } else {
                        None
                    };
                    message_list.append(&message_row(message, &name, actions));
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
    *model_error_slot.borrow_mut() = Some(set_error.clone());

    // Mission proposal choice chips — wired now that input / messages / set_error exist.
    *show_proposal_choices.borrow_mut() = Some(Rc::new({
        let proposal_box = proposal_box.clone();
        let proposal_title = proposal_title.clone();
        let proposal_detail = proposal_detail.clone();
        let proposal_buttons = proposal_buttons.clone();
        let pending_proposal = pending_proposal.clone();
        let keep_proposal_context = keep_proposal_context.clone();
        let clear_pending_proposal = clear_pending_proposal.clone();
        let clear_proposal_ui = clear_proposal_ui.clone();
        let input = input.clone();
        let messages = messages.clone();
        let refresh_messages = refresh_messages.clone();
        let set_error = set_error.clone();
        let follow_bottom = follow_bottom.clone();
        move |proposal: PendingMissionProposal| {
            while let Some(child) = proposal_buttons.first_child() {
                proposal_buttons.remove(&child);
            }
            keep_proposal_context.set(false);
            *pending_proposal.borrow_mut() = Some(proposal.clone());
            proposal_title.set_label(&format!("Save “{}”?", proposal.title));
            let mut detail_parts = Vec::new();
            if !proposal.summary.is_empty() {
                detail_parts.push(proposal.summary.clone());
            } else if !proposal.goal.is_empty() {
                detail_parts.push(proposal.goal.clone());
            }
            if !proposal.targets.is_empty() {
                detail_parts.push(format!(
                    "{} target{}",
                    proposal.targets.len(),
                    if proposal.targets.len() == 1 {
                        ""
                    } else {
                        "s"
                    }
                ));
            } else if !proposal.steps.is_empty() {
                detail_parts.push(format!(
                    "{} step{}",
                    proposal.steps.len(),
                    if proposal.steps.len() == 1 { "" } else { "s" }
                ));
            }
            proposal_detail.set_label(&detail_parts.join(" · "));

            let choices: &[(&str, &str, bool)] = &[
                ("save_plan", "Save as Plan", false),
                ("add_targets", "Add as targets", false),
                ("save_both", "Save both", false),
                ("other", "Other", false),
                ("dismiss", "Dismiss", true),
            ];
            for (id, label, destructive) in choices {
                let button = gtk::Button::with_label(label);
                if *destructive {
                    button.add_css_class("destructive-action");
                } else if *id == "save_both" || *id == "save_plan" {
                    button.add_css_class("suggested-action");
                } else {
                    button.add_css_class("flat");
                }
                let choice = (*id).to_owned();
                let pending_proposal = pending_proposal.clone();
                let keep_proposal_context = keep_proposal_context.clone();
                let clear_pending_proposal = clear_pending_proposal.clone();
                let clear_proposal_ui = clear_proposal_ui.clone();
                let input = input.clone();
                let messages = messages.clone();
                let refresh_messages = refresh_messages.clone();
                let set_error = set_error.clone();
                let follow_bottom = follow_bottom.clone();
                let proposal_box = proposal_box.clone();
                let proposal_title = proposal_title.clone();
                let proposal_detail = proposal_detail.clone();
                let proposal_buttons = proposal_buttons.clone();
                button.connect_clicked(move |_| {
                    let Some(proposal) = pending_proposal.borrow().clone() else {
                        clear_pending_proposal();
                        return;
                    };
                    match choice.as_str() {
                        "dismiss" => {
                            clear_pending_proposal();
                            messages.borrow_mut().push(ChatMessage {
                                role: ChatRole::System,
                                content: "Proposal dismissed.".to_owned(),
                                activity: None,
                            });
                            follow_bottom.set(true);
                            refresh_messages();
                        }
                        "other" => {
                            keep_proposal_context.set(true);
                            clear_proposal_ui();
                            proposal_title
                                .set_label(&format!("Proposal kept · “{}”", proposal.title));
                            proposal_detail.set_label(
                                "Type your own direction below. Nothing was saved yet.",
                            );
                            while let Some(child) = proposal_buttons.first_child() {
                                proposal_buttons.remove(&child);
                            }
                            let dismiss = gtk::Button::with_label("Dismiss");
                            dismiss.add_css_class("flat");
                            let clear_pending_proposal = clear_pending_proposal.clone();
                            dismiss.connect_clicked(move |_| clear_pending_proposal());
                            proposal_buttons.append(&dismiss);
                            proposal_box.set_visible(true);
                            input.grab_focus();
                            messages.borrow_mut().push(ChatMessage {
                                role: ChatRole::System,
                                content: "Okay — tell me what you'd rather do. Proposal kept in context until you dismiss or save.".to_owned(),
                                activity: None,
                            });
                            follow_bottom.set(true);
                            refresh_messages();
                        }
                        "save_plan" | "add_targets" | "save_both" => {
                            let choice = choice.clone();
                            let proposal = proposal.clone();
                            let clear_pending_proposal = clear_pending_proposal.clone();
                            let messages = messages.clone();
                            let refresh_messages = refresh_messages.clone();
                            let set_error = set_error.clone();
                            let follow_bottom = follow_bottom.clone();
                            let (tx, rx) = mpsc::channel::<Result<String, String>>();
                            thread::spawn(move || {
                                let result = match choice.as_str() {
                                    "save_plan" => persist_proposal_as_plan(&proposal).map(|_| {
                                        "Saved as a Plan on Home (Needs your choice).".to_owned()
                                    }),
                                    "add_targets" => {
                                        persist_proposal_as_targets(&proposal).map(|n| {
                                            format!(
                                                "Added {n} target{} to the Target Sequence.",
                                                if n == 1 { "" } else { "s" }
                                            )
                                        })
                                    }
                                    "save_both" => {
                                        persist_proposal_as_plan(&proposal)?;
                                        let n =
                                            persist_proposal_as_targets(&proposal).unwrap_or(0);
                                        post_mission_thought(
                                            &proposal.mission_id,
                                            &proposal.target_id,
                                            &format!("Saved proposal: {}", proposal.title),
                                            &proposal.summary,
                                        );
                                        Ok(format!(
                                            "Saved Plan on Home and added {n} target{} to the Target Sequence.",
                                            if n == 1 { "" } else { "s" }
                                        ))
                                    }
                                    _ => Err("Unknown choice.".to_owned()),
                                };
                                let _ = tx.send(result);
                            });
                            glib::timeout_add_local(Duration::from_millis(50), move || {
                                match rx.try_recv() {
                                    Ok(Ok(msg)) => {
                                        clear_pending_proposal();
                                        messages.borrow_mut().push(ChatMessage {
                                            role: ChatRole::System,
                                            content: msg,
                                            activity: None,
                                        });
                                        follow_bottom.set(true);
                                        refresh_messages();
                                        glib::ControlFlow::Break
                                    }
                                    Ok(Err(err)) => {
                                        set_error(Some(err));
                                        glib::ControlFlow::Break
                                    }
                                    Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                                    Err(mpsc::TryRecvError::Disconnected) => {
                                        set_error(Some("Save did not finish.".to_owned()));
                                        glib::ControlFlow::Break
                                    }
                                }
                            });
                        }
                        _ => clear_pending_proposal(),
                    }
                });
                proposal_buttons.append(&button);
            }
            proposal_box.set_visible(true);
        }
    }));

    let set_sending: Rc<dyn Fn(bool)> = Rc::new({
        let send_button = send_button.clone();
        let stop_button = stop_button.clone();
        let sending_spinner = sending_spinner.clone();
        let is_sending = is_sending.clone();
        let new_chat_button = new_chat_button.clone();
        let session_list = session_list.clone();
        let turn_cancel = turn_cancel.clone();
        let refresh_queue_strip = refresh_queue_strip.clone();
        move |sending: bool| {
            *is_sending.borrow_mut() = sending;
            send_button.set_visible(!sending);
            stop_button.set_visible(sending);
            sending_spinner.set_visible(sending);
            if sending {
                sending_spinner.start();
            } else {
                sending_spinner.stop();
                *turn_cancel.borrow_mut() = None;
            }
            // Keep composer editable while generating (Cursor-like); busy Send enqueues.
            new_chat_button.set_sensitive(!sending);
            session_list.set_sensitive(!sending);
            refresh_queue_strip();
        }
    });

    let stop_turn: Rc<dyn Fn()> = Rc::new({
        let turn_cancel = turn_cancel.clone();
        move || {
            if let Some(flag) = turn_cancel.borrow().as_ref() {
                flag.store(true, Ordering::SeqCst);
            }
        }
    });
    stop_button.connect_clicked({
        let stop_turn = stop_turn.clone();
        move |_| stop_turn()
    });
    strip_stop.connect_clicked({
        let stop_turn = stop_turn.clone();
        move |_| stop_turn()
    });

    let pending_approval_tx: Rc<RefCell<Option<mpsc::Sender<ApprovalDecision>>>> =
        Rc::new(RefCell::new(None));

    let chat_attention = Rc::new(Cell::new(0u32));
    let chat_on_attention: Rc<RefCell<Option<Rc<dyn Fn(u32)>>>> = Rc::new(RefCell::new(None));
    let set_chat_attention: Rc<dyn Fn(u32)> = Rc::new({
        let chat_attention = chat_attention.clone();
        let chat_on_attention = chat_on_attention.clone();
        move |n: u32| {
            chat_attention.set(n);
            if let Some(cb) = chat_on_attention.borrow().as_ref() {
                cb(n);
            }
        }
    });

    let clear_approval: Rc<dyn Fn()> = Rc::new({
        let approval_box = approval_box.clone();
        let approval_buttons = approval_buttons.clone();
        let set_chat_attention = set_chat_attention.clone();
        move || {
            while let Some(child) = approval_buttons.first_child() {
                approval_buttons.remove(&child);
            }
            approval_box.set_visible(false);
            set_chat_attention(0);
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
        let title_label = title.clone();
        move || {
            clear_approval();
            set_sending(false);
            set_error(None);
            // Refresh name off the UI thread so New Chat never stalls on soul_get.
            {
                let assistant_name = assistant_name.clone();
                let title_label = title_label.clone();
                let active_discuss = active_discuss.clone();
                let (tx, rx) = mpsc::channel::<String>();
                thread::spawn(move || {
                    let _ = tx.send(load_assistant_display_name());
                });
                glib::timeout_add_local(Duration::from_millis(50), move || match rx.try_recv() {
                    Ok(name) => {
                        *assistant_name.borrow_mut() = name;
                        if active_discuss.borrow().is_none() {
                            title_label
                                .set_label(&format!("Chat with {}", assistant_name.borrow()));
                        }
                        glib::ControlFlow::Break
                    }
                    Err(mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    Err(mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                });
            }
            title_label.set_label(&format!("Chat with {}", assistant_name.borrow()));
            messages.borrow_mut().clear();
            *active_discuss.borrow_mut() = None;
            context_banner.set_label("");
            context_bar.set_visible(false);
            // Commit continuity for the active chat, then lazy-clear so the next
            // send creates a fresh session without an empty Conversations ghost.
            if let Some(sid) = session_id.borrow().clone() {
                thread::spawn(move || {
                    let _ = run_bridge_json(
                        "session_end_continuity",
                        serde_json::json!({ "session_id": sid }),
                    );
                });
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
            let active_for_fetch = session_id.borrow().clone();
            thread::spawn(move || {
                let mut out: Vec<SessionSummary> = list_sessions_including_empty()
                    .into_iter()
                    .filter(|s| {
                        s.message_count > 0
                            || active_for_fetch.as_deref() == Some(s.id.as_str())
                    })
                    .collect();
                if let Some(ref aid) = active_for_fetch {
                    if let Some(idx) = out.iter().position(|s| s.id == *aid) {
                        let cur = out.remove(idx);
                        out.insert(0, cur);
                    }
                }
                let _ = tx.send(out);
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
        let active_discuss = active_discuss.clone();
        let context_banner = context_banner.clone();
        let context_bar = context_bar.clone();
        let title_label = title.clone();
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
            // Leaving a Discuss thread — drop topic framing for the resumed chat.
            *active_discuss.borrow_mut() = None;
            context_banner.set_label("");
            context_bar.set_visible(false);
            let messages = messages.clone();
            let session_id = session_id.clone();
            let refresh_messages = refresh_messages.clone();
            let refresh_sessions = refresh_sessions.clone();
            let set_error = set_error.clone();
            let switching = switching.clone();
            let follow_bottom = follow_bottom.clone();
            let assistant_name = assistant_name.clone();
            let title_label = title_label.clone();
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
                    title_label.set_label(&format!("Chat with {}", assistant_name.borrow()));
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
        let set_chat_attention = set_chat_attention.clone();
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
            set_chat_attention(1);

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

    let submit_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));

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
        let turn_cancel = turn_cancel.clone();
        let show_proposal_choices = show_proposal_choices.clone();
        let keep_proposal_context = keep_proposal_context.clone();
        let pending_proposal = pending_proposal.clone();
        let message_queue = message_queue.clone();
        let refresh_queue_strip = refresh_queue_strip.clone();
        let reset_activity = reset_activity.clone();
        let mode_btn = mode_btn.clone();
        let submit_slot_for_self = submit_slot.clone();
        move || {
            let text = input.text();
            let pending = attachments.borrow().clone();
            if text.trim().is_empty() && pending.is_empty() {
                return;
            }
            // While a turn is running, enqueue follow-ups (Cursor-like).
            if *is_sending.borrow() {
                message_queue.borrow_mut().push(QueuedFollowUp {
                    text,
                    attachments: pending,
                    plan_mode: intent.get() == ChatIntent::Plan,
                });
                input.clear();
                attachments.borrow_mut().clear();
                refresh_attachments();
                refresh_queue_strip();
                return;
            }
            let plan_mode = intent.get() == ChatIntent::Plan;
            // Soul save clears the on-disk session pointer — drop the stale
            // in-memory session so the next turn loads the new SOUL.md cleanly.
            let _ = honor_soul_session_reset(&session_id, &messages);
            // Use cached assistant name on Send — never sync-spawn soul_get here.
            if let Some(topic) = active_discuss.borrow().as_ref() {
                title.set_label(&topic.session_title());
            } else {
                title.set_label(&format!("Chat with {}", assistant_name.borrow()));
            }
            input.clear();
            attachments.borrow_mut().clear();
            refresh_attachments();
            follow_bottom.set(true);
            messages.borrow_mut().push(ChatMessage {
                role: ChatRole::User,
                content: format_user_display(&text, &pending),
                activity: None,
            });
            refresh_messages();
            set_error(None);
            clear_approval();
            show_activity_working();
            let cancel = Arc::new(AtomicBool::new(false));
            *turn_cancel.borrow_mut() = Some(cancel.clone());
            set_sending(true);

            let discuss_topic = active_discuss.borrow().clone();
            let mut outbound = format_attachment_outbound(&text, &pending);
            // If user chose Other on a prior proposal, keep it in context for this turn.
            if keep_proposal_context.get() {
                if let Some(p) = pending_proposal.borrow().as_ref() {
                    outbound = format!(
                        "[Pending proposal the user chose Other on — do not persist unless they clearly ask]\n\
Title: {}\nGoal: {}\nSummary: {}\nSteps: {}\nTargets: {}\n\n{}",
                        p.title,
                        p.goal,
                        p.summary,
                        p.steps.join("; "),
                        p.targets
                            .iter()
                            .map(|t| format!("{} ({})", t.title, t.target_type))
                            .collect::<Vec<_>>()
                            .join("; "),
                        outbound
                    );
                }
            }
            let mut life_inject: Option<Value> = None;
            let mission_discuss = matches!(discuss_topic, Some(DiscussTopic::Mission { .. }));
            if plan_mode {
                // Plan mode preserves Mission framing (mission-proposal) instead of dropping it.
                if let Some(ref topic) = discuss_topic {
                    life_inject = life_inject_for_topic(&text, topic);
                }
                outbound = frame_plan_mode(&outbound, discuss_topic.as_ref());
            } else if let Some(ref topic) = discuss_topic {
                life_inject = life_inject_for_topic(&text, topic);
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
            // Auto plan-update only outside Plan mode (Plan mode may emit a new artifact).
            let applying_plan_update =
                !plan_mode && !plan_id_for_update.is_empty();
            let applying_commitment_update =
                !plan_mode && !commitment_id_for_update.is_empty();
            // Non-mission Plan mode still auto-saves plan-artifact to Home.
            let auto_save_plan_artifact = plan_mode && !mission_discuss;

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
                run_chat_turn(sid, outbound, life_inject, event_tx, approval_rx, cancel);
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
            let show_proposal_choices = show_proposal_choices.clone();
            let discuss_topic_for_done = discuss_topic.clone();
            let message_queue = message_queue.clone();
            let refresh_queue_strip = refresh_queue_strip.clone();
            let reset_activity = reset_activity.clone();
            let mode_btn = mode_btn.clone();
            let intent = intent.clone();
            let input = input.clone();
            let attachments = attachments.clone();
            let refresh_attachments = refresh_attachments.clone();
            let submit_slot_for_self = submit_slot_for_self.clone();
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
                                let mission_proposal = parse_mission_proposal(
                                    &turn.text,
                                    discuss_topic_for_done.as_ref(),
                                );
                                let mut display = if mission_proposal.is_some() {
                                    strip_proposal_fences(&turn.text)
                                } else if auto_save_plan_artifact {
                                    strip_plan_artifact(&turn.text)
                                } else if applying_plan_update {
                                    strip_plan_update(&turn.text)
                                } else if applying_commitment_update {
                                    strip_commitment_update(&turn.text)
                                } else {
                                    // Still strip accidental fences from display.
                                    strip_proposal_fences(&turn.text)
                                };
                                if let Some(proposal) = mission_proposal {
                                    if display.trim().is_empty() {
                                        display = format!(
                                            "Here's a proposal for “{}”. Choose how to save it below.",
                                            proposal.title
                                        );
                                    } else if !display.to_lowercase().contains("save")
                                        && !display.to_lowercase().contains("chip")
                                    {
                                        display.push_str(
                                            "\n\nChoose Save as Plan, Add as targets, Save both, Other, or Dismiss below.",
                                        );
                                    }
                                    if let Some(show) = show_proposal_choices.borrow().clone() {
                                        show(proposal);
                                    }
                                } else if auto_save_plan_artifact {
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
                                if let Some(archive) = summary {
                                    messages.borrow_mut().push(ChatMessage {
                                        role: ChatRole::System,
                                        content: archive.summary.clone(),
                                        activity: Some(archive),
                                    });
                                    reset_activity();
                                }
                                messages.borrow_mut().push(ChatMessage {
                                    role: ChatRole::Assistant,
                                    content: display,
                                    activity: None,
                                });
                                follow_bottom.set(true);
                                refresh_messages();
                                refresh_sessions();
                            }
                            Err(err) => {
                                if err == "Stopped." {
                                    if let Some(archive) = summary {
                                        messages.borrow_mut().push(ChatMessage {
                                            role: ChatRole::System,
                                            content: archive.summary.clone(),
                                            activity: Some(archive),
                                        });
                                        reset_activity();
                                    }
                                    messages.borrow_mut().push(ChatMessage {
                                        role: ChatRole::System,
                                        content: "Stopped.".to_owned(),
                                        activity: None,
                                    });
                                    follow_bottom.set(true);
                                    refresh_messages();
                                } else {
                                    let _ = summary;
                                    set_error(Some(err));
                                }
                            }
                        }
                        // Drain queued follow-ups (Cursor-like).
                        let next = {
                            let mut q = message_queue.borrow_mut();
                            if q.is_empty() {
                                None
                            } else {
                                Some(q.remove(0))
                            }
                        };
                        refresh_queue_strip();
                        if let Some(next) = next {
                            intent.set(if next.plan_mode {
                                ChatIntent::Plan
                            } else {
                                ChatIntent::Chat
                            });
                            mode_btn.set_label(if next.plan_mode { "Plan" } else { "Chat" });
                            input.set_text(&next.text);
                            *attachments.borrow_mut() = next.attachments;
                            refresh_attachments();
                            let submit_slot = submit_slot_for_self.clone();
                            glib::idle_add_local_once(move || {
                                if let Some(submit) = submit_slot.borrow().clone() {
                                    submit();
                                }
                            });
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
                        refresh_queue_strip();
                        glib::ControlFlow::Break
                    }
                }
            });
        }
    });
    *submit_slot.borrow_mut() = Some(submit.clone());

    // Regenerate last assistant turn from the preceding user message.
    *regenerate_slot.borrow_mut() = Some(Rc::new({
        let messages = messages.clone();
        let input = input.clone();
        let attachments = attachments.clone();
        let refresh_attachments = refresh_attachments.clone();
        let submit = submit.clone();
        let is_sending = is_sending.clone();
        move || {
            if *is_sending.borrow() {
                return;
            }
            let msgs = messages.borrow();
            let Some(last_assistant) = msgs
                .iter()
                .rposition(|m| m.role == ChatRole::Assistant && m.activity.is_none())
            else {
                return;
            };
            let Some(user_idx) = msgs[..last_assistant]
                .iter()
                .rposition(|m| m.role == ChatRole::User)
            else {
                return;
            };
            let user_text = msgs[user_idx].content.clone();
            drop(msgs);
            // Drop the last assistant (+ optional activity system row before it).
            {
                let mut msgs = messages.borrow_mut();
                while msgs.len() > user_idx + 1 {
                    let last = msgs.last().map(|m| m.role);
                    match last {
                        Some(ChatRole::Assistant) | Some(ChatRole::System) => {
                            msgs.pop();
                        }
                        _ => break,
                    }
                }
                // Also remove the user bubble — submit will re-add it.
                if msgs.last().map(|m| m.role) == Some(ChatRole::User) {
                    msgs.pop();
                }
            }
            // Strip attachment display suffixes from user bubble for regenerate text.
            let regen_text = user_text
                .lines()
                .take_while(|l| !l.starts_with("📎 ") && !l.starts_with("Attached:"))
                .collect::<Vec<_>>()
                .join("\n");
            let regen_text = regen_text.trim().to_owned();
            if regen_text.is_empty() {
                return;
            }
            attachments.borrow_mut().clear();
            refresh_attachments();
            input.set_text(&regen_text);
            submit();
        }
    }));

    send_button.connect_clicked({
        let submit = submit.clone();
        move |_| submit()
    });

    // Cursor keybindings: Enter / Ctrl+Enter send; Shift+Enter newline.
    // Ctrl/Cmd+V with an image on the clipboard → attach PNG.
    {
        let submit = submit.clone();
        let attachments = attachments.clone();
        let refresh_attachments = refresh_attachments.clone();
        let key = gtk::EventControllerKey::new();
        key.set_propagation_phase(gtk::PropagationPhase::Capture);
        key.connect_key_pressed(move |controller, keyval, _keycode, state| {
            let shift = state.contains(ModifierType::SHIFT_MASK);
            let ctrl = state.contains(ModifierType::CONTROL_MASK)
                || state.contains(ModifierType::META_MASK)
                || state.contains(ModifierType::SUPER_MASK);

            // Paste image → attachment
            if ctrl && (keyval == Key::v || keyval == Key::V) {
                if let Some(widget) = controller.widget() {
                    let clipboard = widget.clipboard();
                    let attachments = attachments.clone();
                    let refresh_attachments = refresh_attachments.clone();
                    clipboard.read_texture_async(
                        gio::Cancellable::NONE,
                        move |result| {
                            if let Ok(Some(texture)) = result {
                                if save_clipboard_texture_as_attachment(&texture, &attachments) {
                                    refresh_attachments();
                                }
                            }
                        },
                    );
                    // Let text paste proceed if no image; when image exists we still
                    // allow text paste in parallel — fine for v1.
                }
            }

            if keyval == Key::Return || keyval == Key::KP_Enter {
                if shift && !ctrl {
                    return glib::Propagation::Proceed;
                }
                submit();
                return glib::Propagation::Stop;
            }
            glib::Propagation::Proceed
        });
        input.view().add_controller(key);
    }

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
        attention: chat_attention,
        on_attention_changed: chat_on_attention,
        open_topic_session: Rc::new(RefCell::new(None)),
    };

    // Discuss from Missions / Settings must open a topic-named conversation —
    // never continue whatever unrelated chat was already on screen (iPhone parity).
    handle.set_open_topic_session(Rc::new({
        let messages = messages.clone();
        let session_id = session_id.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_sessions = refresh_sessions.clone();
        let set_error = set_error.clone();
        let clear_approval = clear_approval.clone();
        let set_sending = set_sending.clone();
        let follow_bottom = follow_bottom.clone();
        let assistant_name = assistant_name.clone();
        let title_label = title.clone();
        move |topic_title: String| {
            clear_approval();
            set_sending(false);
            set_error(None);
            *assistant_name.borrow_mut() = load_assistant_display_name();
            // Show the topic name in the chat header (conversation identity).
            title_label.set_label(&topic_title);
            follow_bottom.set(true);

            let previous = session_id.borrow().clone();

            if let Some(existing) = find_session_by_title(&topic_title) {
                // Already discussing this topic — resume that thread.
                if previous.as_deref() == Some(existing.id.as_str()) {
                    // Same session already active; keep transcript, just re-bind discuss.
                    return !messages.borrow().is_empty();
                }
                if let Some(ref sid) = previous {
                    let _ = run_bridge_json(
                        "session_end_continuity",
                        serde_json::json!({ "session_id": sid }),
                    );
                }
                match resume_session(&existing.id) {
                    Ok((sid, history)) => {
                        save_session_id(&sid);
                        *session_id.borrow_mut() = Some(sid);
                        *messages.borrow_mut() = history;
                        refresh_messages();
                        refresh_sessions();
                        return true;
                    }
                    Err(err) => {
                        set_error(Some(err));
                        // Fall through and create a fresh named session.
                    }
                }
            }

            if let Some(ref sid) = previous {
                let _ = run_bridge_json(
                    "session_end_continuity",
                    serde_json::json!({ "session_id": sid }),
                );
            }
            match create_named_session(&topic_title, previous.as_deref()) {
                Ok(sid) => {
                    *session_id.borrow_mut() = Some(sid);
                    messages.borrow_mut().clear();
                    refresh_messages();
                    refresh_sessions();
                    false
                }
                Err(err) => {
                    // Soft-fail: still clear the transcript so Discuss doesn't
                    // continue an unrelated thread; first send will create a session.
                    *session_id.borrow_mut() = None;
                    let path = session_store_path();
                    let _ = std::fs::remove_file(&path);
                    messages.borrow_mut().clear();
                    refresh_messages();
                    refresh_sessions();
                    set_error(Some(err));
                    false
                }
            }
        }
    }));

    (container, handle)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_mission_proposal_fence_from_display() {
        let raw = "Here is a plan.\n\n```mission-proposal\n{\"title\":\"T\",\"goal\":\"G\",\"steps\":[\"a\"],\"targets\":[]}\n```\n";
        let stripped = strip_mission_proposal(raw);
        assert!(!stripped.contains("mission-proposal"));
        assert!(stripped.contains("Here is a plan."));
    }

    #[test]
    fn parses_mission_proposal_without_auto_fields() {
        let raw = r#"Next steps:

```mission-proposal
{"title":"Ship accept flow","goal":"User can save","summary":"Chips confirm","steps":["Wire fence","Show chips"],"targets":[{"title":"Must ship chips","target_type":"essential","description":""}]}
```
"#;
        let proposal = parse_mission_proposal(raw, None).expect("parse");
        assert_eq!(proposal.title, "Ship accept flow");
        assert_eq!(proposal.targets.len(), 1);
        assert_eq!(proposal.targets[0].target_type, "essential");
        // Parsing alone must not persist — no bridge calls in this unit test.
        let plan = proposal_to_plan_value(&proposal);
        assert_eq!(plan["status"], "pending_review");
        assert_eq!(plan["title"], "Ship accept flow");
    }

    #[test]
    fn plan_artifact_becomes_mission_proposal_when_mission_topic() {
        let topic = DiscussTopic::Mission {
            statement: "Build Centurion".to_owned(),
            id: Some("m1".to_owned()),
            title: Some("Centurion".to_owned()),
            target_id: None,
            target_title: None,
            target_type: None,
            target_description: None,
            target_status: None,
            sequence_number: None,
        };
        let raw = r#"```plan-artifact
{"title":"Fallback","goal":"G","steps":["one","two"],"summary":"S"}
```"#;
        let proposal = parse_mission_proposal(raw, Some(&topic)).expect("fallback");
        assert_eq!(proposal.mission_id, "m1");
        assert_eq!(proposal.title, "Fallback");
        assert_eq!(proposal.targets.len(), 2); // derived from steps
    }

    #[test]
    fn normalize_target_types() {
        assert_eq!(normalize_target_type("Must Do"), "essential");
        assert_eq!(normalize_target_type("should"), "shouldHave");
        assert_eq!(normalize_target_type("nice_to_have"), "niceToHave");
    }
}

