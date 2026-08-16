use async_trait::async_trait;
use serde::Serialize;
use serde_json::Value;
use std::io;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::OnceLock;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio::time::timeout;

const BRIDGE_TIMEOUT: Duration = Duration::from_secs(360);

#[derive(Debug, Clone)]
pub struct BridgeApprovalEvent {
    pub approval_id: String,
    pub session_key: String,
    pub command: String,
    pub description: String,
    pub pattern_key: String,
    pub choices: Vec<String>,
}

/// Mid-turn push from `remote_bridge` NDJSON (`centurion_event`).
#[derive(Debug, Clone)]
pub enum BridgeTurnEvent {
    Approval(BridgeApprovalEvent),
    /// Tool / thinking / status line for honest waiting UI (no PII required).
    Activity {
        message: String,
        kind: String,
        tool: Option<String>,
    },
    /// Incremental assistant text for live Crypto Chat streaming.
    StreamDelta {
        text: String,
    },
}

#[derive(Debug, Clone)]
pub struct BridgeApprovalDecision {
    pub session_key: String,
    pub choice: String,
    pub resolve_all: bool,
}

#[async_trait]
pub trait AgentBridge: Send + Sync {
    async fn chat(
        &self,
        request_id: &str,
        text: &str,
        session_id: Option<&str>,
        life_inject: Option<Value>,
        event_tx: Option<mpsc::Sender<BridgeTurnEvent>>,
        mut approval_rx: Option<mpsc::Receiver<BridgeApprovalDecision>>,
    ) -> Result<BridgeChatResult, BridgeError>;

    async fn invoke(
        &self,
        request_id: &str,
        action: &str,
        payload: Value,
    ) -> Result<Value, BridgeError>;
}

#[derive(Debug, Clone)]
pub struct BridgeChatResult {
    pub text: String,
    pub recovered: bool,
    pub recovery_message: Option<String>,
    pub routed_display_name: Option<String>,
    pub code: Option<String>,
    pub session_id: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("failed to start the Centurion core: {0}")]
    Spawn(#[source] io::Error),
    #[error("failed to send the request to the Centurion core: {0}")]
    Write(#[source] io::Error),
    #[error("the Centurion core did not complete: {0}")]
    Wait(#[source] io::Error),
    #[error("the Centurion core timed out after {0} seconds")]
    Timeout(u64),
    #[error("the Centurion core returned invalid JSON: {0}")]
    InvalidResponse(#[source] serde_json::Error),
    #[error("{message}")]
    Agent {
        message: String,
        code: Option<String>,
        retryable: bool,
    },
}

#[derive(Debug, Clone)]
pub struct PythonBridge {
    python: String,
}

impl PythonBridge {
    pub fn new(python: impl Into<String>) -> Self {
        Self {
            python: python.into(),
        }
    }
}

#[derive(Serialize, Clone)]
struct BridgeRequest<'a> {
    id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    action: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<&'a str>,
    #[serde(flatten)]
    extra: Value,
}

#[async_trait]
impl AgentBridge for PythonBridge {
    async fn chat(
        &self,
        request_id: &str,
        text: &str,
        session_id: Option<&str>,
        life_inject: Option<Value>,
        event_tx: Option<mpsc::Sender<BridgeTurnEvent>>,
        approval_rx: Option<mpsc::Receiver<BridgeApprovalDecision>>,
    ) -> Result<BridgeChatResult, BridgeError> {
        let mut extra = serde_json::Map::new();
        if let Some(session_id) = session_id {
            extra.insert("session_id".to_owned(), Value::String(session_id.to_owned()));
        }
        if let Some(inject) = life_inject {
            extra.insert("life_inject".to_owned(), inject);
        }
        extra.insert("events".to_owned(), Value::Bool(true));
        let events = event_tx.is_some();
        let response = self
            .run_bridge_chat(
                BridgeRequest {
                    id: request_id,
                    action: Some("chat"),
                    text: Some(text),
                    extra: Value::Object(extra),
                },
                events,
                event_tx,
                approval_rx,
            )
            .await?;

        if value_bool(&response, "ok") {
            return Ok(BridgeChatResult {
                text: response
                    .get("text")
                    .and_then(|item| item.as_str())
                    .unwrap_or("")
                    .to_owned(),
                recovered: value_bool(&response, "recovered"),
                recovery_message: value_string(&response, "recovery_message"),
                routed_display_name: value_string(&response, "routed_display_name"),
                code: value_string(&response, "code"),
                session_id: value_string(&response, "session_id"),
            });
        }

        Err(BridgeError::Agent {
            message: response_message(&response),
            code: value_string(&response, "code"),
            retryable: value_bool_opt(&response, "retryable").unwrap_or(true),
        })
    }

    async fn invoke(
        &self,
        request_id: &str,
        action: &str,
        payload: Value,
    ) -> Result<Value, BridgeError> {
        let response = self
            .run_bridge(BridgeRequest {
                id: request_id,
                action: Some(action),
                text: None,
                extra: payload,
            })
            .await?;

        // Pass through the full Python JSON object so domain payloads
        // (soul, mission, oversight, plans, …) are not dropped.
        if value_bool(&response, "ok") {
            return Ok(response);
        }

        Err(BridgeError::Agent {
            message: response_message(&response),
            code: value_string(&response, "code"),
            retryable: value_bool_opt(&response, "retryable").unwrap_or(false),
        })
    }
}

struct WarmDaemonState {
    child: Option<tokio::process::Child>,
}

fn warm_daemon_state() -> &'static tokio::sync::Mutex<WarmDaemonState> {
    static STATE: OnceLock<tokio::sync::Mutex<WarmDaemonState>> = OnceLock::new();
    STATE.get_or_init(|| tokio::sync::Mutex::new(WarmDaemonState { child: None }))
}

impl PythonBridge {
    fn bridge_socket_path() -> PathBuf {
        if let Ok(path) = std::env::var("CENTURION_BRIDGE_SOCKET") {
            let trimmed = path.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed);
            }
        }
        let home = std::env::var("CENTURION_HOME").unwrap_or_else(|_| {
            let fallback = std::env::var("HOME").unwrap_or_default();
            format!("{fallback}/.centurion")
        });
        PathBuf::from(home).join("run").join("bridge.sock")
    }

    async fn socket_is_ready() -> bool {
        let path = Self::bridge_socket_path();
        matches!(
            timeout(Duration::from_millis(200), UnixStream::connect(&path)).await,
            Ok(Ok(_))
        )
    }

    async fn wait_until_ready(limit: Duration) -> Result<(), BridgeError> {
        let start = tokio::time::Instant::now();
        while start.elapsed() < limit {
            if Self::socket_is_ready().await {
                return Ok(());
            }
            tokio::time::sleep(Duration::from_millis(80)).await;
        }
        if Self::socket_is_ready().await {
            Ok(())
        } else {
            Err(BridgeError::Write(io::Error::new(
                io::ErrorKind::NotFound,
                "warm Centurion daemon did not become ready",
            )))
        }
    }

    async fn connect_warm_socket() -> Result<UnixStream, BridgeError> {
        let path = Self::bridge_socket_path();
        timeout(Duration::from_millis(800), UnixStream::connect(&path))
            .await
            .map_err(|_| {
                BridgeError::Write(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "warm bridge socket not ready",
                ))
            })?
            .map_err(BridgeError::Write)
    }

    /// Start or reuse `$CENTURION_HOME/run/bridge.sock` — the same warm
    /// process Desktop Chat already uses. Do not recycle a live listener;
    /// GTK Brain may already own it.
    pub async fn ensure_warm_daemon(&self) -> Result<(), BridgeError> {
        if Self::socket_is_ready().await {
            return Ok(());
        }
        let mut state = warm_daemon_state().lock().await;
        if Self::socket_is_ready().await {
            return Ok(());
        }
        if let Some(child) = state.child.as_mut() {
            match child.try_wait() {
                Ok(None) => {
                    drop(state);
                    return Self::wait_until_ready(Duration::from_secs(12)).await;
                }
                _ => state.child = None,
            }
        }

        let path = Self::bridge_socket_path();
        if let Some(parent) = path.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }
        if path.exists() && !Self::socket_is_ready().await {
            let _ = tokio::fs::remove_file(&path).await;
        }
        if Self::socket_is_ready().await {
            return Ok(());
        }

        let socket = path.to_string_lossy().into_owned();
        let mut command = Command::new(&self.python);
        command
            .args([
                "-m",
                "centurion_cli.remote_bridge",
                "--serve",
                "--socket",
                &socket,
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::inherit())
            .kill_on_drop(false);
        if let Ok(home) = std::env::var("CENTURION_HOME") {
            command.env("CENTURION_HOME", &home);
        }
        command.env("CENTURION_BRIDGE_SOCKET", &path);
        if let Some(cwd) = bridge_working_directory() {
            command.current_dir(cwd);
        }
        tracing::info!(socket = %path.display(), "starting warm Centurion daemon for iPhone Chat");
        let child = command.spawn().map_err(BridgeError::Spawn)?;
        state.child = Some(child);
        drop(state);
        Self::wait_until_ready(Duration::from_secs(12)).await
    }

    /// Same warm daemon Desktop Chat uses (`$CENTURION_HOME/run/bridge.sock`).
    async fn run_via_warm_socket(
        &self,
        request: BridgeRequest<'_>,
        events: bool,
        event_tx: Option<mpsc::Sender<BridgeTurnEvent>>,
        mut approval_rx: Option<mpsc::Receiver<BridgeApprovalDecision>>,
    ) -> Result<Value, BridgeError> {
        let stream = Self::connect_warm_socket().await?;
        let request_bytes = serialize_bridge_request_line(&request)?;
        let (reader, mut writer) = stream.into_split();
        writer.write_all(&request_bytes).await.map_err(BridgeError::Write)?;
        if !events {
            writer.shutdown().await.map_err(BridgeError::Write)?;
        }
        let mut lines = BufReader::new(reader).lines();
        let mut final_response: Option<Value> = None;
        timeout(BRIDGE_TIMEOUT, async {
            loop {
                tokio::select! {
                    biased;
                    decision = async {
                        match approval_rx.as_mut() {
                            Some(rx) => rx.recv().await,
                            None => std::future::pending().await,
                        }
                    } => {
                        if let Some(decision) = decision {
                            let payload = serde_json::json!({
                                "action": "approval_respond",
                                "session_key": decision.session_key,
                                "choice": decision.choice,
                                "all": decision.resolve_all,
                            });
                            let mut line = serde_json::to_vec(&payload)
                                .map_err(BridgeError::InvalidResponse)?;
                            line.push(b'\n');
                            writer.write_all(&line).await.map_err(BridgeError::Write)?;
                            writer.flush().await.map_err(BridgeError::Write)?;
                        }
                    }
                    line = lines.next_line() => {
                        let line = line.map_err(BridgeError::Wait)?;
                        let Some(line) = line else {
                            break;
                        };
                        let trimmed = line.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        let value: Value = serde_json::from_str(trimmed)
                            .map_err(BridgeError::InvalidResponse)?;
                        if value.get("centurion_event").is_some() {
                            if let Some(tx) = &event_tx {
                                if let Some(event) = turn_event_from_ndjson(&value) {
                                    let _ = tx.send(event).await;
                                }
                            }
                            continue;
                        }
                        if events {
                            if is_bridge_chat_final(&value) {
                                final_response = Some(value);
                                break;
                            }
                        } else {
                            final_response = Some(value);
                            break;
                        }
                    }
                }
            }
            final_response.ok_or_else(|| {
                BridgeError::InvalidResponse(serde_json::Error::io(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "warm bridge closed without a JSON response",
                )))
            })
        })
        .await
        .map_err(|_| BridgeError::Timeout(BRIDGE_TIMEOUT.as_secs()))?
    }

    async fn run_bridge(&self, request: BridgeRequest<'_>) -> Result<Value, BridgeError> {
        if self.ensure_warm_daemon().await.is_ok() {
            return self
                .run_via_warm_socket(request, false, None, None)
                .await;
        }
        tracing::warn!("warm Centurion daemon unavailable; starting a one-shot core");
        let mut command = Command::new(&self.python);
        command
            .args(["-m", "centurion_cli.remote_bridge"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true);
        if let Ok(home) = std::env::var("CENTURION_HOME") {
            command.env("CENTURION_HOME", &home);
        }
        if let Some(cwd) = bridge_working_directory() {
            command.current_dir(cwd);
        }

        let mut child = command.spawn().map_err(BridgeError::Spawn)?;
        let request_bytes = serialize_bridge_request(&request)?;

        let mut stdin = child.stdin.take().expect("piped stdin was requested");
        stdin
            .write_all(&request_bytes)
            .await
            .map_err(BridgeError::Write)?;
        stdin.shutdown().await.map_err(BridgeError::Write)?;

        let output = timeout(BRIDGE_TIMEOUT, child.wait_with_output())
            .await
            .map_err(|_| BridgeError::Timeout(BRIDGE_TIMEOUT.as_secs()))?
            .map_err(BridgeError::Wait)?;

        let stdout = std::str::from_utf8(&output.stdout).map_err(|error| {
            BridgeError::InvalidResponse(serde_json::Error::io(io::Error::new(
                io::ErrorKind::InvalidData,
                error,
            )))
        })?;
        // When stray lines exist, take the last non-empty JSON object.
        parse_final_json(stdout)
    }

    async fn run_bridge_chat(
        &self,
        request: BridgeRequest<'_>,
        events: bool,
        event_tx: Option<mpsc::Sender<BridgeTurnEvent>>,
        mut approval_rx: Option<mpsc::Receiver<BridgeApprovalDecision>>,
    ) -> Result<Value, BridgeError> {
        if self.ensure_warm_daemon().await.is_ok() {
            return self
                .run_via_warm_socket(request, events, event_tx, approval_rx)
                .await;
        }
        tracing::warn!("warm Centurion daemon unavailable; starting a one-shot core for Chat");
        let mut command = Command::new(&self.python);
        command
            .args(["-m", "centurion_cli.remote_bridge"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true);
        if events {
            command.env("CENTURION_REMOTE_EVENTS", "1");
        }
        if let Ok(home) = std::env::var("CENTURION_HOME") {
            command.env("CENTURION_HOME", &home);
        }
        if let Some(cwd) = bridge_working_directory() {
            command.current_dir(cwd);
        }

        let mut child = command.spawn().map_err(BridgeError::Spawn)?;
        let request_bytes = serialize_bridge_request_line(&request)?;

        let mut stdin = child.stdin.take().expect("piped stdin was requested");
        stdin
            .write_all(&request_bytes)
            .await
            .map_err(BridgeError::Write)?;
        if !events {
            stdin.shutdown().await.map_err(BridgeError::Write)?;
        }

        let stdout = child.stdout.take().expect("piped stdout was requested");
        let mut lines = BufReader::new(stdout).lines();
        let mut final_response: Option<Value> = None;

        let wait_fut = child.wait();
        tokio::pin!(wait_fut);

        let outcome = timeout(BRIDGE_TIMEOUT, async {
            loop {
                tokio::select! {
                    biased;
                    decision = async {
                        match approval_rx.as_mut() {
                            Some(rx) => rx.recv().await,
                            None => std::future::pending().await,
                        }
                    } => {
                        if let Some(decision) = decision {
                            let payload = serde_json::json!({
                                "action": "approval_respond",
                                "session_key": decision.session_key,
                                "choice": decision.choice,
                                "all": decision.resolve_all,
                            });
                            let mut line = serde_json::to_vec(&payload)
                                .map_err(BridgeError::InvalidResponse)?;
                            line.push(b'\n');
                            stdin.write_all(&line).await.map_err(BridgeError::Write)?;
                            stdin.flush().await.map_err(BridgeError::Write)?;
                        }
                    }
                    line = lines.next_line() => {
                        let line = line.map_err(BridgeError::Wait)?;
                        let Some(line) = line else {
                            break;
                        };
                        let trimmed = line.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        let value: Value = serde_json::from_str(trimmed)
                            .map_err(BridgeError::InvalidResponse)?;
                        // Never treat mid-turn activity NDJSON as the chat final.
                        if value.get("centurion_event").is_some() {
                            if let Some(tx) = &event_tx {
                                if let Some(event) = turn_event_from_ndjson(&value) {
                                    let _ = tx.send(event).await;
                                }
                            }
                            continue;
                        }
                        if is_bridge_chat_final(&value) {
                            final_response = Some(value);
                            break;
                        }
                    }
                    status = &mut wait_fut => {
                        let _ = status.map_err(BridgeError::Wait)?;
                        break;
                    }
                }
            }
            // Drain remaining lines for a final JSON object if needed.
            while final_response.is_none() {
                match lines.next_line().await {
                    Ok(Some(line)) => {
                        let trimmed = line.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
                            if value.get("centurion_event").is_some() {
                                continue;
                            }
                            if is_bridge_chat_final(&value) {
                                final_response = Some(value);
                                break;
                            }
                        }
                    }
                    Ok(None) | Err(_) => break,
                }
            }
            final_response.ok_or_else(|| {
                BridgeError::InvalidResponse(serde_json::Error::io(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "bridge closed without a final JSON response",
                )))
            })
        })
        .await
        .map_err(|_| BridgeError::Timeout(BRIDGE_TIMEOUT.as_secs()))?;

        if events {
            let _ = stdin.shutdown().await;
        }
        outcome
    }
}

fn serialize_bridge_request(request: &BridgeRequest<'_>) -> Result<Vec<u8>, BridgeError> {
    let mut body =
        serde_json::to_value(request).expect("bridge request is always serializable");
    if let Value::Object(map) = &mut body {
        if let Some(Value::Object(extra_map)) = map.remove("extra") {
            for (key, value) in extra_map {
                map.insert(key, value);
            }
        }
    }
    serde_json::to_vec(&body).map_err(BridgeError::InvalidResponse)
}

fn serialize_bridge_request_line(request: &BridgeRequest<'_>) -> Result<Vec<u8>, BridgeError> {
    let mut bytes = serialize_bridge_request(request)?;
    bytes.push(b'\n');
    Ok(bytes)
}

fn turn_event_from_ndjson(value: &Value) -> Option<BridgeTurnEvent> {
    match value.get("centurion_event").and_then(|v| v.as_str())? {
        "approval_request" => Some(BridgeTurnEvent::Approval(BridgeApprovalEvent {
            approval_id: value_string(value, "approval_id").unwrap_or_default(),
            session_key: value_string(value, "session_key").unwrap_or_default(),
            command: value_string(value, "command").unwrap_or_default(),
            description: value_string(value, "description").unwrap_or_default(),
            pattern_key: value_string(value, "pattern_key").unwrap_or_default(),
            choices: value
                .get("choices")
                .and_then(|item| item.as_array())
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
        })),
        "activity" | "tool_progress" | "status" => {
            let message = value_string(value, "text")
                .or_else(|| value_string(value, "line"))
                .or_else(|| value_string(value, "message"))
                .or_else(|| value_string(value, "preview"))
                .filter(|s| !s.trim().is_empty())?;
            Some(BridgeTurnEvent::Activity {
                message,
                kind: value_string(value, "kind")
                    .or_else(|| value_string(value, "event"))
                    .unwrap_or_else(|| "status".to_owned()),
                tool: value_string(value, "tool"),
            })
        }
        "stream_delta" | "partial" => {
            let text = value_string(value, "text")
                .or_else(|| value_string(value, "delta"))
                .filter(|s| !s.is_empty())?;
            Some(BridgeTurnEvent::StreamDelta { text })
        }
        _ => None,
    }
}

fn is_bridge_chat_final(value: &Value) -> bool {
    if value.get("centurion_event").is_some() {
        return false;
    }
    let action = value
        .get("action")
        .and_then(|item| item.as_str())
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    if action == "chat" {
        return true;
    }
    // Explicit chat success with reply text (legacy shapes omit action).
    let ok = value.get("ok").and_then(|item| item.as_bool()) == Some(true);
    let has_text = ["text", "reply", "response"]
        .iter()
        .any(|key| {
            value
                .get(*key)
                .and_then(|item| item.as_str())
                .map(|s| !s.trim().is_empty())
                .unwrap_or(false)
        });
    ok && has_text && (action.is_empty() || action == "chat")
}

fn parse_final_json(stdout: &str) -> Result<Value, BridgeError> {
    let mut last_err = None;
    for line in stdout.lines().rev() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        match serde_json::from_str::<Value>(trimmed) {
            Ok(value) if is_bridge_chat_final(&value) => return Ok(value),
            Ok(_) => continue,
            Err(error) => last_err = Some(error),
        }
    }
    // Whole-buffer fallback for legacy single-object responses.
    match serde_json::from_str(stdout.trim()) {
        Ok(value) if is_bridge_chat_final(&value) => Ok(value),
        Ok(_) => Err(BridgeError::InvalidResponse(serde_json::Error::io(
            io::Error::new(
                io::ErrorKind::InvalidData,
                "bridge stdout had JSON but no chat final",
            ),
        ))),
        Err(error) => Err(BridgeError::InvalidResponse(last_err.unwrap_or(error))),
    }
}

fn value_bool(value: &Value, key: &str) -> bool {
    value
        .get(key)
        .and_then(|item| item.as_bool())
        .unwrap_or(false)
}

fn value_bool_opt(value: &Value, key: &str) -> Option<bool> {
    value.get(key).and_then(|item| item.as_bool())
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(|item| item.as_str())
        .map(str::to_owned)
        .filter(|item| !item.is_empty())
}

fn response_message(response: &Value) -> String {
    if let Some(message) = value_string(response, "message") {
        return message;
    }
    value_string(response, "error").unwrap_or_default()
}

fn bridge_working_directory() -> Option<PathBuf> {
    for key in ["TERMINAL_CWD", "CENTURION_AI_REPO"] {
        if let Ok(path) = std::env::var(key) {
            let candidate = PathBuf::from(path);
            if candidate.is_dir() {
                return Some(candidate);
            }
        }
    }

    std::env::var("CENTURION_HOME")
        .ok()
        .map(PathBuf::from)
        .filter(|path| path.is_dir())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invoke_passthrough_keeps_domain_payload_keys() {
        let response = serde_json::json!({
            "ok": true,
            "id": "req-1",
            "soul": {"identity": "Keeper"},
            "mission": {"statement": "Ship Remote"},
            "oversight": {"autonomy": "balanced"},
            "plans": [{"id": "p1"}],
            "plan": {"id": "p1"},
            "templates": [],
            "snapshot": {"hot": 1},
        });
        assert!(value_bool(&response, "ok"));
        assert!(response.get("soul").is_some());
        assert!(response.get("mission").is_some());
        assert!(response.get("oversight").is_some());
        assert!(response.get("plans").is_some());
        assert_eq!(response_message(&response), "");
    }

    #[test]
    fn default_bridge_socket_path_is_under_run() {
        let path = PythonBridge::bridge_socket_path();
        assert_eq!(path.file_name().and_then(|n| n.to_str()), Some("bridge.sock"));
        assert!(
            path.components()
                .any(|c| c.as_os_str() == "run"),
            "expected run/bridge.sock, got {}",
            path.display()
        );
    }

    #[test]
    fn response_message_prefers_message_over_error() {
        let response = serde_json::json!({
            "ok": false,
            "message": "friendly",
            "error": "raw",
        });
        assert_eq!(response_message(&response), "friendly");
    }

    #[test]
    fn parse_final_json_skips_event_lines() {
        let stdout = concat!(
            r#"{"centurion_event":"approval_request","command":"rm -rf /"}"#,
            "\n",
            r#"{"ok":true,"text":"done","session_id":"remote_abc"}"#,
            "\n",
        );
        let value = parse_final_json(stdout).expect("parse");
        assert_eq!(value["text"], "done");
        assert_eq!(value["session_id"], "remote_abc");
    }

    #[test]
    fn turn_event_parses_activity_and_approval() {
        let activity = serde_json::json!({
            "centurion_event": "activity",
            "kind": "tool",
            "tool": "terminal",
            "text": "$ ls"
        });
        match turn_event_from_ndjson(&activity).expect("activity") {
            BridgeTurnEvent::Activity {
                message,
                kind,
                tool,
            } => {
                assert_eq!(message, "$ ls");
                assert_eq!(kind, "tool");
                assert_eq!(tool.as_deref(), Some("terminal"));
            }
            other => panic!("expected activity, got {other:?}"),
        }

        let approval = serde_json::json!({
            "centurion_event": "approval_request",
            "approval_id": "a1",
            "session_key": "s1",
            "command": "rm -rf /",
            "description": "Dangerous"
        });
        match turn_event_from_ndjson(&approval).expect("approval") {
            BridgeTurnEvent::Approval(ev) => {
                assert_eq!(ev.approval_id, "a1");
                assert_eq!(ev.command, "rm -rf /");
            }
            other => panic!("expected approval, got {other:?}"),
        }

        let delta = serde_json::json!({
            "centurion_event": "stream_delta",
            "text": "Hello"
        });
        match turn_event_from_ndjson(&delta).expect("delta") {
            BridgeTurnEvent::StreamDelta { text } => assert_eq!(text, "Hello"),
            other => panic!("expected stream delta, got {other:?}"),
        }
    }
}

#[derive(Debug, Default)]
pub struct EchoBridge;

#[async_trait]
impl AgentBridge for EchoBridge {
    async fn chat(
        &self,
        _request_id: &str,
        text: &str,
        session_id: Option<&str>,
        _life_inject: Option<Value>,
        _event_tx: Option<mpsc::Sender<BridgeTurnEvent>>,
        _approval_rx: Option<mpsc::Receiver<BridgeApprovalDecision>>,
    ) -> Result<BridgeChatResult, BridgeError> {
        Ok(BridgeChatResult {
            text: format!("[Development echo] {text}"),
            recovered: false,
            recovery_message: None,
            routed_display_name: None,
            code: None,
            session_id: session_id.map(str::to_owned),
        })
    }

    async fn invoke(
        &self,
        request_id: &str,
        action: &str,
        _payload: Value,
    ) -> Result<Value, BridgeError> {
        Ok(serde_json::json!({
            "ok": true,
            "status": {
                "provider": "echo",
                "model": "echo-model",
                "health": "ok",
                "health_message": format!("echo {action}"),
            },
            "request_id": request_id,
        }))
    }
}
