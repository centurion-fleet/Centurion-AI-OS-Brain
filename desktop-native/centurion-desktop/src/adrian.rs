//! Adrian — Centurion's cloud support guide (internet, separate from LAN link).

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

pub const DEFAULT_BASE_URL: &str = "https://help.personal-centurion.com";

const WELCOME: &str = "I'm Adrian online — Adrian who built Centurion. My passion is helping you live \
your mission, not just fix your app.\n\n\
Centurion is for a 1:1 relationship with your private AI — to take day-to-day pressure \
off you, free your thinking, and keep discovering what matters. Your mission isn't one \
fixed destination; it evolves, and that's the point.\n\n\
I'll listen first, then help — one clear step at a time. Stuck technically, curious how \
things work, or ready to dream what's next? Ask me. Plain language, no technical exam.\n\n\
I work over the internet, separate from your Centurion on your Centurion brain. What would \
you like to explore?";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdrianMessage {
    pub role: AdrianRole,
    pub content: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdrianRole {
    User,
    Adrian,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SuggestedAction {
    pub id: String,
    pub label: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct AdrianChatContext {
    pub app_version: String,
    pub connection_state: String,
    pub thinking_health: String,
    pub thinking_message: String,
    pub has_mission: bool,
    pub active_target_count: u32,
    pub mission_summary: String,
    pub support_code: String,
}

#[derive(Serialize)]
struct ChatPayload {
    install_id: String,
    messages: Vec<WireMessage>,
    context: AdrianChatContext,
}

#[derive(Serialize)]
struct WireMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    ok: bool,
    reply: String,
    #[serde(default)]
    suggested_actions: Vec<SuggestedActionWire>,
    #[serde(default)]
    message: String,
}

#[derive(Debug, Deserialize)]
struct SuggestedActionWire {
    id: String,
    label: String,
}

pub struct ChatResult {
    pub ok: bool,
    pub reply: String,
    pub suggested_actions: Vec<SuggestedAction>,
    pub message: String,
}

pub fn base_url() -> String {
    std::env::var("CENTURION_ADRIAN_BASE_URL")
        .or_else(|_| std::env::var("CENTURION_HERALD_BASE_URL"))
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_BASE_URL.to_owned())
}

pub fn centurion_home() -> PathBuf {
    std::env::var("CENTURION_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_owned());
            PathBuf::from(format!("{home}/.centurion"))
        })
}

fn adrian_dir() -> PathBuf {
    centurion_home().join("adrian")
}

pub fn install_id() -> String {
    let path = adrian_dir().join("install_id");
    if let Ok(existing) = fs::read_to_string(&path) {
        let trimmed = existing.trim();
        if trimmed.len() >= 8 {
            return trimmed.to_owned();
        }
    }
    let legacy = adrian_dir().join("herald_install_id");
    if let Ok(existing) = fs::read_to_string(&legacy) {
        let trimmed = existing.trim();
        if trimmed.len() >= 8 {
            let _ = write_text(&path, trimmed);
            return trimmed.to_owned();
        }
    }
    let fresh = format!("desktop-linux-{}", uuid::Uuid::new_v4());
    let _ = write_text(&path, &fresh);
    fresh
}

pub fn has_accepted_privacy() -> bool {
    let path = adrian_dir().join("privacy_accepted");
    if fs::read_to_string(&path)
        .map(|value| value.trim() == "1")
        .unwrap_or(false)
    {
        return true;
    }
    let legacy = adrian_dir().join("herald_privacy_accepted");
    fs::read_to_string(&legacy)
        .map(|value| value.trim() == "1")
        .unwrap_or(false)
}

pub fn accept_privacy() {
    let _ = write_text(&adrian_dir().join("privacy_accepted"), "1");
}

pub fn seed_welcome(messages: &mut Vec<AdrianMessage>) {
    if messages.is_empty() {
        messages.push(AdrianMessage {
            role: AdrianRole::Adrian,
            content: WELCOME.to_owned(),
        });
    }
}

pub fn send_chat(
    messages: &[AdrianMessage],
    user_message: &str,
    context: &AdrianChatContext,
) -> Result<ChatResult, String> {
    let trimmed = user_message.trim();
    if trimmed.is_empty() {
        return Err("Message is empty.".to_owned());
    }

    let install = install_id();
    let mut wire_messages: Vec<WireMessage> = messages
        .iter()
        .filter(|msg| matches!(msg.role, AdrianRole::User | AdrianRole::Adrian))
        .rev()
        .take(12)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .map(|msg| WireMessage {
            role: if msg.role == AdrianRole::User {
                "user".to_owned()
            } else {
                "assistant".to_owned()
            },
            content: msg.content.clone(),
        })
        .collect();

    if wire_messages.last().map(|m| m.role.as_str()) != Some("user") {
        wire_messages.push(WireMessage {
            role: "user".to_owned(),
            content: trimmed.to_owned(),
        });
    }

    let payload = ChatPayload {
        install_id: install.clone(),
        messages: wire_messages,
        context: context.clone(),
    };

    let url = format!("{}/api/v1/chat", base_url().trim_end_matches('/'));
    let response = ureq::post(&url)
        .set("Content-Type", "application/json")
        .set("X-Centurion-Install-ID", &install)
        .timeout(std::time::Duration::from_secs(45))
        .send_json(payload)
        .map_err(|error| format_network_error(&error))?;

    let status = response.status();
    let body: ChatResponse = response
        .into_json()
        .map_err(|error| format!("Adrian returned an unreadable response: {error}"))?;

    if status >= 400 && !body.ok {
        return Ok(ChatResult {
            ok: false,
            reply: String::new(),
            suggested_actions: Vec::new(),
            message: if body.message.is_empty() {
                "Adrian couldn't respond right now.".to_owned()
            } else {
                body.message
            },
        });
    }

    Ok(ChatResult {
        ok: body.ok,
        reply: body.reply,
        suggested_actions: body
            .suggested_actions
            .into_iter()
            .map(|action| SuggestedAction {
                id: action.id,
                label: action.label,
            })
            .collect(),
        message: body.message,
    })
}

fn format_network_error(error: &ureq::Error) -> String {
    match error {
        ureq::Error::Status(code, response) => {
            let detail = response.into_string().unwrap_or_default();
            if detail.is_empty() {
                format!("Couldn't reach Adrian (HTTP {code}). Check your internet connection.")
            } else {
                format!("Couldn't reach Adrian (HTTP {code}): {detail}")
            }
        }
        _ => "Couldn't reach Adrian. Check your internet connection and try again.".to_owned(),
    }
}

fn write_text(path: &PathBuf, value: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, value)
}
