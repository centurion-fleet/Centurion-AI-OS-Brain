//! Long-lived remote pairing tokens for authenticated iPhone linking.
//!
//! Secrets are shown once at creation; only SHA-256 hashes are persisted.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Connection string prefix: `token:<secret>@<host>:<port>`
pub const CONNECTION_STRING_PREFIX: &str = "token:";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PairingTokenRecord {
    pub id: String,
    pub token_hash: String,
    pub label: String,
    pub created_at: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bound_fingerprint: Option<String>,
    #[serde(default)]
    pub revoked: bool,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct PairingDocument {
    #[serde(default)]
    tokens: Vec<PairingTokenRecord>,
}

#[derive(Debug)]
pub struct PairingTokenStore {
    path: PathBuf,
    document: PairingDocument,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingValidationError {
    InvalidToken,
    TokenRevoked,
    BoundToOtherDevice,
}

impl PairingTokenStore {
    pub fn load(path: impl Into<PathBuf>) -> io::Result<Self> {
        let path = path.into();
        let document = match fs::read(&path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => PairingDocument::default(),
            Err(error) => return Err(error),
        };
        Ok(Self { path, document })
    }

    pub fn default_path() -> io::Result<PathBuf> {
        if let Some(home) = std::env::var_os("CENTURION_HOME") {
            return Ok(PathBuf::from(home)
                .join("remote")
                .join("pairing-tokens.json"));
        }
        let home = std::env::var_os("HOME")
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))?;
        Ok(PathBuf::from(home)
            .join(".centurion")
            .join("remote")
            .join("pairing-tokens.json"))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn tokens(&self) -> &[PairingTokenRecord] {
        &self.document.tokens
    }

    /// True when at least one non-revoked token can still be used for pairing
    /// (unbound, or already bound — reconnect uses device approval, but we
    /// still treat the store as "remote mode active" when any live token exists).
    pub fn has_active_tokens(&self) -> bool {
        self.document.tokens.iter().any(|token| !token.revoked)
    }

    /// True when remote pairing is required for unpaired fingerprints:
    /// at least one non-revoked token exists.
    pub fn requires_pair_for_new_devices(&self) -> bool {
        self.has_active_tokens()
    }

    pub fn reload_from_disk(&mut self) -> io::Result<()> {
        let reloaded = Self::load(&self.path)?;
        self.document = reloaded.document;
        Ok(())
    }

    /// Create a new long-lived pairing token. Returns `(record, plaintext_secret)`.
    pub fn create_token(&mut self, label: String) -> io::Result<(PairingTokenRecord, String)> {
        let secret = generate_token_secret();
        let record = PairingTokenRecord {
            id: Uuid::new_v4().to_string(),
            token_hash: hash_token(&secret),
            label,
            created_at: unix_timestamp(),
            bound_fingerprint: None,
            revoked: false,
        };
        self.document.tokens.push(record.clone());
        self.persist()?;
        Ok((record, secret))
    }

    /// Validate a plaintext token and bind it to `fingerprint` on first use.
    /// If already bound to the same fingerprint, succeeds. If bound to another, fails.
    pub fn validate_and_bind(
        &mut self,
        plaintext: &str,
        fingerprint: &str,
    ) -> Result<(), PairingValidationError> {
        let hash = hash_token(plaintext);
        let Some(token) = self
            .document
            .tokens
            .iter_mut()
            .find(|token| token.token_hash == hash)
        else {
            return Err(PairingValidationError::InvalidToken);
        };
        if token.revoked {
            return Err(PairingValidationError::TokenRevoked);
        }
        match &token.bound_fingerprint {
            None => {
                token.bound_fingerprint = Some(fingerprint.to_owned());
            }
            Some(bound) if bound == fingerprint => {}
            Some(_) => return Err(PairingValidationError::BoundToOtherDevice),
        }
        self.persist()
            .map_err(|_| PairingValidationError::InvalidToken)?;
        Ok(())
    }

    pub fn revoke(&mut self, id_or_prefix: &str) -> io::Result<bool> {
        let mut found = false;
        for token in &mut self.document.tokens {
            if token.id == id_or_prefix || token.id.starts_with(id_or_prefix) {
                if !token.revoked {
                    token.revoked = true;
                    found = true;
                }
            }
        }
        if found {
            self.persist()?;
        }
        Ok(found)
    }

    fn persist(&self) -> io::Result<()> {
        let parent = self.path.parent().unwrap_or_else(|| Path::new("."));
        fs::create_dir_all(parent)?;
        let temporary = self.path.with_extension("json.tmp");
        let bytes = serde_json::to_vec_pretty(&self.document).map_err(io::Error::other)?;
        fs::write(&temporary, bytes)?;
        fs::rename(temporary, &self.path)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&self.path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}

/// Build `token:<secret>@<host>:<port>`.
pub fn format_connection_string(secret: &str, host: &str, port: u16) -> String {
    format!("{CONNECTION_STRING_PREFIX}{secret}@{host}:{port}")
}

/// Parse `token:<secret>@<host>:<port>` (port optional, defaults to 9119).
pub fn parse_connection_string(input: &str) -> Option<(String, String, u16)> {
    let trimmed = input.trim();
    let rest = trimmed.strip_prefix(CONNECTION_STRING_PREFIX)?;
    let (secret, hostport) = rest.split_once('@')?;
    if secret.is_empty() || hostport.is_empty() {
        return None;
    }
    let (host, port) = match hostport.rsplit_once(':') {
        Some((host, port_str)) if !host.is_empty() => {
            let port: u16 = port_str.parse().ok()?;
            (host.to_owned(), port)
        }
        _ => (hostport.to_owned(), centurion_common::DEFAULT_PORT),
    };
    Some((secret.to_owned(), host, port))
}

fn hash_token(plaintext: &str) -> String {
    let digest = Sha256::digest(plaintext.as_bytes());
    hex::encode(digest)
}

fn generate_token_secret() -> String {
    // 128+ bits of entropy as URL-safe hex (32 bytes → 64 hex chars).
    let mut bytes = [0_u8; 32];
    getrandom_fill(&mut bytes);
    hex::encode(bytes)
}

fn getrandom_fill(buf: &mut [u8]) {
    // Prefer OS randomness via uuid's underlying getrandom when available;
    // fall back to combining uuid + timestamp entropy.
    for chunk in buf.chunks_mut(16) {
        let id = Uuid::new_v4();
        let bytes = id.as_bytes();
        let n = chunk.len().min(bytes.len());
        chunk[..n].copy_from_slice(&bytes[..n]);
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
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("centurion-pairing-{name}-{nanos}.json"))
    }

    #[test]
    fn create_validate_bind_and_reject_other_device() {
        let path = temp_path("bind");
        let mut store = PairingTokenStore::load(&path).expect("load");
        let (_record, secret) = store
            .create_token("iPhone".to_owned())
            .expect("create");
        assert!(store.requires_pair_for_new_devices());

        store
            .validate_and_bind(&secret, "fingerprint-a")
            .expect("bind");
        store
            .validate_and_bind(&secret, "fingerprint-a")
            .expect("same device ok");
        assert_eq!(
            store.validate_and_bind(&secret, "fingerprint-b"),
            Err(PairingValidationError::BoundToOtherDevice)
        );

        let _ = fs::remove_file(path);
    }

    #[test]
    fn invalid_and_revoked_tokens() {
        let path = temp_path("revoke");
        let mut store = PairingTokenStore::load(&path).expect("load");
        let (record, secret) = store.create_token("lab".to_owned()).expect("create");
        assert_eq!(
            store.validate_and_bind("not-a-real-token", "fp"),
            Err(PairingValidationError::InvalidToken)
        );
        assert!(store.revoke(&record.id).expect("revoke"));
        assert_eq!(
            store.validate_and_bind(&secret, "fp"),
            Err(PairingValidationError::TokenRevoked)
        );
        let _ = fs::remove_file(path);
    }

    #[test]
    fn connection_string_round_trip() {
        let formatted = format_connection_string("abc123", "brain.example.com", 9119);
        assert_eq!(formatted, "token:abc123@brain.example.com:9119");
        let parsed = parse_connection_string(&formatted).expect("parse");
        assert_eq!(
            parsed,
            ("abc123".to_owned(), "brain.example.com".to_owned(), 9119)
        );
        let no_port = parse_connection_string("token:xyz@10.0.0.1").expect("parse");
        assert_eq!(no_port.2, centurion_common::DEFAULT_PORT);
    }

    #[test]
    fn secret_not_persisted_plaintext() {
        let path = temp_path("plain");
        let mut store = PairingTokenStore::load(&path).expect("load");
        let (_record, secret) = store.create_token("x".to_owned()).expect("create");
        let raw = fs::read_to_string(&path).expect("read");
        assert!(!raw.contains(&secret));
        assert!(raw.contains("token_hash"));
        let _ = fs::remove_file(path);
    }
}
