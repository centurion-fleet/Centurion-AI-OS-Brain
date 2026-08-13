use centurion_common::SERVICE_TYPE;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;

#[derive(Debug, thiserror::Error)]
pub enum DiscoveryError {
    #[error("mDNS daemon could not start: {0}")]
    Daemon(#[source] mdns_sd::Error),
    #[error("mDNS service could not be created: {0}")]
    Service(#[source] mdns_sd::Error),
    #[error("mDNS service could not be registered: {0}")]
    Register(#[source] mdns_sd::Error),
}

pub struct Advertisement {
    daemon: ServiceDaemon,
    fullname: String,
}

impl Advertisement {
    pub fn start(instance_name: &str, port: u16, version: &str) -> Result<Self, DiscoveryError> {
        let daemon = ServiceDaemon::new().map_err(DiscoveryError::Daemon)?;
        let hostname = format!(
            "{}.local.",
            hostname::get()
                .unwrap_or_default()
                .to_string_lossy()
                .trim_end_matches(".local")
        );
        let properties = HashMap::from([
            ("version".to_owned(), version.to_owned()),
            ("hostname".to_owned(), hostname.clone()),
            ("requires_pairing".to_owned(), "true".to_owned()),
            ("transport".to_owned(), "tcp-v1".to_owned()),
        ]);
        let service =
            ServiceInfo::new(SERVICE_TYPE, instance_name, &hostname, "", port, properties)
                .map_err(DiscoveryError::Service)?
                .enable_addr_auto();
        let fullname = service.get_fullname().to_owned();
        daemon.register(service).map_err(DiscoveryError::Register)?;

        Ok(Self { daemon, fullname })
    }
}

impl Drop for Advertisement {
    fn drop(&mut self) {
        let _ = self.daemon.unregister(&self.fullname);
        let _ = self.daemon.shutdown();
    }
}
