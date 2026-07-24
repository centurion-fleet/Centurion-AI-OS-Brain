use centurion_common::DEFAULT_PORT;
use centurion_remote::admin::{self, AdminState};
use centurion_remote::bridge::{AgentBridge, EchoBridge, PythonBridge};
use centurion_remote::crypto::ServerIdentity;
use centurion_remote::discovery::Advertisement;
use centurion_remote::listing::build_device_listing;
use centurion_remote::pairing::{PairingTokenStore, format_connection_string};
use centurion_remote::registry::DeviceRegistry;
use centurion_remote::server::{self, ServerState};
use centurion_remote::session_registry::SessionRegistry;
use clap::{Parser, Subcommand};
use std::error::Error;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::Mutex;
use tracing::info;

#[derive(Debug, Parser)]
#[command(
    name = "centurion-remote",
    about = "Encrypted remote service for CenturionAI Remote"
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    Serve {
        #[arg(long, default_value_t = SocketAddr::new(
            IpAddr::V4(Ipv4Addr::UNSPECIFIED),
            DEFAULT_PORT
        ))]
        bind: SocketAddr,
        #[arg(long, default_value = "Sovereign AI Brain")]
        name: String,
        #[arg(long)]
        auto_approve: bool,
        #[arg(long)]
        echo: bool,
        #[arg(long, default_value = "python3")]
        python: String,
    },
    Devices {
        #[arg(long)]
        json: bool,
    },
    Sessions {
        #[arg(long)]
        json: bool,
    },
    Approve {
        fingerprint: String,
        #[arg(long, default_value = "iPhone")]
        name: String,
    },
    Revoke {
        fingerprint: String,
    },
    /// Mint a long-lived remote pairing token and print a connection string.
    RemotePair {
        #[arg(long, default_value = "iPhone")]
        label: String,
        /// Host/IP to embed in the connection string (public hostname, tunnel, or LAN).
        #[arg(long)]
        host: Option<String>,
        #[arg(long, default_value_t = DEFAULT_PORT)]
        port: u16,
        #[arg(long)]
        json: bool,
    },
    /// List remote pairing tokens (hashes only; secrets are never stored).
    RemoteTokens {
        #[arg(long)]
        json: bool,
    },
    /// Revoke a remote pairing token by id or id prefix.
    RemoteRevoke {
        id: String,
    },
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(false)
        .compact()
        .init();

    let cli = Cli::parse();
    match cli.command.unwrap_or(Command::Serve {
        bind: SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), DEFAULT_PORT),
        name: "Sovereign AI Brain".to_owned(),
        auto_approve: false,
        echo: false,
        python: "python3".to_owned(),
    }) {
        Command::Serve {
            bind,
            name,
            auto_approve,
            echo,
            python,
        } => serve(bind, &name, auto_approve, echo, &python).await?,
        Command::Devices { json } => {
            let registry = DeviceRegistry::load(DeviceRegistry::default_path()?)?;
            if json {
                let live = admin::query_sessions(&admin::default_socket_path()?)
                    .await
                    .unwrap_or_default();
                let listing = build_device_listing(&registry, &live);
                println!("{}", serde_json::to_string(&listing)?);
            } else if registry.devices().is_empty() && registry.pending_devices().is_empty() {
                println!("No iPhones have been approved.");
            } else {
                let live = admin::query_sessions(&admin::default_socket_path()?)
                    .await
                    .unwrap_or_default();
                let connected: std::collections::HashSet<&str> = live
                    .iter()
                    .map(|session| session.fingerprint.as_str())
                    .collect();
                for device in registry.pending_devices() {
                    println!(
                        "PENDING   {}  {}  last seen {}",
                        device.fingerprint, device.name, device.last_seen_at
                    );
                }
                for device in registry.devices() {
                    let status = if connected.contains(device.fingerprint.as_str()) {
                        "CONNECTED"
                    } else {
                        "APPROVED"
                    };
                    println!(
                        "{status:<9} {}  {}  last seen {}",
                        device.fingerprint, device.name, device.last_seen_at
                    );
                }
            }
        }
        Command::Sessions { json } => {
            let sessions = admin::query_sessions(&admin::default_socket_path()?)
                .await
                .unwrap_or_default();
            if json {
                println!("{}", serde_json::json!({ "sessions": sessions }));
            } else if sessions.is_empty() {
                println!("No iPhones are connected right now.");
            } else {
                for session in sessions {
                    println!(
                        "CONNECTED {}  {}  peer {}  last activity {}",
                        session.fingerprint, session.id, session.peer, session.last_activity_at
                    );
                }
            }
        }
        Command::Approve { fingerprint, name } => {
            let mut registry = DeviceRegistry::load(DeviceRegistry::default_path()?)?;
            registry.approve(&fingerprint, name)?;
            println!("Approved {fingerprint}.");
        }
        Command::Revoke { fingerprint } => {
            let mut registry = DeviceRegistry::load(DeviceRegistry::default_path()?)?;
            if registry.revoke(&fingerprint)? {
                println!("Revoked {fingerprint}.");
            } else {
                println!("No approved device matched {fingerprint}.");
            }
        }
        Command::RemotePair {
            label,
            host,
            port,
            json,
        } => {
            let advertise_host = host.unwrap_or_else(default_advertise_host);
            let mut store = PairingTokenStore::load(PairingTokenStore::default_path()?)?;
            let (record, secret) = store.create_token(label)?;
            let connection = format_connection_string(&secret, &advertise_host, port);
            if json {
                println!(
                    "{}",
                    serde_json::json!({
                        "id": record.id,
                        "label": record.label,
                        "created_at": record.created_at,
                        "host": advertise_host,
                        "port": port,
                        "connection_string": connection,
                        "token": secret,
                    })
                );
            } else {
                println!("Remote pairing token created (id {}).", record.id);
                println!();
                println!("{connection}");
                println!();
                println!(
                    "Paste this into CenturionAI Remote on your iPhone.\n\
                     Expose TCP {port} on this host (Cloudflare Tunnel, reverse proxy, or firewall) \
                     so the phone can reach you away from home.\n\
                     The secret is shown once; only a hash is stored on disk."
                );
                if is_private_or_local_host(&advertise_host) {
                    println!();
                    println!(
                        "Note: {advertise_host} looks like a local address. For away access, \
                         re-run with --host <public-hostname-or-tunnel>."
                    );
                }
            }
        }
        Command::RemoteTokens { json } => {
            let store = PairingTokenStore::load(PairingTokenStore::default_path()?)?;
            if json {
                println!("{}", serde_json::to_string(store.tokens())?);
            } else if store.tokens().is_empty() {
                println!("No remote pairing tokens. Run: centurion-remote remote-pair");
            } else {
                for token in store.tokens() {
                    let status = if token.revoked {
                        "REVOKED"
                    } else if token.bound_fingerprint.is_some() {
                        "BOUND"
                    } else {
                        "OPEN"
                    };
                    let bound = token
                        .bound_fingerprint
                        .as_deref()
                        .unwrap_or("-");
                    println!(
                        "{status:<8} {}  {}  bound {}  created {}",
                        token.id, token.label, bound, token.created_at
                    );
                }
            }
        }
        Command::RemoteRevoke { id } => {
            let mut store = PairingTokenStore::load(PairingTokenStore::default_path()?)?;
            if store.revoke(&id)? {
                println!("Revoked pairing token matching {id}.");
            } else {
                println!("No pairing token matched {id}.");
            }
        }
    }
    Ok(())
}

async fn serve(
    bind: SocketAddr,
    name: &str,
    auto_approve: bool,
    echo: bool,
    python: &str,
) -> Result<(), Box<dyn Error>> {
    sodiumoxide::init().map_err(|()| "libsodium initialization failed")?;
    let listener = TcpListener::bind(bind).await?;
    let local_addr = listener.local_addr()?;
    let _advertisement = Advertisement::start(name, local_addr.port(), env!("CARGO_PKG_VERSION"))?;
    let registry = DeviceRegistry::load(DeviceRegistry::default_path()?)?;
    let pairing = PairingTokenStore::load(PairingTokenStore::default_path()?)?;
    let identity_path = ServerIdentity::default_path()?;
    let identity = ServerIdentity::load_or_create(&identity_path)?;
    let sessions = SessionRegistry::new();
    let admin_path = admin::default_socket_path()?;
    let admin_state = AdminState {
        sessions: sessions.clone(),
    };
    tokio::spawn(async move {
        if let Err(error) = admin::run(admin_state, admin_path).await {
            tracing::warn!("admin socket stopped: {error}");
        }
    });
    let bridge: Arc<dyn AgentBridge> = if echo {
        Arc::new(EchoBridge)
    } else {
        Arc::new(PythonBridge::new(python))
    };

    info!(
        address = %local_addr,
        auto_approve,
        remote_tokens = pairing.has_active_tokens(),
        "Your Centurion is ready for iPhone connections"
    );

    server::run(
        listener,
        ServerState {
            bridge,
            registry: Arc::new(Mutex::new(registry)),
            pairing: Arc::new(Mutex::new(pairing)),
            sessions,
            identity: Arc::new(identity),
            auto_approve,
        },
    )
    .await?;
    Ok(())
}

fn default_advertise_host() -> String {
    if let Ok(host) = std::env::var("CENTURION_REMOTE_ADVERTISE_HOST") {
        let trimmed = host.trim().to_owned();
        if !trimmed.is_empty() {
            return trimmed;
        }
    }
    pairing_lan_host().unwrap_or_else(|| "127.0.0.1".to_owned())
}

fn pairing_lan_host() -> Option<String> {
    // Best-effort: hostname that resolves, else first non-loopback IPv4 via `hostname -I` style.
    if let Ok(name) = hostname::get() {
        if let Ok(s) = name.into_string() {
            let trimmed = s.trim().to_owned();
            if !trimmed.is_empty() && trimmed != "localhost" {
                return Some(trimmed);
            }
        }
    }
    None
}

fn is_private_or_local_host(host: &str) -> bool {
    let lower = host.to_ascii_lowercase();
    if lower == "localhost" || lower.ends_with(".local") {
        return true;
    }
    if let Ok(ip) = host.parse::<IpAddr>() {
        return match ip {
            IpAddr::V4(v4) => {
                v4.is_loopback()
                    || v4.is_private()
                    || v4.is_link_local()
                    || v4.is_unspecified()
            }
            IpAddr::V6(v6) => v6.is_loopback() || v6.is_unspecified(),
        };
    }
    false
}
