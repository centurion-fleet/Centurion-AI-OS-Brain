use centurion_common::{
    KEY_EXCHANGE_FRAME_BYTES, RemoteMessage, decode_key_exchange, encode_frame, encode_key_exchange,
};
use centurion_remote::bridge::EchoBridge;
use centurion_remote::admin::{self, AdminState};
use centurion_remote::crypto::ServerIdentity;
use centurion_remote::registry::DeviceRegistry;
use centurion_remote::server::{self, ServerState};
use centurion_remote::session_registry::SessionRegistry;
use sodiumoxide::crypto::{kx, secretbox};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex;
use std::path::PathBuf;
use uuid::Uuid;

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
async fn smoke_bind_echo_round_trip() {
    let bind = match std::env::var("CENTURION_REMOTE_SMOKE_BIND") {
        Ok(value) => value,
        Err(_) => return,
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
