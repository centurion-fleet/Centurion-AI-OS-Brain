import Foundation

/// Centurion's encryption layer — built on libsodium (NaCl).
///
/// Security model:
/// - X25519 key exchange (Curve25519 ECDH)
/// - XSalsa20-Poly1305 authenticated encryption
/// - Perfect Forward Secrecy via ephemeral key exchange
/// - No session keys ever written to disk

enum CryptoError: Error, LocalizedError {
    case keyGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case keyExchangeFailed
    case invalidPublicKey
    
    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed: return "Failed to generate encryption keys"
        case .encryptionFailed: return "Failed to encrypt message"
        case .decryptionFailed: return "Failed to decrypt message"
        case .keyExchangeFailed: return "Failed to establish secure channel"
        case .invalidPublicKey: return "Invalid public key received"
        }
    }
}

/// A secure session key established between iPhone and Centurion
struct SessionKey {
    let key: Data
    let createdAt: Date
    
    /// Performs X25519 ECDH key exchange
    static func exchange(theirPublicKey: Data, mySecretKey: Data, myPublicKey: Data) throws -> SessionKey {
        var rx = Data(count: 32)
        var tx = Data(count: 32)
        
        let result = crypto_kx_client_session_keys(
            rx: &rx, tx: &tx,
            clientPk: myPublicKey,
            clientSk: mySecretKey,
            serverPk: theirPublicKey
        )
        
        guard result == 0 else {
            throw CryptoError.keyExchangeFailed
        }
        
        // Combine rx + tx into a session key
        var combined = Data()
        combined.append(rx)
        combined.append(tx)
        
        return SessionKey(key: combined, createdAt: Date())
    }
}

/// Manages the iPhone's identity keypair (persisted in Keychain)
struct IdentityKey {
    let publicKey: Data
    let secretKey: Data
    
    static func generate() throws -> IdentityKey {
        var pk = Data(count: 32)
        var sk = Data(count: 32)
        
        let result = crypto_box_keypair(pk: &pk, sk: &sk)
        
        guard result == 0 else {
            throw CryptoError.keyGenerationFailed
        }
        
        return IdentityKey(publicKey: pk, secretKey: sk)
    }
}
