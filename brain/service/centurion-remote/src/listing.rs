use crate::admin::SessionView;
use crate::registry::{DeviceRecord, DeviceRegistry, PendingDevice};
use serde::Serialize;
use std::collections::HashMap;

#[derive(Debug, Serialize)]
pub struct DeviceListing {
    pub approved: Vec<ApprovedDeviceView>,
    pub pending: Vec<PendingDeviceView>,
}

#[derive(Debug, Serialize)]
pub struct ApprovedDeviceView {
    pub fingerprint: String,
    pub name: String,
    pub approved_at: u64,
    pub last_seen_at: u64,
    pub connected: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<uuid::Uuid>,
}

#[derive(Debug, Serialize)]
pub struct PendingDeviceView {
    pub fingerprint: String,
    pub name: String,
    pub last_seen_at: u64,
    pub connected: bool,
}

pub fn build_device_listing(
    registry: &DeviceRegistry,
    live_sessions: &[SessionView],
) -> DeviceListing {
    let live_by_fingerprint: HashMap<&str, &SessionView> = live_sessions
        .iter()
        .map(|session| (session.fingerprint.as_str(), session))
        .collect();

    DeviceListing {
        approved: registry
            .devices()
            .iter()
            .map(|device| {
                approved_view(device, live_by_fingerprint.get(device.fingerprint.as_str()))
            })
            .collect(),
        pending: registry
            .pending_devices()
            .iter()
            .map(pending_view)
            .collect(),
    }
}

fn approved_view(device: &DeviceRecord, live: Option<&&SessionView>) -> ApprovedDeviceView {
    ApprovedDeviceView {
        fingerprint: device.fingerprint.clone(),
        name: device.name.clone(),
        approved_at: device.approved_at,
        last_seen_at: device.last_seen_at,
        connected: live.is_some(),
        peer: live.map(|session| session.peer.clone()),
        session_id: live.map(|session| session.id),
    }
}

fn pending_view(device: &PendingDevice) -> PendingDeviceView {
    PendingDeviceView {
        fingerprint: device.fingerprint.clone(),
        name: device.name.clone(),
        last_seen_at: device.last_seen_at,
        connected: false,
    }
}
