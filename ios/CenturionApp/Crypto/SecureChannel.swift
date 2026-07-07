import Foundation

/// Encrypted bidirectional channel between iPhone and Centurion.
///
/// Uses XSalsa20-Poly1305 (secretbox) for authenticated encryption
/// with Perfect Forward Secrecy. Each session generates fresh
/// ephemeral keys so that compromising today's key cannot decrypt
/// yesterday's messages.

final class SecureChannel {
    private var sessionKey: SessionKey?
    private let nonceSize = 24
    
    /// Encrypt a message for transit to the Centurion
    func encrypt(_ message: Data, using key: SessionKey) throws -> Data {
        let nonce = randomNonce()
        let ciphertextLength = message.count + crypto_secretbox_MACBYTES
        var ciphertext = Data(count: ciphertextLength)
        
        // Use rx part of session key (first 32 bytes)
        let encryptionKey = key.key.prefix(32)
        
        let result = crypto_secretbox_easy(
            ciphertext: &ciphertext,
            message: message,
            nonce: nonce,
            key: encryptionKey
        )
        
        guard result == 0 else {
            throw CryptoError.encryptionFailed
        }
        
        // Prepend the nonce to the ciphertext for transmission
        return nonce + ciphertext
    }
    
    /// Decrypt a message received from the Centurion
    func decrypt(_ ciphertextWithNonce: Data, using key: SessionKey) throws -> Data {
        guard ciphertextWithNonce.count >= nonceSize else {
            throw CryptoError.decryptionFailed
        }
        
        let nonce = ciphertextWithNonce[..<nonceSize]
        let ciphertext = ciphertextWithNonce[nonceSize...]
        
        let plaintextLength = ciphertext.count - crypto_secretbox_MACBYTES
        guard plaintextLength >= 0 else {
            throw CryptoError.decryptionFailed
        }
        
        var plaintext = Data(count: plaintextLength)
        
        // Use tx part of session key (second 32 bytes) for decrypting responses
        let decryptionKey = key.key.dropFirst(32).prefix(32)
        
        let result = crypto_secretbox_open_easy(
            plaintext: &plaintext,
            ciphertext: Data(ciphertext),
            nonce: Data(nonce),
            key: decryptionKey
        )
        
        guard result == 0 else {
            throw CryptoError.decryptionFailed
        }
        
        return plaintext
    }
    
    /// Generate a random nonce for each message (PFS requirement)
    private func randomNonce() -> Data {
        var nonce = Data(count: nonceSize)
        randombytes_buf(&nonce)
        return nonce
    }
}
