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
