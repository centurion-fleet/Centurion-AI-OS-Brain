use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub const SERVICE_TYPE: &str = "_centurion._tcp.local.";
pub const DEFAULT_PORT: u16 = 9119;
pub const KEY_EXCHANGE_TYPE: u8 = 0x01;
pub const PUBLIC_KEY_BYTES: usize = 32;
pub const KEY_EXCHANGE_FRAME_BYTES: usize = 1 + PUBLIC_KEY_BYTES;
pub const FRAME_HEADER_BYTES: usize = 4;
pub const MAX_FRAME_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RemoteMessage {
    Chat {
        id: Uuid,
        text: String,
    },
    ChatResponse {
        id: Uuid,
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        recovered: Option<bool>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        recovery_message: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        routed_display_name: Option<String>,
    },
    ProviderStatus {
        id: Uuid,
    },
    ProviderStatusResponse {
        id: Uuid,
        status: serde_json::Value,
    },
    ProviderOptions {
        id: Uuid,
    },
    ProviderOptionsResponse {
        id: Uuid,
        options: serde_json::Value,
    },
    ProviderValidate {
        id: Uuid,
        provider: String,
        model: String,
    },
    ProviderValidateResponse {
        id: Uuid,
        ok: bool,
        result: serde_json::Value,
    },
    ProviderApply {
        id: Uuid,
        provider: String,
        model: String,
    },
    ProviderApplyResponse {
        id: Uuid,
        ok: bool,
        result: serde_json::Value,
    },
    ProviderRestore {
        id: Uuid,
    },
    ProviderRestoreResponse {
        id: Uuid,
        ok: bool,
        restored: bool,
        result: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    HealthCheck {
        id: Uuid,
    },
    HealthCheckResponse {
        id: Uuid,
        ok: bool,
        snapshot: serde_json::Value,
        summary: String,
        thinking_health: String,
    },
    SupportBundle {
        id: Uuid,
    },
    SupportBundleResponse {
        id: Uuid,
        ok: bool,
        code: String,
        expires_at: String,
        summary: String,
        thinking_health: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    SupportAutoFix {
        id: Uuid,
    },
    SupportAutoFixResponse {
        id: Uuid,
        ok: bool,
        message: String,
        thinking_health: String,
        restored: bool,
    },
    SwarmSnapshot {
        id: Uuid,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        since: Option<String>,
    },
    SwarmSnapshotResponse {
        id: Uuid,
        snapshot: serde_json::Value,
    },
    SwarmConnect {
        id: Uuid,
        token: String,
        install_id: String,
        project_id: String,
    },
    SwarmConnectResponse {
        id: Uuid,
        ok: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        result: Option<serde_json::Value>,
    },
    SwarmInvite {
        id: Uuid,
        invited_customer_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        project_id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        role: Option<String>,
    },
    SwarmInviteResponse {
        id: Uuid,
        ok: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        result: Option<serde_json::Value>,
    },
    BeneficiarySnapshot {
        id: Uuid,
    },
    BeneficiarySnapshotResponse {
        id: Uuid,
        snapshot: serde_json::Value,
    },
    BeneficiarySetFamilyMember {
        id: Uuid,
        first_name: String,
    },
    BeneficiarySetFamilyMemberResponse {
        id: Uuid,
        ok: bool,
        snapshot: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    BeneficiarySubmitColleague {
        id: Uuid,
        name: String,
        email: String,
        phone: String,
        non_family_attested: bool,
    },
    BeneficiarySubmitColleagueResponse {
        id: Uuid,
        ok: bool,
        snapshot: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    RemoteModelCatalog {
        id: Uuid,
    },
    RemoteModelCatalogResponse {
        id: Uuid,
        catalog: serde_json::Value,
    },
    RemoteModelApply {
        id: Uuid,
        connector_id: String,
    },
    RemoteModelApplyResponse {
        id: Uuid,
        ok: bool,
        result: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        routing_mode: Option<String>,
    },
    RemoteModelSaveKey {
        id: Uuid,
        connector_id: String,
        key: String,
    },
    RemoteModelSaveKeyResponse {
        id: Uuid,
        ok: bool,
        result: serde_json::Value,
    },
    RemoteRoutingMode {
        id: Uuid,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mode: Option<String>,
    },
    RemoteRoutingModeResponse {
        id: Uuid,
        ok: bool,
        routing_mode: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    TelegramImportBundle {
        id: Uuid,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        session_id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        dry_run: Option<bool>,
    },
    TelegramImportBundleResponse {
        id: Uuid,
        ok: bool,
        bundle: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    TelegramImportPreview {
        id: Uuid,
    },
    TelegramImportPreviewResponse {
        id: Uuid,
        ok: bool,
        bundle: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    Ready,
    Ping,
    Pong,
    Error {
        id: Option<Uuid>,
        code: String,
        message: String,
        retryable: bool,
    },
}

impl RemoteMessage {
    pub fn to_json(&self) -> Result<Vec<u8>, ProtocolError> {
        serde_json::to_vec(self).map_err(ProtocolError::Json)
    }

    pub fn from_json(payload: &[u8]) -> Result<Self, ProtocolError> {
        serde_json::from_slice(payload).map_err(ProtocolError::Json)
    }
}

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("frame length {0} exceeds the maximum")]
    FrameTooLarge(usize),
    #[error("invalid key exchange frame")]
    InvalidKeyExchange,
    #[error("invalid JSON message: {0}")]
    Json(serde_json::Error),
}

pub fn encode_frame(payload: &[u8]) -> Result<Vec<u8>, ProtocolError> {
    if payload.len() > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(payload.len()));
    }

    let length =
        u32::try_from(payload.len()).map_err(|_| ProtocolError::FrameTooLarge(payload.len()))?;
    let mut frame = Vec::with_capacity(FRAME_HEADER_BYTES + payload.len());
    frame.extend_from_slice(&length.to_be_bytes());
    frame.extend_from_slice(payload);
    Ok(frame)
}

#[derive(Debug, Default)]
pub struct FrameDecoder {
    buffer: Vec<u8>,
}

impl FrameDecoder {
    pub fn push(&mut self, bytes: &[u8]) -> Result<Vec<Vec<u8>>, ProtocolError> {
        self.buffer.extend_from_slice(bytes);
        let mut frames = Vec::new();

        loop {
            if self.buffer.len() < FRAME_HEADER_BYTES {
                break;
            }

            let length = u32::from_be_bytes(
                self.buffer[..FRAME_HEADER_BYTES]
                    .try_into()
                    .expect("frame header length was checked"),
            ) as usize;

            if length > MAX_FRAME_BYTES {
                return Err(ProtocolError::FrameTooLarge(length));
            }

            let frame_end = FRAME_HEADER_BYTES + length;
            if self.buffer.len() < frame_end {
                break;
            }

            let payload = self.buffer[FRAME_HEADER_BYTES..frame_end].to_vec();
            self.buffer.drain(..frame_end);
            frames.push(payload);
        }

        Ok(frames)
    }

    pub fn buffered_len(&self) -> usize {
        self.buffer.len()
    }
}

pub fn encode_key_exchange(
    public_key: &[u8],
) -> Result<[u8; KEY_EXCHANGE_FRAME_BYTES], ProtocolError> {
    if public_key.len() != PUBLIC_KEY_BYTES {
        return Err(ProtocolError::InvalidKeyExchange);
    }

    let mut frame = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    frame[0] = KEY_EXCHANGE_TYPE;
    frame[1..].copy_from_slice(public_key);
    Ok(frame)
}

pub fn decode_key_exchange(frame: &[u8]) -> Result<[u8; PUBLIC_KEY_BYTES], ProtocolError> {
    if frame.len() != KEY_EXCHANGE_FRAME_BYTES || frame[0] != KEY_EXCHANGE_TYPE {
        return Err(ProtocolError::InvalidKeyExchange);
    }

    let mut public_key = [0_u8; PUBLIC_KEY_BYTES];
    public_key.copy_from_slice(&frame[1..]);
    Ok(public_key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_decoder_handles_fragmented_input() {
        let frame = encode_frame(b"hello").expect("encode");
        let mut decoder = FrameDecoder::default();

        assert!(decoder.push(&frame[..2]).expect("decode").is_empty());
        assert!(decoder.push(&frame[2..5]).expect("decode").is_empty());
        assert_eq!(decoder.push(&frame[5..]).expect("decode"), vec![b"hello"]);
        assert_eq!(decoder.buffered_len(), 0);
    }

    #[test]
    fn frame_decoder_handles_coalesced_frames() {
        let mut bytes = encode_frame(b"one").expect("encode");
        bytes.extend(encode_frame(b"two").expect("encode"));

        let mut decoder = FrameDecoder::default();
        assert_eq!(
            decoder.push(&bytes).expect("decode"),
            vec![b"one".to_vec(), b"two".to_vec()]
        );
    }

    #[test]
    fn key_exchange_round_trip() {
        let key = [7_u8; PUBLIC_KEY_BYTES];
        let frame = encode_key_exchange(&key).expect("encode");
        assert_eq!(decode_key_exchange(&frame).expect("decode"), key);
    }

    #[test]
    fn chat_message_json_round_trip() {
        let message = RemoteMessage::Chat {
            id: Uuid::new_v4(),
            text: "Hello".to_owned(),
        };
        let encoded = message.to_json().expect("serialize");
        assert_eq!(RemoteMessage::from_json(&encoded).expect("parse"), message);
    }
}
