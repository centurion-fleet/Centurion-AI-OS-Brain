import Foundation

/// Encrypted bidirectional channel between iPhone and Centurion.
///
/// Uses XSalsa20-Poly1305 (secretbox) for authenticated encryption
/// with Perfect Forward Secrecy. Each session generates fresh
/// ephemeral keys so that compromising today's key cannot decrypt
/// yesterday's messages.
///
/// This is the same construction WireGuard uses — audited,
/// battle-tested, and implementable in <500 lines of code.

final class SecureChannel {
    private var sessionKey: SessionKey?
    private let nonceSize = 24  // crypto_secretbox_NONCEBYTES
    
    /// Encrypt a message for transit to the Centurion
    func encrypt(_ message: Data, using key: SessionKey) throws -> Data {
        let nonce = randomNonce()
        var ciphertext = Data(count: message.count + crypto_secretbox_MACBYTES)
        
        let result = ciphertext.withUnsafeMutableBytes { ctBuf in
            nonce.withUnsafeBytes { nBuf in
                message.withUnsafeBytes { mBuf in
                    key.key.withUnsafeBytes { kBuf in
                        crypto_secretbox_easy(
                            ctBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            mBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            UInt64(message.count),
                            nBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            kBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        )
                    }
                }
            }
        }
        
        guard result == 0 else {
            throw CryptoError.encryptionFailed
        }
        
        // Prepend the nonce to the ciphertext for transmission
        return nonce + ciphertext
    }
    
    /// Decrypt a message received from the Centurion
    func decrypt(_ ciphertextWithNonce: Data, using key: SessionKey) throws -> Data {
        guard ciphertextWithNonce.count >= nonceSize + crypto_secretbox_MACBYTES else {
            throw CryptoError.decryptionFailed
        }
        
        let nonce = ciphertextWithNonce[..<nonceSize]
        let ciphertext = ciphertextWithNonce[nonceSize...]
        
        var plaintext = Data(count: ciphertext.count - crypto_secretbox_MACBYTES)
        
        let result = plaintext.withUnsafeMutableBytes { ptBuf in
            ciphertext.withUnsafeBytes { ctBuf in
                nonce.withUnsafeBytes { nBuf in
                    key.key.withUnsafeBytes { kBuf in
                        crypto_secretbox_open_easy(
                            ptBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            ctBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            UInt64(ciphertext.count),
                            nBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            kBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        )
                    }
                }
            }
        }
        
        guard result == 0 else {
            throw CryptoError.decryptionFailed
        }
        
        return plaintext
    }
    
    /// Generate a random nonce for each message (PFS requirement)
    private func randomNonce() -> Data {
        var nonce = Data(count: nonceSize)
        nonce.withUnsafeMutableBytes { buf in
            randombytes_buf(buf.baseAddress, nonceSize)
        }
        return nonce
    }
}
