import Foundation
import Sodium

/// Encrypted bidirectional channel between iPhone and Centurion.
///
/// Uses XSalsa20-Poly1305 (secretbox) for authenticated encryption
/// with independent directional keys and a fresh random nonce for
/// every message.

final class SecureChannel {
    private let sodium = Sodium()
    
    /// Encrypt a message for transit to the Centurion
    func encrypt(_ message: Data, using key: SessionKey) throws -> Data {
        let ciphertext: [UInt8]? = sodium.secretBox.seal(
            message: [UInt8](message),
            secretKey: [UInt8](key.transmitKey)
        )
        guard let ciphertext else {
            throw CryptoError.encryptionFailed
        }

        // Swift-Sodium prepends the 24-byte nonce to the authenticated ciphertext.
        return Data(ciphertext)
    }
    
    /// Decrypt a message received from the Centurion
    func decrypt(_ ciphertextWithNonce: Data, using key: SessionKey) throws -> Data {
        let plaintext: [UInt8]? = sodium.secretBox.open(
            nonceAndAuthenticatedCipherText: [UInt8](ciphertextWithNonce),
            secretKey: [UInt8](key.receiveKey)
        )
        guard let plaintext else {
            throw CryptoError.decryptionFailed
        }

        return Data(plaintext)
    }
}
