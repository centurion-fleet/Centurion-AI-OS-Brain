use centurion_common::DEFAULT_PORT;
use centurion_remote::admin::{self, AdminState};
use centurion_remote::bridge::{AgentBridge, EchoBridge, PythonBridge};
use centurion_remote::crypto::ServerIdentity;
use centurion_remote::discovery::Advertisement;
use centurion_remote::listing::build_device_listing;
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
    about = "Encrypted LAN service for CenturionAI Remote"
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
        #[arg(long, default_value = "Personal Centurion")]
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
        name: "Personal Centurion".to_owned(),
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
                let connected: std::collections::HashSet<&str> =
                    live.iter().map(|session| session.fingerprint.as_str()).collect();
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
                        session.fingerprint,
                        session.id,
                        session.peer,
                        session.last_activity_at
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
        "Your Centurion is ready for iPhone connections"
    );

    server::run(
        listener,
        ServerState {
            bridge,
            registry: Arc::new(Mutex::new(registry)),
            sessions,
            identity: Arc::new(identity),
            auto_approve,
        },
    )
    .await?;
    Ok(())
}
