use crate::bridge::AgentBridge;
use crate::crypto::{ServerIdentity, ServerSession};
use crate::registry::DeviceRegistry;
use crate::session_registry::{SessionGuard, SessionRegistry};
use centurion_common::{
    FRAME_HEADER_BYTES, KEY_EXCHANGE_FRAME_BYTES, MAX_FRAME_BYTES, RemoteMessage,
    decode_key_exchange, encode_frame, encode_key_exchange,
};
use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;
use tracing::{info, warn};

#[derive(Clone)]
pub struct ServerState {
    pub bridge: Arc<dyn AgentBridge>,
    pub registry: Arc<Mutex<DeviceRegistry>>,
    pub sessions: Arc<SessionRegistry>,
    pub identity: Arc<ServerIdentity>,
    pub auto_approve: bool,
}

pub async fn run(listener: TcpListener, state: ServerState) -> io::Result<()> {
    loop {
        let (stream, peer) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(error) = handle_connection(stream, peer, state).await {
                warn!(%peer, %error, "iPhone session ended");
            }
        });
    }
}

async fn handle_connection(
    mut stream: TcpStream,
    peer: SocketAddr,
    state: ServerState,
) -> Result<(), SessionError> {
    stream.set_nodelay(true)?;

    let mut handshake = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream.read_exact(&mut handshake).await?;
    let client_public_key = decode_key_exchange(&handshake)?;
    let fingerprint = DeviceRegistry::fingerprint(&client_public_key);
    let session = ServerSession::establish(&client_public_key, &state.identity)?;
    let response = encode_key_exchange(&session.public_key())?;
    stream.write_all(&response).await?;

    let approved = reload_is_approved(&state, &fingerprint).await?;

    if !approved && state.auto_approve {
        let name = format!("iPhone {}", &fingerprint[..8]);
        state.registry.lock().await.approve(&fingerprint, name)?;
    } else if !approved {
        state
            .registry
            .lock()
            .await
            .note_pending(fingerprint.clone(), format!("iPhone {}", &fingerprint[..8]))?;
        let message = RemoteMessage::Error {
            id: None,
            code: "PAIRING_APPROVAL_REQUIRED".to_owned(),
            message: format!(
                "Approve device fingerprint {fingerprint} on your Centurion, then try again."
            ),
            retryable: true,
        };
        write_message(&mut stream, &session, &message).await?;
        return Err(SessionError::ApprovalRequired(fingerprint));
    }

    state.registry.lock().await.touch(&fingerprint)?;
    write_message(&mut stream, &session, &RemoteMessage::Ready).await?;
    let session_id = state
        .sessions
        .register(fingerprint.clone(), peer)
        .await;
    let _session_guard = SessionGuard::new(state.sessions.clone(), session_id);
    info!(%peer, %fingerprint, "iPhone connected");

    let mut approval_poll = tokio::time::interval(Duration::from_secs(5));
    approval_poll.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        if !reload_is_approved(&state, &fingerprint).await? {
            send_revoked(&mut stream, &session).await?;
            return Err(SessionError::ApprovalRequired(fingerprint));
        }

        let encrypted = tokio::select! {
            frame = read_frame(&mut stream) => frame?,
            _ = approval_poll.tick() => {
                continue;
            }
        };
        let plaintext = session.decrypt(&encrypted)?;
        let message = RemoteMessage::from_json(&plaintext)?;

        let response = match message {
            RemoteMessage::Chat { id, text } => {
                let response = state.bridge.chat(&id.to_string(), &text).await;
                if !reload_is_approved(&state, &fingerprint).await? {
                    send_revoked(&mut stream, &session).await?;
                    return Err(SessionError::ApprovalRequired(fingerprint));
                }
                match response {
                    Ok(text) => RemoteMessage::ChatResponse { id, text },
                    Err(error) => RemoteMessage::Error {
                        id: Some(id),
                        code: "CENTURION_UNAVAILABLE".to_owned(),
                        message: error.to_string(),
                        retryable: true,
                    },
                }
            }
            RemoteMessage::Ping => RemoteMessage::Pong,
            _ => RemoteMessage::Error {
                id: None,
                code: "UNSUPPORTED_MESSAGE".to_owned(),
                message: "This message type is not supported.".to_owned(),
                retryable: false,
            },
        };

        write_message(&mut stream, &session, &response).await?;
        state.sessions.touch(session_id).await;
        state.registry.lock().await.touch(&fingerprint)?;
    }
}

async fn send_revoked(
    stream: &mut TcpStream,
    session: &ServerSession,
) -> Result<(), SessionError> {
    let message = RemoteMessage::Error {
        id: None,
        code: "DEVICE_REVOKED".to_owned(),
        message: "This iPhone is no longer approved on your Centurion.".to_owned(),
        retryable: false,
    };
    write_message(stream, session, &message).await
}

async fn reload_is_approved(state: &ServerState, fingerprint: &str) -> Result<bool, SessionError> {
    let mut registry = state.registry.lock().await;
    registry
        .reload_from_disk()
        .map_err(|error| SessionError::Registry(error.to_string()))?;
    Ok(registry.is_approved(fingerprint))
}

async fn read_frame(stream: &mut TcpStream) -> Result<Vec<u8>, SessionError> {
    let mut header = [0_u8; FRAME_HEADER_BYTES];
    stream.read_exact(&mut header).await?;
    let length = u32::from_be_bytes(header) as usize;
    if length > MAX_FRAME_BYTES {
        return Err(SessionError::FrameTooLarge(length));
    }

    let mut payload = vec![0_u8; length];
    stream.read_exact(&mut payload).await?;
    Ok(payload)
}

async fn write_message(
    stream: &mut TcpStream,
    session: &ServerSession,
    message: &RemoteMessage,
) -> Result<(), SessionError> {
    let plaintext = message.to_json()?;
    let encrypted = session.encrypt(&plaintext);
    let frame = encode_frame(&encrypted)?;
    stream.write_all(&frame).await?;
    Ok(())
}

#[derive(Debug, thiserror::Error)]
enum SessionError {
    #[error("network error: {0}")]
    Network(#[from] io::Error),
    #[error("protocol error: {0}")]
    Protocol(#[from] centurion_common::ProtocolError),
    #[error("cryptography error: {0}")]
    Crypto(#[from] crate::crypto::CryptoError),
    #[error("device approval is required for {0}")]
    ApprovalRequired(String),
    #[error("device registry error: {0}")]
    Registry(String),
    #[error("encrypted frame length {0} exceeds the maximum")]
    FrameTooLarge(usize),
}
