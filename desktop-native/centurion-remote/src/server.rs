use crate::bridge::{AgentBridge, BridgeError};
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
                info!(
                    %peer,
                    %fingerprint,
                    request_id = %id,
                    bytes = text.len(),
                    "iPhone chat request received"
                );
                let response = state.bridge.chat(&id.to_string(), &text).await;
                if !reload_is_approved(&state, &fingerprint).await? {
                    send_revoked(&mut stream, &session).await?;
                    return Err(SessionError::ApprovalRequired(fingerprint));
                }
                match response {
                    Ok(result) => {
                        info!(
                            %peer,
                            %fingerprint,
                            request_id = %id,
                            bytes = result.text.len(),
                            "Centurion response ready"
                        );
                        RemoteMessage::ChatResponse {
                            id,
                            text: result.text,
                            recovered: result.recovered.then_some(true),
                            recovery_message: result.recovery_message,
                            routed_display_name: result.routed_display_name,
                        }
                    }
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ProviderStatus { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "provider_status", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::ProviderStatusResponse {
                        id,
                        status: payload
                            .get("status")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ProviderOptions { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "provider_options", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::ProviderOptionsResponse {
                        id,
                        options: payload
                            .get("options")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ProviderValidate { id, provider, model } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "provider_validate",
                        serde_json::json!({ "provider": provider, "model": model }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::ProviderValidateResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        result: payload
                            .get("result")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ProviderApply { id, provider, model } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "provider_apply",
                        serde_json::json!({ "provider": provider, "model": model }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::ProviderApplyResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        result: payload
                            .get("result")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ProviderRestore { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "provider_restore", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::ProviderRestoreResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        restored: payload
                            .get("restored")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false),
                        result: payload
                            .get("result")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::HealthCheck { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "health_check", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::HealthCheckResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(true),
                        snapshot: payload
                            .get("snapshot")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        summary: payload
                            .get("summary")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        thinking_health: payload
                            .get("thinking_health")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_owned(),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SupportBundle { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "support_bundle", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::SupportBundleResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(true),
                        code: payload
                            .get("code")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        expires_at: payload
                            .get("expires_at")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        summary: payload
                            .get("summary")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        thinking_health: payload
                            .get("thinking_health")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_owned(),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SupportAutoFix { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "support_auto_fix", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::SupportAutoFixResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        thinking_health: payload
                            .get("thinking_health")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_owned(),
                        restored: payload
                            .get("restored")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SwarmSnapshot { id, since } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "swarm_snapshot",
                        serde_json::json!({ "since": since }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SwarmSnapshotResponse {
                        id,
                        snapshot: payload
                            .get("snapshot")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::BeneficiarySnapshot { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "beneficiary_snapshot", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::BeneficiarySnapshotResponse {
                        id,
                        snapshot: payload
                            .get("snapshot")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::BeneficiarySetFamilyMember { id, first_name } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "beneficiary_set_family_member",
                        serde_json::json!({ "first_name": first_name }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::BeneficiarySetFamilyMemberResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(true),
                        snapshot: payload
                            .get("snapshot")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::BeneficiarySubmitColleague {
                id,
                name,
                email,
                phone,
                non_family_attested,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "beneficiary_submit_colleague",
                        serde_json::json!({
                            "name": name,
                            "email": email,
                            "phone": phone,
                            "non_family_attested": non_family_attested,
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::BeneficiarySubmitColleagueResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(true),
                        snapshot: payload
                            .get("snapshot")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::RemoteModelCatalog { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "remote_model_catalog", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::RemoteModelCatalogResponse {
                        id,
                        catalog: payload
                            .get("catalog")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::RemoteModelApply { id, connector_id } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "remote_model_apply",
                        serde_json::json!({ "connector_id": connector_id }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::RemoteModelApplyResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        result: payload
                            .get("result")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        routing_mode: payload
                            .get("routing_mode")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::RemoteModelSaveKey {
                id,
                connector_id,
                key,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "remote_model_save_key",
                        serde_json::json!({ "connector_id": connector_id, "key": key }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::RemoteModelSaveKeyResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        result: payload
                            .get("result")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::RemoteRoutingMode { id, mode } => {
                let body = if let Some(mode) = mode {
                    serde_json::json!({ "mode": mode })
                } else {
                    serde_json::json!({})
                };
                match state
                    .bridge
                    .invoke(&id.to_string(), "remote_routing_mode", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::RemoteRoutingModeResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(true),
                        routing_mode: payload
                            .get("routing_mode")
                            .and_then(|v| v.as_str())
                            .unwrap_or("manual")
                            .to_owned(),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::TelegramImportBundle {
                id,
                session_id,
                dry_run,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "telegram_import_bundle",
                        serde_json::json!({
                            "session_id": session_id,
                            "dry_run": dry_run,
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::TelegramImportBundleResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        bundle: payload
                            .get("bundle")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::TelegramImportPreview { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "telegram_import_preview", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::TelegramImportPreviewResponse {
                        id,
                        ok: payload.get("ok").and_then(|v| v.as_bool()).unwrap_or(false),
                        bundle: payload
                            .get("bundle")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
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

fn bridge_error_response(id: Option<uuid::Uuid>, error: BridgeError) -> RemoteMessage {
    match error {
        BridgeError::Agent {
            message,
            code,
            retryable,
        } => {
            warn!(?id, %message, ?code, "Centurion bridge request failed");
            RemoteMessage::Error {
                id,
                code: code.unwrap_or_else(|| "CENTURION_UNAVAILABLE".to_owned()),
                message,
                retryable,
            }
        }
        other => {
            warn!(?id, %other, "Centurion bridge transport failed");
            RemoteMessage::Error {
                id,
                code: "CENTURION_UNAVAILABLE".to_owned(),
                message: other.to_string(),
                retryable: true,
            }
        }
    }
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
