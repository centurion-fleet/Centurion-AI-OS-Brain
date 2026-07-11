use async_trait::async_trait;
use serde::{Deserialize, Serialize};
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
    async fn chat(&self, request_id: &str, text: &str) -> Result<String, BridgeError>;
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
    #[error("{0}")]
    Agent(String),
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
    text: &'a str,
}

#[derive(Deserialize)]
struct BridgeResponse {
    ok: bool,
    #[serde(default)]
    text: String,
    #[serde(default)]
    error: String,
}

#[async_trait]
impl AgentBridge for PythonBridge {
    async fn chat(&self, request_id: &str, text: &str) -> Result<String, BridgeError> {
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

        let request = serde_json::to_vec(&BridgeRequest {
            id: request_id,
            text,
        })
        .expect("bridge request is always serializable");

        let mut stdin = child.stdin.take().expect("piped stdin was requested");
        stdin
            .write_all(&request)
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
        let response: BridgeResponse =
            serde_json::from_str(stdout.trim()).map_err(BridgeError::InvalidResponse)?;

        if response.ok {
            Ok(response.text)
        } else {
            Err(BridgeError::Agent(response.error))
        }
    }
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
    async fn chat(&self, _request_id: &str, text: &str) -> Result<String, BridgeError> {
        Ok(format!("[Development echo] {text}"))
    }
}
