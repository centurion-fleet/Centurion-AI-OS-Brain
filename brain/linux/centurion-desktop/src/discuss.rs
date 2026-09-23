//! Topic descriptors for the Mission Deck's "discuss" affordances.
//!
//! Extracted from the former `chat_page` module when Chat was removed from the
//! Linux Brain (v6.0.0). These describe WHAT a deck card is about; they were
//! originally handed to Chat to frame an outbound turn.
//!
//! Chat is gone. The deck still builds these and still calls its `on_ask_about`
//! hook, which the shell now wires to a no-op. This module is retained so the
//! deck's call sites stay intact while the destination for "discuss" is decided.

use serde_json::Value;

/// Structured topic for the Mission Deck's discuss affordances.
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
        /// Kanban board slug (usually same as `id`).
        board_id: String,
        root_id: String,
        workers_summary: String,
        blackboard_json: String,
    },
    Document {
        /// life.db document id when known (Focus mission docs).
        id: Option<String>,
        mission_id: Option<String>,
        doc_type: Option<String>,
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
    Decision {
        id: String,
        title: String,
        chosen: String,
        context: String,
        mission_id: Option<String>,
        mission_title: Option<String>,
        target_id: Option<String>,
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
            Self::Decision { title, .. } => format!("Discussing decision · {title}"),
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
            Self::Decision { title, .. } => format!("Decision · {title}"),
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

    /// Stable SessionDB `topic_kind` for Durable Discuss restore.
    pub fn topic_kind(&self) -> &'static str {
        match self {
            Self::Plan { .. } => "plan",
            Self::Collab { .. } => "collab",
            Self::Document { .. } => "document",
            Self::Mission { .. } => "mission",
            Self::Commitment { .. } => "commitment",
            Self::Horizon { .. } => "horizon",
            Self::Decision { .. } => "decision",
            Self::Generic { .. } => "generic",
        }
    }

    /// JSON `topic_ref` persisted beside the session for Desktop/iPhone restore.
    pub fn topic_ref(&self) -> Value {
        match self {
            Self::Plan {
                id,
                title,
                status,
                goal,
                summary,
                steps,
                risks,
            } => serde_json::json!({
                "plan_id": id,
                "title": title,
                "status": status,
                "goal": goal,
                "summary": summary,
                "steps": steps,
                "risks": risks,
            }),
            Self::Collab {
                id,
                name,
                pulse,
                objective,
                board_id,
                root_id,
                workers_summary,
                blackboard_json,
            } => serde_json::json!({
                "id": id,
                "name": name,
                "pulse": pulse,
                "objective": objective,
                "board_id": board_id,
                "root_id": root_id,
                "workers_summary": workers_summary,
                "blackboard_json": blackboard_json,
            }),
            Self::Document {
                id,
                mission_id,
                doc_type,
                title,
                summary,
                plan_id,
                body_excerpt,
            } => serde_json::json!({
                "id": id,
                "mission_id": mission_id,
                "doc_type": doc_type,
                "title": title,
                "summary": summary,
                "plan_id": plan_id,
                "body_excerpt": body_excerpt,
            }),
            Self::Mission {
                statement,
                id,
                title,
                target_id,
                target_title,
                target_type,
                target_description,
                target_status,
                sequence_number,
            } => serde_json::json!({
                "mission_id": id,
                "title": title,
                "statement": statement,
                "target_id": target_id,
                "target_title": target_title,
                "target_type": target_type,
                "target_description": target_description,
                "target_status": target_status,
                "sequence_number": sequence_number,
            }),
            Self::Commitment {
                id,
                title,
                description,
                active,
                mission_statement,
            } => serde_json::json!({
                "commitment_id": id,
                "title": title,
                "description": description,
                "active": active,
                "mission_statement": mission_statement,
            }),
            Self::Horizon { layer, detail } => serde_json::json!({
                "layer": layer,
                "detail": detail,
            }),
            Self::Decision {
                id,
                title,
                chosen,
                context,
                mission_id,
                mission_title,
                target_id,
            } => serde_json::json!({
                "decision_id": id,
                "title": title,
                "chosen": chosen,
                "context": context,
                "mission_id": mission_id,
                "mission_title": mission_title,
                "target_id": target_id,
            }),
            Self::Generic { title, kind, detail } => serde_json::json!({
                "title": title,
                "kind": kind,
                "detail": detail,
            }),
        }
    }

    /// Rebuild Discuss framing from SessionDB topic metadata (best-effort).
    pub fn from_session_meta(kind: &str, title: &str, topic_ref: Option<&Value>) -> Option<Self> {
        let kind = kind.trim().to_ascii_lowercase();
        if kind.is_empty() {
            return None;
        }
        let r = topic_ref.unwrap_or(&Value::Null);
        let str_field = |key: &str| -> Option<String> {
            r.get(key)
                .and_then(|v| v.as_str())
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
        };
        let opt_str = |key: &str| -> Option<String> { str_field(key) };
        let display = {
            let t = title.trim();
            if t.is_empty() {
                str_field("title")
                    .or_else(|| str_field("name"))
                    .unwrap_or_else(|| "Discussion".to_owned())
            } else {
                t.to_owned()
            }
        };
        match kind.as_str() {
            "plan" => Some(Self::Plan {
                id: str_field("plan_id").or_else(|| str_field("id")).unwrap_or_default(),
                title: display,
                status: str_field("status").unwrap_or_default(),
                goal: str_field("goal").unwrap_or_default(),
                summary: str_field("summary").unwrap_or_default(),
                steps: r
                    .get("steps")
                    .and_then(|v| v.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|x| x.as_str().map(str::to_owned))
                            .collect()
                    })
                    .unwrap_or_default(),
                risks: r
                    .get("risks")
                    .and_then(|v| v.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|x| x.as_str().map(str::to_owned))
                            .collect()
                    })
                    .unwrap_or_default(),
            }),
            "collab" => Some(Self::Collab {
                id: str_field("id")
                    .or_else(|| str_field("board_id"))
                    .unwrap_or_default(),
                name: display,
                pulse: str_field("pulse").unwrap_or_default(),
                objective: str_field("objective").unwrap_or_default(),
                board_id: str_field("board_id")
                    .or_else(|| str_field("id"))
                    .unwrap_or_default(),
                root_id: str_field("root_id").unwrap_or_default(),
                workers_summary: str_field("workers_summary").unwrap_or_default(),
                blackboard_json: str_field("blackboard_json").unwrap_or_else(|| "{}".to_owned()),
            }),
            "document" => Some(Self::Document {
                id: opt_str("id"),
                mission_id: opt_str("mission_id"),
                doc_type: opt_str("doc_type"),
                title: display,
                summary: str_field("summary").unwrap_or_default(),
                plan_id: opt_str("plan_id"),
                body_excerpt: str_field("body_excerpt").unwrap_or_default(),
            }),
            "mission" => Some(Self::Mission {
                statement: str_field("statement").unwrap_or_else(|| display.clone()),
                id: opt_str("mission_id").or_else(|| opt_str("id")),
                title: Some(display),
                target_id: opt_str("target_id"),
                target_title: opt_str("target_title"),
                target_type: opt_str("target_type"),
                target_description: opt_str("target_description"),
                target_status: opt_str("target_status"),
                sequence_number: r.get("sequence_number").and_then(|v| v.as_i64()),
            }),
            "commitment" => Some(Self::Commitment {
                id: str_field("commitment_id")
                    .or_else(|| str_field("id"))
                    .unwrap_or_default(),
                title: display,
                description: str_field("description").unwrap_or_default(),
                active: r.get("active").and_then(|v| v.as_bool()).unwrap_or(true),
                mission_statement: str_field("mission_statement").unwrap_or_default(),
            }),
            "horizon" => Some(Self::Horizon {
                layer: str_field("layer").unwrap_or_else(|| display.clone()),
                detail: str_field("detail").unwrap_or_default(),
            }),
            "decision" => Some(Self::Decision {
                id: str_field("decision_id")
                    .or_else(|| str_field("id"))
                    .unwrap_or_default(),
                title: display,
                chosen: str_field("chosen").unwrap_or_default(),
                context: str_field("context").unwrap_or_default(),
                mission_id: opt_str("mission_id"),
                mission_title: opt_str("mission_title"),
                target_id: opt_str("target_id"),
            }),
            "generic" | "topic" => Some(Self::Generic {
                title: display,
                kind: str_field("kind").unwrap_or_else(|| "topic".to_owned()),
                detail: str_field("detail").unwrap_or_default(),
            }),
            _ => Some(Self::Generic {
                title: display,
                kind: kind,
                detail: str_field("detail").unwrap_or_default(),
            }),
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
