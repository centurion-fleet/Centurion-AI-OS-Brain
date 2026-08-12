use centurion_common::{
    KEY_EXCHANGE_FRAME_BYTES, RemoteMessage, decode_key_exchange, encode_frame, encode_key_exchange,
};
use centurion_remote::admin::{self, AdminState};
use centurion_remote::bridge::EchoBridge;
use centurion_remote::crypto::ServerIdentity;
use centurion_remote::pairing::PairingTokenStore;
use centurion_remote::registry::DeviceRegistry;
use centurion_remote::server::{self, ServerState};
use centurion_remote::session_registry::SessionRegistry;
use sodiumoxide::crypto::{kx, secretbox};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;
use uuid::Uuid;

fn empty_pairing() -> Arc<Mutex<PairingTokenStore>> {
    let path = std::env::temp_dir().join(format!("centurion-pairing-{}.json", Uuid::new_v4()));
    Arc::new(Mutex::new(
        PairingTokenStore::load(&path).expect("pairing store"),
    ))
}

#[tokio::test]
async fn encrypted_chat_round_trip_over_tcp() {
    sodiumoxide::init().expect("sodium");
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("listener");
    let address = listener.local_addr().expect("address");
    let registry_path =
        std::env::temp_dir().join(format!("centurion-loopback-{}.json", Uuid::new_v4()));
    let registry = DeviceRegistry::load(&registry_path).expect("registry");
    let sessions = SessionRegistry::new();
    let admin_path = PathBuf::from(format!("/tmp/c-loopback-{}.sock", Uuid::new_v4()));
    let admin_state = AdminState {
        sessions: sessions.clone(),
    };
    tokio::spawn(admin::run(admin_state, admin_path.clone()));
    let server = tokio::spawn(server::run(
        listener,
        ServerState {
            bridge: Arc::new(EchoBridge),
            registry: Arc::new(Mutex::new(registry)),
            pairing: empty_pairing(),
            sessions,
            identity: Arc::new(ServerIdentity::generate().expect("identity")),
            auto_approve: true,
        },
    ));

    let mut stream = TcpStream::connect(address).await.expect("connect");
    let (client_public, client_secret) = kx::gen_keypair();
    stream
        .write_all(&encode_key_exchange(client_public.as_ref()).expect("handshake"))
        .await
        .expect("send handshake");

    let mut server_handshake = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream
        .read_exact(&mut server_handshake)
        .await
        .expect("server handshake");
    let server_public =
        kx::PublicKey::from_slice(&decode_key_exchange(&server_handshake).expect("public key"))
            .expect("server public key");
    let (receive, transmit) =
        kx::client_session_keys(&client_public, &client_secret, &server_public)
            .expect("session keys");
    let receive = secretbox::Key::from_slice(receive.as_ref()).expect("receive key");
    let transmit = secretbox::Key::from_slice(transmit.as_ref()).expect("transmit key");
    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::Ready
    );

    let live = admin::query_sessions(&admin_path)
        .await
        .expect("live sessions");
    assert_eq!(live.len(), 1);

    let request_id = Uuid::new_v4();
    let request = RemoteMessage::Chat {
        id: request_id,
        text: "Hello".to_owned(),
        session_id: None,
        life_inject: None,
    }
    .to_json()
    .expect("request JSON");
    let nonce = secretbox::gen_nonce();
    let mut encrypted = nonce.as_ref().to_vec();
    encrypted.extend(secretbox::seal(&request, &nonce, &transmit));
    stream
        .write_all(&encode_frame(&encrypted).expect("frame"))
        .await
        .expect("send request");

    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::ChatResponse {
            id: request_id,
            text: "[Development echo] Hello".to_owned(),
            recovered: None,
            recovery_message: None,
            routed_display_name: None,
            session_id: None,
        }
    );

    server.abort();
    let _ = std::fs::remove_file(registry_path);
    let _ = std::fs::remove_file(admin_path);
}

#[tokio::test]
async fn revoked_device_receives_error_on_next_message() {
    sodiumoxide::init().expect("sodium");
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("listener");
    let address = listener.local_addr().expect("address");
    let registry_path =
        std::env::temp_dir().join(format!("centurion-loopback-revoke-{}.json", Uuid::new_v4()));
    let registry = DeviceRegistry::load(&registry_path).expect("registry");
    let sessions = SessionRegistry::new();
    let server = tokio::spawn(server::run(
        listener,
        ServerState {
            bridge: Arc::new(EchoBridge),
            registry: Arc::new(Mutex::new(registry)),
            pairing: empty_pairing(),
            sessions,
            identity: Arc::new(ServerIdentity::generate().expect("identity")),
            auto_approve: true,
        },
    ));

    let (client_public, client_secret) = kx::gen_keypair();
    let fingerprint = DeviceRegistry::fingerprint(client_public.as_ref());
    let mut stream = TcpStream::connect(address).await.expect("connect");
    stream
        .write_all(&encode_key_exchange(client_public.as_ref()).expect("handshake"))
        .await
        .expect("send handshake");

    let mut server_handshake = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream
        .read_exact(&mut server_handshake)
        .await
        .expect("server handshake");
    let server_public =
        kx::PublicKey::from_slice(&decode_key_exchange(&server_handshake).expect("public key"))
            .expect("server public key");
    let (receive, transmit) =
        kx::client_session_keys(&client_public, &client_secret, &server_public)
            .expect("session keys");
    let receive = secretbox::Key::from_slice(receive.as_ref()).expect("receive key");
    let transmit = secretbox::Key::from_slice(transmit.as_ref()).expect("transmit key");
    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::Ready
    );

    {
        let mut registry = DeviceRegistry::load(&registry_path).expect("registry");
        registry.revoke(&fingerprint).expect("revoke");
    }

    let request_id = Uuid::new_v4();
    let request = RemoteMessage::Chat {
        id: request_id,
        text: "After revoke".to_owned(),
        session_id: None,
        life_inject: None,
    }
    .to_json()
    .expect("request JSON");
    let nonce = secretbox::gen_nonce();
    let mut encrypted = nonce.as_ref().to_vec();
    encrypted.extend(secretbox::seal(&request, &nonce, &transmit));
    stream
        .write_all(&encode_frame(&encrypted).expect("frame"))
        .await
        .expect("send request");

    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::Error {
            id: None,
            code: "DEVICE_REVOKED".to_owned(),
            message: "This iPhone is no longer approved on your Centurion.".to_owned(),
            retryable: false,
        }
    );

    server.abort();
    let _ = std::fs::remove_file(registry_path);
}

#[tokio::test]
async fn remote_pair_token_approves_and_ready() {
    sodiumoxide::init().expect("sodium");
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("listener");
    let address = listener.local_addr().expect("address");
    let registry_path =
        std::env::temp_dir().join(format!("centurion-loopback-pair-{}.json", Uuid::new_v4()));
    let pairing_path =
        std::env::temp_dir().join(format!("centurion-loopback-pair-tok-{}.json", Uuid::new_v4()));
    let registry = DeviceRegistry::load(&registry_path).expect("registry");
    let mut pairing_store = PairingTokenStore::load(&pairing_path).expect("pairing");
    let (_record, secret) = pairing_store
        .create_token("test".to_owned())
        .expect("token");
    let sessions = SessionRegistry::new();
    let server = tokio::spawn(server::run(
        listener,
        ServerState {
            bridge: Arc::new(EchoBridge),
            registry: Arc::new(Mutex::new(registry)),
            pairing: Arc::new(Mutex::new(pairing_store)),
            sessions,
            identity: Arc::new(ServerIdentity::generate().expect("identity")),
            auto_approve: false,
        },
    ));

    let (client_public, client_secret) = kx::gen_keypair();
    let mut stream = TcpStream::connect(address).await.expect("connect");
    stream
        .write_all(&encode_key_exchange(client_public.as_ref()).expect("handshake"))
        .await
        .expect("send handshake");

    let mut server_handshake = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream
        .read_exact(&mut server_handshake)
        .await
        .expect("server handshake");
    let server_public =
        kx::PublicKey::from_slice(&decode_key_exchange(&server_handshake).expect("public key"))
            .expect("server public key");
    let (receive, transmit) =
        kx::client_session_keys(&client_public, &client_secret, &server_public)
            .expect("session keys");
    let receive = secretbox::Key::from_slice(receive.as_ref()).expect("receive key");
    let transmit = secretbox::Key::from_slice(transmit.as_ref()).expect("transmit key");

    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::PairRequired
    );

    let pair = RemoteMessage::Pair {
        token: secret.clone(),
    }
    .to_json()
    .expect("pair JSON");
    let nonce = secretbox::gen_nonce();
    let mut encrypted = nonce.as_ref().to_vec();
    encrypted.extend(secretbox::seal(&pair, &nonce, &transmit));
    stream
        .write_all(&encode_frame(&encrypted).expect("frame"))
        .await
        .expect("send pair");

    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::Ready
    );

    // Reconnect should get Ready without Pair (fingerprint approved).
    let mut stream2 = TcpStream::connect(address).await.expect("reconnect");
    stream2
        .write_all(&encode_key_exchange(client_public.as_ref()).expect("handshake"))
        .await
        .expect("send handshake");
    let mut server_handshake2 = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream2
        .read_exact(&mut server_handshake2)
        .await
        .expect("server handshake");
    let (receive2, _transmit2) =
        kx::client_session_keys(&client_public, &client_secret, &server_public)
            .expect("session keys");
    let receive2 = secretbox::Key::from_slice(receive2.as_ref()).expect("receive key");
    assert_eq!(
        read_message(&mut stream2, &receive2).await,
        RemoteMessage::Ready
    );

    server.abort();
    let _ = std::fs::remove_file(registry_path);
    let _ = std::fs::remove_file(pairing_path);
}

#[tokio::test]
async fn virgin_lan_confirm_auto_approves_without_token() {
    sodiumoxide::init().expect("sodium");
    let Some(lan_ip) = first_private_ipv4() else {
        // CI / sandboxes without a private NIC skip this path.
        return;
    };
    let listener = TcpListener::bind((lan_ip, 0)).await.expect("listener");
    let address = listener.local_addr().expect("address");
    let registry_path =
        std::env::temp_dir().join(format!("centurion-loopback-virgin-{}.json", Uuid::new_v4()));
    let pairing_path =
        std::env::temp_dir().join(format!("centurion-loopback-virgin-tok-{}.json", Uuid::new_v4()));
    let registry = DeviceRegistry::load(&registry_path).expect("registry");
    // Active pairing tokens must not block first LAN Confirm on a virgin Brain.
    let mut pairing_store = PairingTokenStore::load(&pairing_path).expect("pairing");
    let (_record, _secret) = pairing_store
        .create_token("unused-qr".to_owned())
        .expect("token");
    let sessions = SessionRegistry::new();
    let server = tokio::spawn(server::run(
        listener,
        ServerState {
            bridge: Arc::new(EchoBridge),
            registry: Arc::new(Mutex::new(registry)),
            pairing: Arc::new(Mutex::new(pairing_store)),
            sessions,
            identity: Arc::new(ServerIdentity::generate().expect("identity")),
            auto_approve: false,
        },
    ));

    let (client_public, client_secret) = kx::gen_keypair();
    let mut stream = TcpStream::connect(address).await.expect("connect");
    stream
        .write_all(&encode_key_exchange(client_public.as_ref()).expect("handshake"))
        .await
        .expect("send handshake");

    let mut server_handshake = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream
        .read_exact(&mut server_handshake)
        .await
        .expect("server handshake");
    let server_public =
        kx::PublicKey::from_slice(&decode_key_exchange(&server_handshake).expect("public key"))
            .expect("server public key");
    let (receive, _transmit) =
        kx::client_session_keys(&client_public, &client_secret, &server_public)
            .expect("session keys");
    let receive = secretbox::Key::from_slice(receive.as_ref()).expect("receive key");

    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::Ready
    );

    server.abort();
    let _ = std::fs::remove_file(registry_path);
    let _ = std::fs::remove_file(pairing_path);
}

fn first_private_ipv4() -> Option<std::net::Ipv4Addr> {
    let Ok(output) = std::process::Command::new("hostname").args(["-I"]).output() else {
        return None;
    };
    if !output.status.success() {
        return None;
    }
    for token in String::from_utf8_lossy(&output.stdout).split_whitespace() {
        if let Ok(ip) = token.parse::<std::net::Ipv4Addr>() {
            if ip.is_private() {
                return Some(ip);
            }
        }
    }
    None
}

#[tokio::test]
async fn smoke_bind_echo_round_trip() {
    let Ok(bind) = std::env::var("CENTURION_REMOTE_SMOKE_BIND") else {
        return;
    };
    sodiumoxide::init().expect("sodium");
    let address: std::net::SocketAddr = bind.parse().expect("smoke bind");

    let mut stream = TcpStream::connect(address).await.expect("connect");
    let (client_public, client_secret) = kx::gen_keypair();
    stream
        .write_all(&encode_key_exchange(client_public.as_ref()).expect("handshake"))
        .await
        .expect("send handshake");

    let mut server_handshake = [0_u8; KEY_EXCHANGE_FRAME_BYTES];
    stream
        .read_exact(&mut server_handshake)
        .await
        .expect("server handshake");
    let server_public =
        kx::PublicKey::from_slice(&decode_key_exchange(&server_handshake).expect("public key"))
            .expect("server public key");
    let (receive, transmit) =
        kx::client_session_keys(&client_public, &client_secret, &server_public)
            .expect("session keys");
    let receive = secretbox::Key::from_slice(receive.as_ref()).expect("receive key");
    let transmit = secretbox::Key::from_slice(transmit.as_ref()).expect("transmit key");
    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::Ready
    );

    let request_id = Uuid::new_v4();
    let request = RemoteMessage::Chat {
        id: request_id,
        text: "Smoke".to_owned(),
        session_id: None,
        life_inject: None,
    }
    .to_json()
    .expect("request JSON");
    let nonce = secretbox::gen_nonce();
    let mut encrypted = nonce.as_ref().to_vec();
    encrypted.extend(secretbox::seal(&request, &nonce, &transmit));
    stream
        .write_all(&encode_frame(&encrypted).expect("frame"))
        .await
        .expect("send request");

    assert_eq!(
        read_message(&mut stream, &receive).await,
        RemoteMessage::ChatResponse {
            id: request_id,
            text: "[Development echo] Smoke".to_owned(),
            recovered: None,
            recovery_message: None,
            routed_display_name: None,
            session_id: None,
        }
    );
}

async fn read_message(stream: &mut TcpStream, receive: &secretbox::Key) -> RemoteMessage {
    let length = stream.read_u32().await.expect("response length") as usize;
    let mut response = vec![0_u8; length];
    stream
        .read_exact(&mut response)
        .await
        .expect("response frame");
    let nonce =
        secretbox::Nonce::from_slice(&response[..secretbox::NONCEBYTES]).expect("response nonce");
    let plaintext = secretbox::open(&response[secretbox::NONCEBYTES..], &nonce, receive)
        .expect("decrypt response");
    RemoteMessage::from_json(&plaintext).expect("response JSON")
}
