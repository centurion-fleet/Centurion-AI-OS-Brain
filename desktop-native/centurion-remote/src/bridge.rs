use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::io;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::time::timeout;

const BRIDGE_TIMEOUT: Duration = Duration::from_secs(180);

#[async_trait]
pub trait AgentBridge: Send + Sync {
    async fn chat(&self, request_id: &str, text: &str) -> Result<BridgeChatResult, BridgeError>;
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

#[derive(Serialize)]
struct BridgeRequest<'a> {
    id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    action: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<&'a str>,
    #[serde(flatten)]
    extra: Value,
}

#[derive(Deserialize)]
struct BridgeResponse {
    ok: bool,
    #[serde(default)]
    text: String,
    #[serde(default)]
    error: String,
    #[serde(default)]
    message: String,
    #[serde(default)]
    code: Option<String>,
    #[serde(default)]
    retryable: Option<bool>,
    #[serde(default)]
    recovered: Option<bool>,
    #[serde(default)]
    recovery_message: Option<String>,
    #[serde(default)]
    status: Option<Value>,
    #[serde(default)]
    options: Option<Value>,
    #[serde(default)]
    result: Option<Value>,
    #[serde(default)]
    restored: Option<bool>,
    #[serde(default)]
    snapshot: Option<Value>,
    #[serde(default)]
    summary: Option<String>,
    #[serde(default)]
    thinking_health: Option<String>,
    #[serde(default)]
    expires_at: Option<String>,
    #[serde(default)]
    catalog: Option<Value>,
    #[serde(default)]
    bundle: Option<Value>,
    #[serde(default)]
    routing_mode: Option<String>,
    #[serde(default)]
    routed_display_name: Option<String>,
}

#[async_trait]
impl AgentBridge for PythonBridge {
    async fn chat(&self, request_id: &str, text: &str) -> Result<BridgeChatResult, BridgeError> {
        let response = self
            .run_bridge(BridgeRequest {
                id: request_id,
                action: Some("chat"),
                text: Some(text),
                extra: Value::Null,
            })
            .await?;

        if response.ok {
            return Ok(BridgeChatResult {
                text: response.text,
                recovered: response.recovered.unwrap_or(false),
                recovery_message: response.recovery_message,
                routed_display_name: response.routed_display_name,
                code: response.code,
            });
        }

        Err(BridgeError::Agent {
            message: response_message(&response),
            code: response.code,
            retryable: response.retryable.unwrap_or(true),
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

        if response.ok {
            let mut value = serde_json::json!({ "ok": true });
            if let Some(status) = response.status {
                value["status"] = status;
            }
            if let Some(options) = response.options {
                value["options"] = options;
            }
            if let Some(result) = response.result {
                value["result"] = result;
            }
            if let Some(restored) = response.restored {
                value["restored"] = Value::Bool(restored);
            }
            if !response.message.is_empty() {
                value["message"] = Value::String(response.message.clone());
            }
            if let Some(snapshot) = response.snapshot {
                value["snapshot"] = snapshot;
            }
            if let Some(summary) = &response.summary {
                value["summary"] = Value::String(summary.clone());
            }
            if let Some(thinking_health) = &response.thinking_health {
                value["thinking_health"] = Value::String(thinking_health.clone());
            }
            if let Some(code) = &response.code {
                value["code"] = Value::String(code.clone());
            }
            if let Some(expires_at) = &response.expires_at {
                value["expires_at"] = Value::String(expires_at.clone());
            }
            if let Some(catalog) = response.catalog {
                value["catalog"] = catalog;
            }
            if let Some(bundle) = response.bundle {
                value["bundle"] = bundle;
            }
            if let Some(routing_mode) = &response.routing_mode {
                value["routing_mode"] = Value::String(routing_mode.clone());
            }
            return Ok(value);
        }

        Err(BridgeError::Agent {
            message: response_message(&response),
            code: response.code,
            retryable: response.retryable.unwrap_or(false),
        })
    }
}

impl PythonBridge {
    async fn run_bridge(&self, request: BridgeRequest<'_>) -> Result<BridgeResponse, BridgeError> {
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

        let mut body =
            serde_json::to_value(&request).expect("bridge request is always serializable");
        if let Value::Object(map) = &mut body {
            if let Some(Value::Object(extra_map)) = map.remove("extra") {
                for (key, value) in extra_map {
                    map.insert(key, value);
                }
            }
        }
        let request_bytes =
            serde_json::to_vec(&body).expect("bridge request is always serializable");

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
        serde_json::from_str(stdout.trim()).map_err(BridgeError::InvalidResponse)
    }
}

fn response_message(response: &BridgeResponse) -> String {
    if !response.message.is_empty() {
        return response.message.clone();
    }
    response.error.clone()
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

#[derive(Debug, Default)]
pub struct EchoBridge;

#[async_trait]
impl AgentBridge for EchoBridge {
    async fn chat(&self, _request_id: &str, text: &str) -> Result<BridgeChatResult, BridgeError> {
        Ok(BridgeChatResult {
            text: format!("[Development echo] {text}"),
            recovered: false,
            recovery_message: None,
            routed_display_name: None,
            code: None,
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
