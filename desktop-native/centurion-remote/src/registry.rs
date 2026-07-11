use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DeviceRecord {
    pub fingerprint: String,
    pub name: String,
    pub approved_at: u64,
    pub last_seen_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PendingDevice {
    pub fingerprint: String,
    pub name: String,
    pub last_seen_at: u64,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct RegistryDocument {
    #[serde(default)]
    devices: Vec<DeviceRecord>,
    #[serde(default)]
    pending: Vec<PendingDevice>,
}

#[derive(Debug)]
pub struct DeviceRegistry {
    path: PathBuf,
    document: RegistryDocument,
}

impl DeviceRegistry {
    pub fn load(path: impl Into<PathBuf>) -> io::Result<Self> {
        let path = path.into();
        let document = match fs::read(&path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => RegistryDocument::default(),
            Err(error) => return Err(error),
        };
        Ok(Self { path, document })
    }

    pub fn default_path() -> io::Result<PathBuf> {
        if let Some(home) = std::env::var_os("CENTURION_HOME") {
            return Ok(PathBuf::from(home).join("remote").join("devices.json"));
        }
        let home = std::env::var_os("HOME")
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))?;
        Ok(PathBuf::from(home)
            .join(".centurion")
            .join("remote")
            .join("devices.json"))
    }

    pub fn fingerprint(public_key: &[u8]) -> String {
        let digest = Sha256::digest(public_key);
        hex::encode(&digest[..16])
    }

    pub fn is_approved(&self, fingerprint: &str) -> bool {
        self.document
            .devices
            .iter()
            .any(|device| device.fingerprint == fingerprint)
    }

    pub fn approve(&mut self, fingerprint: &str, name: String) -> io::Result<()> {
        let now = unix_timestamp();
        if let Some(device) = self
            .document
            .devices
            .iter_mut()
            .find(|device| device.fingerprint == fingerprint)
        {
            device.name = name;
            device.last_seen_at = now;
        } else {
            self.document.devices.push(DeviceRecord {
                fingerprint: fingerprint.to_owned(),
                name,
                approved_at: now,
                last_seen_at: now,
            });
        }
        self.document
            .pending
            .retain(|device| device.fingerprint != fingerprint);
        self.persist()
    }

    pub fn note_pending(&mut self, fingerprint: String, name: String) -> io::Result<()> {
        let now = unix_timestamp();
        if let Some(device) = self
            .document
            .pending
            .iter_mut()
            .find(|device| device.fingerprint == fingerprint)
        {
            device.name = name;
            device.last_seen_at = now;
        } else {
            self.document.pending.push(PendingDevice {
                fingerprint,
                name,
                last_seen_at: now,
            });
        }
        self.persist()
    }

    pub fn touch(&mut self, fingerprint: &str) -> io::Result<()> {
        if let Some(device) = self
            .document
            .devices
            .iter_mut()
            .find(|device| device.fingerprint == fingerprint)
        {
            device.last_seen_at = unix_timestamp();
            self.persist()?;
        }
        Ok(())
    }

    pub fn reload_from_disk(&mut self) -> io::Result<()> {
        let reloaded = Self::load(&self.path)?;
        self.document = reloaded.document;
        Ok(())
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn devices(&self) -> &[DeviceRecord] {
        &self.document.devices
    }

    pub fn pending_devices(&self) -> &[PendingDevice] {
        &self.document.pending
    }

    pub fn revoke(&mut self, fingerprint: &str) -> io::Result<bool> {
        let original_len = self.document.devices.len();
        self.document
            .devices
            .retain(|device| device.fingerprint != fingerprint);
        let removed = self.document.devices.len() != original_len;
        if removed {
            self.persist()?;
        }
        Ok(removed)
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

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn approval_persists_and_reloads() {
        let path = std::env::temp_dir().join(format!(
            "centurion-device-registry-{}.json",
            uuid::Uuid::new_v4()
        ));
        let mut registry = DeviceRegistry::load(&path).expect("load");
        registry
            .approve("fingerprint", "Adrian's iPhone".to_owned())
            .expect("approve");

        let reloaded = DeviceRegistry::load(&path).expect("reload");
        assert!(reloaded.is_approved("fingerprint"));
        assert_eq!(reloaded.devices()[0].name, "Adrian's iPhone");
        let _ = fs::remove_file(path);
    }

    #[test]
    fn reload_picks_up_external_approval() {
        let path = std::env::temp_dir().join(format!(
            "centurion-device-registry-reload-{}.json",
            uuid::Uuid::new_v4()
        ));
        let mut server_registry = DeviceRegistry::load(&path).expect("load");
        let mut cli_registry = DeviceRegistry::load(&path).expect("load");
        cli_registry
            .approve("fingerprint", "Adrian's iPhone".to_owned())
            .expect("approve");
        assert!(!server_registry.is_approved("fingerprint"));
        server_registry.reload_from_disk().expect("reload");
        assert!(server_registry.is_approved("fingerprint"));
        let _ = fs::remove_file(path);
    }
}
