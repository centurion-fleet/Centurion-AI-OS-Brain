use crate::session_registry::{ActiveSession, SessionRegistry};
use serde::{Deserialize, Serialize};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum AdminRequest {
    ListSessions,
    Ping,
    ProviderStatus,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum AdminResponse {
    Sessions { sessions: Vec<SessionView> },
    Pong,
    ProviderStatus { payload: serde_json::Value },
    Error { message: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SessionView {
    pub id: Uuid,
    pub fingerprint: String,
    pub peer: String,
    pub connected_at: u64,
    pub last_activity_at: u64,
}

#[derive(Clone)]
pub struct AdminState {
    pub sessions: Arc<SessionRegistry>,
}

pub fn default_socket_path() -> io::Result<PathBuf> {
    if let Some(home) = std::env::var_os("CENTURION_HOME") {
        return Ok(PathBuf::from(home).join("remote").join("admin.sock"));
    }
    let home = std::env::var_os("HOME")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))?;
    Ok(PathBuf::from(home)
        .join(".centurion")
        .join("remote")
        .join("admin.sock"))
}

pub async fn run(state: AdminState, path: PathBuf) -> io::Result<()> {
    if path.exists() {
        let _ = std::fs::remove_file(&path);
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let listener = UnixListener::bind(&path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    }

    loop {
        let (stream, _) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(error) = handle_connection(state, stream).await {
                tracing::warn!("admin request failed: {error}");
            }
        });
    }
}

async fn handle_connection(state: AdminState, stream: UnixStream) -> io::Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();
    let Some(line) = lines.next_line().await? else {
        return Ok(());
    };

    let response = match serde_json::from_str::<AdminRequest>(&line) {
        Ok(AdminRequest::ListSessions) => AdminResponse::Sessions {
            sessions: state
                .sessions
                .list()
                .await
                .into_iter()
                .map(session_view_from_active)
                .collect(),
        },
        Ok(AdminRequest::Ping) => AdminResponse::Pong,
        Ok(AdminRequest::ProviderStatus) => AdminResponse::ProviderStatus {
            payload: read_provider_status_json(),
        },
        Err(error) => AdminResponse::Error {
            message: format!("invalid admin request: {error}"),
        },
    };

    let payload = serde_json::to_string(&response).map_err(io::Error::other)?;
    writer.write_all(payload.as_bytes()).await?;
    writer.write_all(b"\n").await?;
    Ok(())
}

pub async fn query_sessions(path: &Path) -> io::Result<Vec<SessionView>> {
    let mut stream = match UnixStream::connect(path).await {
        Ok(stream) => stream,
        Err(error) if error.kind() == io::ErrorKind::ConnectionRefused => return Ok(Vec::new()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };

    let request = serde_json::to_string(&AdminRequest::ListSessions).map_err(io::Error::other)?;
    stream.write_all(request.as_bytes()).await?;
    stream.write_all(b"\n").await?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).await?;
    match serde_json::from_str::<AdminResponse>(&line) {
        Ok(AdminResponse::Sessions { sessions }) => Ok(sessions),
        Ok(AdminResponse::Error { message }) => Err(io::Error::other(message)),
        Ok(AdminResponse::Pong | AdminResponse::ProviderStatus { .. }) => Ok(Vec::new()),
        Err(error) => Err(io::Error::other(error)),
    }
}

fn read_provider_status_json() -> serde_json::Value {
    let centurion = std::env::var("HOME")
        .ok()
        .map(|home| format!("{home}/.local/bin/centurion"))
        .filter(|path| Path::new(path).is_file())
        .unwrap_or_else(|| "centurion".to_owned());
    let output = std::process::Command::new(centurion)
        .args(["provider", "status", "--json"])
        .output();
    match output {
        Ok(output) if output.status.success() => serde_json::from_slice(&output.stdout)
            .unwrap_or_else(|error| serde_json::json!({ "ok": false, "error": error.to_string() })),
        Ok(output) => serde_json::json!({
            "ok": false,
            "error": String::from_utf8_lossy(&output.stderr).to_string(),
        }),
        Err(error) => serde_json::json!({ "ok": false, "error": error.to_string() }),
    }
}

fn session_view_from_active(session: ActiveSession) -> SessionView {
    SessionView {
        id: session.id,
        fingerprint: session.fingerprint,
        peer: session.peer.to_string(),
        connected_at: session.connected_at,
        last_activity_at: session.last_activity_at,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session_registry::SessionRegistry;
    use std::net::{Ipv4Addr, SocketAddr};
    use uuid::Uuid;

    #[tokio::test]
    async fn admin_lists_live_sessions() {
        let path = PathBuf::from(format!("/tmp/c-admin-{}.sock", Uuid::new_v4()));
        let sessions = SessionRegistry::new();
        let peer = SocketAddr::new(Ipv4Addr::LOCALHOST.into(), 42);
        sessions.register("fingerprint".to_owned(), peer).await;

        let state = AdminState {
            sessions: sessions.clone(),
        };
        let listener = tokio::spawn(run(state, path.clone()));
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;

        let listed = query_sessions(&path).await.expect("query");
        listener.abort();
        let _ = std::fs::remove_file(path);

        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].fingerprint, "fingerprint");
    }
}
