use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActiveSession {
    pub id: Uuid,
    pub fingerprint: String,
    pub peer: SocketAddr,
    pub connected_at: u64,
    pub last_activity_at: u64,
}

#[derive(Default)]
struct SessionStore {
    sessions: HashMap<Uuid, ActiveSession>,
    by_fingerprint: HashMap<String, Uuid>,
}

pub struct SessionRegistry {
    store: Mutex<SessionStore>,
}

impl SessionRegistry {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            store: Mutex::new(SessionStore::default()),
        })
    }

    pub async fn register(&self, fingerprint: String, peer: SocketAddr) -> Uuid {
        let mut store = self.store.lock().await;
        if let Some(old_id) = store.by_fingerprint.remove(&fingerprint) {
            store.sessions.remove(&old_id);
        }

        let now = unix_timestamp();
        let id = Uuid::new_v4();
        store.sessions.insert(
            id,
            ActiveSession {
                id,
                fingerprint: fingerprint.clone(),
                peer,
                connected_at: now,
                last_activity_at: now,
            },
        );
        store.by_fingerprint.insert(fingerprint, id);
        id
    }

    pub async fn touch(&self, id: Uuid) {
        let mut store = self.store.lock().await;
        if let Some(session) = store.sessions.get_mut(&id) {
            session.last_activity_at = unix_timestamp();
        }
    }

    pub async fn unregister(&self, id: Uuid) {
        let mut store = self.store.lock().await;
        if let Some(session) = store.sessions.remove(&id) {
            store.by_fingerprint.remove(&session.fingerprint);
        }
    }

    pub async fn list(&self) -> Vec<ActiveSession> {
        let store = self.store.lock().await;
        let mut sessions: Vec<ActiveSession> = store.sessions.values().cloned().collect();
        sessions.sort_by_key(|session| session.connected_at);
        sessions
    }

    pub async fn is_connected(&self, fingerprint: &str) -> bool {
        self.store
            .lock()
            .await
            .by_fingerprint
            .contains_key(fingerprint)
    }
}

pub struct SessionGuard {
    registry: Arc<SessionRegistry>,
    id: Uuid,
}

impl SessionGuard {
    pub fn new(registry: Arc<SessionRegistry>, id: Uuid) -> Self {
        Self { registry, id }
    }
}

impl Drop for SessionGuard {
    fn drop(&mut self) {
        let registry = self.registry.clone();
        let id = self.id;
        tokio::spawn(async move {
            registry.unregister(id).await;
        });
    }
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{Ipv4Addr, SocketAddr};

    #[tokio::test]
    async fn register_touch_unregister_round_trip() {
        let registry = SessionRegistry::new();
        let peer = SocketAddr::new(Ipv4Addr::LOCALHOST.into(), 42);
        let id = registry.register("fingerprint".to_owned(), peer).await;
        assert!(registry.is_connected("fingerprint").await);
        registry.touch(id).await;
        registry.unregister(id).await;
        assert!(!registry.is_connected("fingerprint").await);
    }

    #[tokio::test]
    async fn reconnect_replaces_existing_session() {
        let registry = SessionRegistry::new();
        let peer = SocketAddr::new(Ipv4Addr::LOCALHOST.into(), 42);
        let first = registry.register("fingerprint".to_owned(), peer).await;
        let second = registry.register("fingerprint".to_owned(), peer).await;
        assert_ne!(first, second);
        assert_eq!(registry.list().await.len(), 1);
    }
}
