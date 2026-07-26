use crate::bridge::{AgentBridge, BridgeApprovalDecision, BridgeError};
use crate::crypto::{ServerIdentity, ServerSession};
use crate::pairing::{PairingTokenStore, PairingValidationError};
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
use tokio::sync::{mpsc, Mutex};
use tracing::{info, warn};

#[derive(Clone)]
pub struct ServerState {
    pub bridge: Arc<dyn AgentBridge>,
    pub registry: Arc<Mutex<DeviceRegistry>>,
    pub pairing: Arc<Mutex<PairingTokenStore>>,
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

#[allow(clippy::too_many_lines)]
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

    // Unbox & Go: first phone on the LAN may Confirm without a QR when no
    // devices are linked yet. Once any device is approved, QR / explicit
    // approve is required again.
    let virgin_lan_auto = {
        let registry = state.registry.lock().await;
        registry.devices().is_empty() && is_private_lan_peer(peer)
    };

    if !approved && (state.auto_approve || virgin_lan_auto) {
        let name = format!("iPhone {}", &fingerprint[..8]);
        state.registry.lock().await.approve(&fingerprint, name)?;
        if virgin_lan_auto && !state.auto_approve {
            info!(%peer, %fingerprint, "Virgin LAN link auto-approved");
        }
    } else if !approved {
        let requires_pair = {
            let mut pairing = state.pairing.lock().await;
            pairing
                .reload_from_disk()
                .map_err(|error| SessionError::Registry(error.to_string()))?;
            pairing.requires_pair_for_new_devices()
        };

        if requires_pair {
            complete_remote_pair(&mut stream, &session, &state, &fingerprint).await?;
        } else {
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
    }

    state.registry.lock().await.touch(&fingerprint)?;
    write_message(&mut stream, &session, &RemoteMessage::Ready).await?;
    let session_id = state.sessions.register(fingerprint.clone(), peer).await;
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
            RemoteMessage::Chat {
                id,
                text,
                session_id,
            } => {
                info!(
                    %peer,
                    %fingerprint,
                    request_id = %id,
                    bytes = text.len(),
                    "iPhone chat request received"
                );
                let request_id = id.to_string();
                let (event_tx, mut event_rx) = mpsc::channel(8);
                let (approval_tx, approval_rx) = mpsc::channel(8);
                let bridge = Arc::clone(&state.bridge);
                let chat_fut = bridge.chat(
                    &request_id,
                    &text,
                    session_id.as_deref(),
                    Some(event_tx),
                    Some(approval_rx),
                );
                tokio::pin!(chat_fut);
                let chat_response = loop {
                    tokio::select! {
                        Some(event) = event_rx.recv() => {
                            let push = RemoteMessage::ApprovalRequest {
                                id,
                                approval_id: event.approval_id,
                                session_key: event.session_key,
                                command: event.command,
                                description: event.description,
                                pattern_key: (!event.pattern_key.is_empty())
                                    .then_some(event.pattern_key),
                                choices: event.choices,
                            };
                            write_message(&mut stream, &session, &push).await?;
                        }
                        frame = read_frame(&mut stream) => {
                            let encrypted = frame?;
                            let plaintext = session.decrypt(&encrypted)?;
                            let inbound = RemoteMessage::from_json(&plaintext)?;
                            match inbound {
                                RemoteMessage::ApprovalRespond {
                                    id: respond_id,
                                    approval_id,
                                    session_key,
                                    choice,
                                    all,
                                } => {
                                    let key = session_key.unwrap_or(approval_id);
                                    let _ = approval_tx
                                        .send(BridgeApprovalDecision {
                                            session_key: key,
                                            choice,
                                            resolve_all: all.unwrap_or(false),
                                        })
                                        .await;
                                    let ack = RemoteMessage::ApprovalRespondResponse {
                                        id: respond_id,
                                        ok: true,
                                        resolved: 1,
                                    };
                                    write_message(&mut stream, &session, &ack).await?;
                                }
                                RemoteMessage::Ping => {
                                    write_message(&mut stream, &session, &RemoteMessage::Pong)
                                        .await?;
                                }
                                other => {
                                    warn!(
                                        %peer,
                                        message = ?other,
                                        "Ignoring unexpected message during chat turn"
                                    );
                                }
                            }
                        }
                        result = &mut chat_fut => {
                            if !reload_is_approved(&state, &fingerprint).await? {
                                send_revoked(&mut stream, &session).await?;
                                return Err(SessionError::ApprovalRequired(fingerprint));
                            }
                            break match result {
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
                                        session_id: result.session_id,
                                    }
                                }
                                Err(error) => bridge_error_response(Some(id), error),
                            };
                        }
                    }
                };
                chat_response
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
            RemoteMessage::ProviderValidate {
                id,
                provider,
                model,
            } => {
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        result: payload
                            .get("result")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ProviderApply {
                id,
                provider,
                model,
            } => {
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        restored: payload
                            .get("restored")
                            .and_then(serde_json::Value::as_bool)
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
                            .and_then(serde_json::Value::as_bool)
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
            RemoteMessage::SwarmConnect {
                id,
                token,
                install_id,
                project_id,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "swarm_connect",
                        serde_json::json!({
                            "token": token,
                            "install_id": install_id,
                            "project_id": project_id,
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SwarmConnectResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                        result: payload.get("result").cloned(),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SwarmInvite {
                id,
                invited_customer_id,
                project_id,
                role,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "swarm_invite",
                        serde_json::json!({
                            "invited_customer_id": invited_customer_id,
                            "project_id": project_id,
                            "role": role,
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SwarmInviteResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                        result: payload.get("result").cloned(),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SwarmResolveSignal {
                id,
                signal_id,
                choice_note,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "swarm_resolve_signal",
                        serde_json::json!({
                            "signal_id": signal_id,
                            "choice_note": choice_note,
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SwarmResolveSignalResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                        result: payload.get("result").cloned(),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SwarmCreateBoard {
                id,
                name,
                objective,
                mission_id,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "swarm_create_board",
                        serde_json::json!({
                            "name": name,
                            "objective": objective,
                            "mission_id": mission_id,
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SwarmCreateBoardResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                        result: payload.get("result").cloned(),
                        snapshot: payload.get("snapshot").cloned(),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::BeneficiarySnapshot { id } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "beneficiary_snapshot",
                        serde_json::json!({}),
                    )
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
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
                    .invoke(
                        &id.to_string(),
                        "remote_model_catalog",
                        serde_json::json!({}),
                    )
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
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
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
                    .invoke(
                        &id.to_string(),
                        "telegram_import_preview",
                        serde_json::json!({}),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::TelegramImportPreviewResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
            RemoteMessage::OversightGet { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "oversight_get", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::OversightGetResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        oversight: payload
                            .get("oversight")
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
            RemoteMessage::OversightPut {
                id,
                oversight,
                apply_level_preset,
            } => {
                let mut body = serde_json::json!({ "oversight": oversight });
                if let Some(preset) = apply_level_preset {
                    body["apply_level_preset"] = serde_json::Value::Bool(preset);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "oversight_put", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::OversightPutResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        oversight: payload
                            .get("oversight")
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
            RemoteMessage::SoulGet { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "soul_get", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::SoulGetResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        soul: payload
                            .get("soul")
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
            RemoteMessage::SoulPut { id, soul, markdown } => {
                let mut body = serde_json::Map::new();
                if let Some(soul) = soul {
                    body.insert("soul".to_owned(), soul);
                }
                if let Some(markdown) = markdown {
                    body.insert(
                        "markdown".to_owned(),
                        serde_json::Value::String(markdown),
                    );
                }
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "soul_put",
                        serde_json::Value::Object(body),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SoulPutResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        soul: payload
                            .get("soul")
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
            RemoteMessage::MissionGet { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "mission_get", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::MissionGetResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        mission: payload
                            .get("mission")
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
            RemoteMessage::MissionPut {
                id,
                mission,
                markdown,
            } => {
                let mut body = serde_json::Map::new();
                if let Some(mission) = mission {
                    body.insert("mission".to_owned(), mission);
                }
                if let Some(markdown) = markdown {
                    body.insert(
                        "markdown".to_owned(),
                        serde_json::Value::String(markdown),
                    );
                }
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "mission_put",
                        serde_json::Value::Object(body),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::MissionPutResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        mission: payload
                            .get("mission")
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
            RemoteMessage::MemoryHorizonSnapshot { id } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "memory_horizon_snapshot",
                        serde_json::json!({}),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::MemoryHorizonSnapshotResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
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
            RemoteMessage::PlansList { id, status } => {
                let mut body = serde_json::Map::new();
                if let Some(status) = status {
                    body.insert("status".to_owned(), serde_json::Value::String(status));
                }
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "plans_list",
                        serde_json::Value::Object(body),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::PlansListResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plans: payload
                            .get("plans")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!([])),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::PlanGet { id, plan_id } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "plan_get",
                        serde_json::json!({ "plan_id": plan_id }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanGetResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plan: payload
                            .get("plan")
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
            RemoteMessage::PlanPut { id, plan } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "plan_put",
                        serde_json::json!({ "plan": plan }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanPutResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plan: payload
                            .get("plan")
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
            RemoteMessage::PlanDecide {
                id,
                plan_id,
                choice,
                note,
                reviewer_customer_id,
            } => {
                let mut body = serde_json::json!({
                    "plan_id": plan_id,
                    "choice": choice,
                });
                if let Some(note) = note {
                    body["note"] = serde_json::Value::String(note);
                }
                if let Some(reviewer) = reviewer_customer_id {
                    body["reviewer_customer_id"] = serde_json::Value::String(reviewer);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "plan_decide", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanDecideResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plan: payload
                            .get("plan")
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
            RemoteMessage::PlanShare {
                id,
                plan_id,
                reviewer_customer_id,
                role,
                board_id,
            } => {
                let mut body = serde_json::json!({
                    "plan_id": plan_id,
                    "reviewer_customer_id": reviewer_customer_id,
                });
                if let Some(role) = role {
                    body["role"] = serde_json::Value::String(role);
                }
                if let Some(board_id) = board_id {
                    body["board_id"] = serde_json::Value::String(board_id);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "plan_share", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanShareResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plan: payload
                            .get("plan")
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
            RemoteMessage::PlanComment {
                id,
                plan_id,
                body,
                author,
            } => {
                let mut req = serde_json::json!({
                    "plan_id": plan_id,
                    "body": body,
                });
                if let Some(author) = author {
                    req["author"] = serde_json::Value::String(author);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "plan_comment", req)
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanCommentResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plan: payload
                            .get("plan")
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
            RemoteMessage::PlanTemplatesList { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "plan_templates_list", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanTemplatesListResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        templates: payload
                            .get("templates")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!([])),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::PlanTemplateInstantiate {
                id,
                template_id,
                overrides,
            } => {
                let mut body = serde_json::json!({ "template_id": template_id });
                if let Some(overrides) = overrides {
                    body["overrides"] = overrides;
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "plan_template_instantiate", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanTemplateInstantiateResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        plan: payload
                            .get("plan")
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
            RemoteMessage::PlanSaveTemplate { id, plan_id, title } => {
                let mut body = serde_json::json!({ "plan_id": plan_id });
                if let Some(title) = title {
                    body["title"] = serde_json::Value::String(title);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "plan_save_template", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::PlanSaveTemplateResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        template: payload
                            .get("template")
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
            RemoteMessage::GatewayStatus { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "gateway_status", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::GatewayStatusResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        status: payload
                            .get("status")
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
            RemoteMessage::GatewayStart { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "gateway_start", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::GatewayLifecycleResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        status: payload
                            .get("status")
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
            RemoteMessage::GatewayStop { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "gateway_stop", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::GatewayLifecycleResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        status: payload
                            .get("status")
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
            RemoteMessage::GatewayRestart { id } => {
                match state
                    .bridge
                    .invoke(&id.to_string(), "gateway_restart", serde_json::json!({}))
                    .await
                {
                    Ok(payload) => RemoteMessage::GatewayLifecycleResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        status: payload
                            .get("status")
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
            RemoteMessage::GatewayPlatformSet {
                id,
                platform,
                enabled,
                restart,
            } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "gateway_platform_set",
                        serde_json::json!({
                            "platform": platform,
                            "enabled": enabled,
                            "restart": restart.unwrap_or(true),
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::GatewayPlatformSetResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(false),
                        status: payload
                            .get("status")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!({})),
                        message: payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned),
                        restarted: payload.get("restarted").and_then(|v| v.as_bool()),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SessionList { id, limit, source } => {
                let mut body = serde_json::json!({});
                if let Some(limit) = limit {
                    body["limit"] = serde_json::json!(limit);
                }
                if let Some(source) = source {
                    body["source"] = serde_json::json!(source);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "session_list", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::SessionListResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        sessions: payload
                            .get("sessions")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!([])),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SessionNew { id, title } => {
                let mut body = serde_json::json!({});
                if let Some(title) = title {
                    body["title"] = serde_json::json!(title);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "session_new", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::SessionNewResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        session_id: payload
                            .get("session_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SessionResume { id, session_id } => {
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "session_resume",
                        serde_json::json!({ "session_id": session_id }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::SessionResumeResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        session_id: payload
                            .get("session_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        messages: payload
                            .get("messages")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!([])),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::SessionHistory {
                id,
                session_id,
                limit,
            } => {
                let mut body = serde_json::json!({ "session_id": session_id });
                if let Some(limit) = limit {
                    body["limit"] = serde_json::json!(limit);
                }
                match state
                    .bridge
                    .invoke(&id.to_string(), "session_history", body)
                    .await
                {
                    Ok(payload) => RemoteMessage::SessionHistoryResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        session_id: payload
                            .get("session_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_owned(),
                        messages: payload
                            .get("messages")
                            .cloned()
                            .unwrap_or_else(|| serde_json::json!([])),
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
            RemoteMessage::ApprovalRespond {
                id,
                approval_id,
                session_key,
                choice,
                all,
            } => {
                // Outside an active chat turn — resolve via a short bridge invoke.
                let key = session_key.unwrap_or(approval_id);
                match state
                    .bridge
                    .invoke(
                        &id.to_string(),
                        "approval_respond",
                        serde_json::json!({
                            "session_key": key,
                            "choice": choice,
                            "all": all.unwrap_or(false),
                        }),
                    )
                    .await
                {
                    Ok(payload) => RemoteMessage::ApprovalRespondResponse {
                        id,
                        ok: payload
                            .get("ok")
                            .and_then(serde_json::Value::as_bool)
                            .unwrap_or(true),
                        resolved: payload
                            .get("resolved")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0) as u32,
                    },
                    Err(error) => bridge_error_response(Some(id), error),
                }
            }
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

async fn send_revoked(stream: &mut TcpStream, session: &ServerSession) -> Result<(), SessionError> {
    let message = RemoteMessage::Error {
        id: None,
        code: "DEVICE_REVOKED".to_owned(),
        message: "This iPhone is no longer approved on your Centurion.".to_owned(),
        retryable: false,
    };
    write_message(stream, session, &message).await
}

/// Challenge for a remote pairing token, validate, approve + bind fingerprint.
async fn complete_remote_pair(
    stream: &mut TcpStream,
    session: &ServerSession,
    state: &ServerState,
    fingerprint: &str,
) -> Result<(), SessionError> {
    write_message(stream, session, &RemoteMessage::PairRequired).await?;

    let encrypted = tokio::time::timeout(Duration::from_secs(30), read_frame(stream))
        .await
        .map_err(|_| SessionError::PairTimeout)??;
    let plaintext = session.decrypt(&encrypted)?;
    let message = RemoteMessage::from_json(&plaintext)?;

    let token = match message {
        RemoteMessage::Pair { token } => token,
        _ => {
            let rejected = RemoteMessage::PairRejected {
                code: "EXPECTED_PAIR".to_owned(),
                message: "Expected a pairing token message.".to_owned(),
            };
            write_message(stream, session, &rejected).await?;
            return Err(SessionError::PairRejected);
        }
    };

    let bind_result = {
        let mut pairing = state.pairing.lock().await;
        pairing
            .reload_from_disk()
            .map_err(|error| SessionError::Registry(error.to_string()))?;
        pairing.validate_and_bind(&token, fingerprint)
    };

    match bind_result {
        Ok(()) => {
            let name = format!("iPhone {}", &fingerprint[..8.min(fingerprint.len())]);
            state
                .registry
                .lock()
                .await
                .approve(fingerprint, name)
                .map_err(|error| SessionError::Registry(error.to_string()))?;
            info!(%fingerprint, "iPhone paired via remote token");
            Ok(())
        }
        Err(error) => {
            let (code, message) = match error {
                PairingValidationError::InvalidToken => (
                    "INVALID_TOKEN",
                    "That pairing code is not valid. Generate a new one on your Centurion.",
                ),
                PairingValidationError::TokenRevoked => (
                    "TOKEN_REVOKED",
                    "That pairing code was revoked. Generate a new one on your Centurion.",
                ),
                PairingValidationError::BoundToOtherDevice => (
                    "TOKEN_BOUND",
                    "That pairing code is already linked to another iPhone.",
                ),
            };
            write_message(
                stream,
                session,
                &RemoteMessage::PairRejected {
                    code: code.to_owned(),
                    message: message.to_owned(),
                },
            )
            .await?;
            Err(SessionError::PairRejected)
        }
    }
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

/// True for RFC1918 / link-local peers — Unbox Confirm on the home LAN.
/// Loopback is excluded so lab pair-token tests still exercise PairRequired.
fn is_private_lan_peer(peer: SocketAddr) -> bool {
    match peer.ip() {
        std::net::IpAddr::V4(v4) => v4.is_private() || v4.is_link_local(),
        std::net::IpAddr::V6(v6) => {
            // Unique-local (fc00::/7) and link-local — not loopback.
            (v6.segments()[0] & 0xfe00) == 0xfc00 || (v6.segments()[0] & 0xffc0) == 0xfe80
        }
    }
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
    #[error("pairing token rejected")]
    PairRejected,
    #[error("timed out waiting for pairing token")]
    PairTimeout,
    #[error("device registry error: {0}")]
    Registry(String),
    #[error("encrypted frame length {0} exceeds the maximum")]
    FrameTooLarge(usize),
}
