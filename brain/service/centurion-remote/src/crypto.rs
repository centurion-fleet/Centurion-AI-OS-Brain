use sodiumoxide::crypto::{kx, secretbox};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const NONCE_BYTES: usize = secretbox::NONCEBYTES;

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("libsodium could not be initialized")]
    Initialization,
    #[error("the peer public key is invalid")]
    InvalidPeerKey,
    #[error("the encrypted frame is too short")]
    FrameTooShort,
    #[error("message authentication failed")]
    Authentication,
}

#[derive(Debug)]
pub struct ServerIdentity {
    public: kx::PublicKey,
    secret: kx::SecretKey,
}

impl ServerIdentity {
    pub fn generate() -> Result<Self, CryptoError> {
        sodiumoxide::init().map_err(|()| CryptoError::Initialization)?;
        let (public, secret) = kx::gen_keypair();
        Ok(Self { public, secret })
    }

    pub fn load_or_create(path: &Path) -> io::Result<Self> {
        sodiumoxide::init().map_err(|()| io::Error::other("libsodium initialization failed"))?;
        match fs::read(path) {
            Ok(bytes) => {
                if bytes.len() != kx::PUBLICKEYBYTES + kx::SECRETKEYBYTES {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid Centurion server identity",
                    ));
                }
                let public = kx::PublicKey::from_slice(&bytes[..kx::PUBLICKEYBYTES])
                    .ok_or_else(|| io::Error::other("invalid server public key"))?;
                let secret = kx::SecretKey::from_slice(&bytes[kx::PUBLICKEYBYTES..])
                    .ok_or_else(|| io::Error::other("invalid server secret key"))?;
                Ok(Self { public, secret })
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let identity =
                    Self::generate().map_err(|error| io::Error::other(error.to_string()))?;
                if let Some(parent) = path.parent() {
                    fs::create_dir_all(parent)?;
                }
                let mut bytes = Vec::with_capacity(kx::PUBLICKEYBYTES + kx::SECRETKEYBYTES);
                bytes.extend_from_slice(identity.public.as_ref());
                bytes.extend_from_slice(identity.secret.as_ref());
                write_private(path, &bytes)?;
                Ok(identity)
            }
            Err(error) => Err(error),
        }
    }

    pub fn default_path() -> io::Result<PathBuf> {
        if let Some(home) = std::env::var_os("CENTURION_HOME") {
            return Ok(PathBuf::from(home)
                .join("remote")
                .join("server-identity.bin"));
        }
        let home = std::env::var_os("HOME")
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))?;
        Ok(PathBuf::from(home)
            .join(".centurion")
            .join("remote")
            .join("server-identity.bin"))
    }
}

#[derive(Debug)]
pub struct ServerSession {
    public: kx::PublicKey,
    receive: secretbox::Key,
    transmit: secretbox::Key,
}

impl ServerSession {
    pub fn establish(
        client_public_key: &[u8],
        identity: &ServerIdentity,
    ) -> Result<Self, CryptoError> {
        sodiumoxide::init().map_err(|()| CryptoError::Initialization)?;

        let client_public_key =
            kx::PublicKey::from_slice(client_public_key).ok_or(CryptoError::InvalidPeerKey)?;
        let (receive, transmit) =
            kx::server_session_keys(&identity.public, &identity.secret, &client_public_key)
                .map_err(|()| CryptoError::InvalidPeerKey)?;

        let receive_key =
            secretbox::Key::from_slice(receive.as_ref()).ok_or(CryptoError::InvalidPeerKey)?;
        let transmit_key =
            secretbox::Key::from_slice(transmit.as_ref()).ok_or(CryptoError::InvalidPeerKey)?;

        Ok(Self {
            public: identity.public,
            receive: receive_key,
            transmit: transmit_key,
        })
    }

    pub fn public_key(&self) -> [u8; kx::PUBLICKEYBYTES] {
        let mut bytes = [0_u8; kx::PUBLICKEYBYTES];
        bytes.copy_from_slice(self.public.as_ref());
        bytes
    }

    pub fn decrypt(&self, frame: &[u8]) -> Result<Vec<u8>, CryptoError> {
        if frame.len() < NONCE_BYTES + secretbox::MACBYTES {
            return Err(CryptoError::FrameTooShort);
        }

        let nonce = secretbox::Nonce::from_slice(&frame[..NONCE_BYTES])
            .ok_or(CryptoError::FrameTooShort)?;
        secretbox::open(&frame[NONCE_BYTES..], &nonce, &self.receive)
            .map_err(|()| CryptoError::Authentication)
    }

    pub fn encrypt(&self, plaintext: &[u8]) -> Vec<u8> {
        let nonce = secretbox::gen_nonce();
        let ciphertext = secretbox::seal(plaintext, &nonce, &self.transmit);
        let mut frame = Vec::with_capacity(NONCE_BYTES + ciphertext.len());
        frame.extend_from_slice(nonce.as_ref());
        frame.extend_from_slice(&ciphertext);
        frame
    }
}

#[cfg(unix)]
fn write_private(path: &std::path::Path, bytes: &[u8]) -> io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;

    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(bytes)
}

#[cfg(not(unix))]
fn write_private(path: &std::path::Path, bytes: &[u8]) -> io::Result<()> {
    fs::write(path, bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn server_keys_interoperate_with_client_keys() {
        sodiumoxide::init().expect("sodium");
        let (client_public, client_secret) = kx::gen_keypair();
        let identity = ServerIdentity::generate().expect("server identity");
        let server =
            ServerSession::establish(client_public.as_ref(), &identity).expect("server session");
        let server_public =
            kx::PublicKey::from_slice(&server.public_key()).expect("server public key");
        let (client_receive, client_transmit) =
            kx::client_session_keys(&client_public, &client_secret, &server_public)
                .expect("client session");
        let client_transmit =
            secretbox::Key::from_slice(client_transmit.as_ref()).expect("transmit key");
        let client_receive =
            secretbox::Key::from_slice(client_receive.as_ref()).expect("receive key");

        let request_nonce = secretbox::gen_nonce();
        let request = secretbox::seal(b"hello", &request_nonce, &client_transmit);
        let mut request_frame = request_nonce.as_ref().to_vec();
        request_frame.extend(request);
        assert_eq!(server.decrypt(&request_frame).expect("decrypt"), b"hello");

        let response = server.encrypt(b"world");
        let response_nonce =
            secretbox::Nonce::from_slice(&response[..NONCE_BYTES]).expect("response nonce");
        assert_eq!(
            secretbox::open(&response[NONCE_BYTES..], &response_nonce, &client_receive)
                .expect("open response"),
            b"world"
        );
    }
}
