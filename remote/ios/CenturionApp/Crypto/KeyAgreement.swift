import Foundation
import Security
import Sodium
import CryptoKit

/// Centurion's encryption layer — built on libsodium (NaCl).
///
/// Security model:
/// - X25519 key exchange (Curve25519 ECDH)
/// - XSalsa20-Poly1305 authenticated encryption
/// - No session keys ever written to disk

enum CryptoError: Error, LocalizedError {
    case keyGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case keyExchangeFailed
    case invalidPublicKey
    case serverIdentityChanged
    
    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed: return "Failed to generate encryption keys"
        case .encryptionFailed: return "Failed to encrypt message"
        case .decryptionFailed: return "Failed to decrypt message"
        case .keyExchangeFailed: return "Failed to establish secure channel"
        case .invalidPublicKey: return "Invalid public key received"
        case .serverIdentityChanged:
            return "This Sovereign's secure identity has changed. Re-pair it before connecting."
        }
    }
}

enum ServerTrustStore {
    private static let service = "com.centurion.ios.trusted-centurions"

    static func verifyOrStore(identifier: String, publicKey: Data) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess {
            guard let trustedKey = item as? Data, trustedKey == publicKey else {
                throw CryptoError.serverIdentityChanged
            }
            return
        }
        guard status == errSecItemNotFound else {
            throw CryptoError.invalidPublicKey
        }

        var insert = lookup
        insert.removeValue(forKey: kSecReturnData as String)
        insert.removeValue(forKey: kSecMatchLimit as String)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        insert[kSecValueData as String] = publicKey
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw CryptoError.invalidPublicKey
        }
    }

    static func remove(identifier: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// A secure session key established between iPhone and Sovereign
struct SessionKey {
    let receiveKey: Data
    let transmitKey: Data
    let createdAt: Date
    
    /// Performs X25519 ECDH key exchange
    static func exchange(theirPublicKey: Data, mySecretKey: Data, myPublicKey: Data) throws -> SessionKey {
        let sodium = Sodium()
        guard let keys = sodium.keyExchange.sessionKeyPair(
            publicKey: [UInt8](myPublicKey),
            secretKey: [UInt8](mySecretKey),
            otherPublicKey: [UInt8](theirPublicKey),
            side: .CLIENT
        ) else {
            throw CryptoError.keyExchangeFailed
        }

        return SessionKey(
            receiveKey: Data(keys.rx),
            transmitKey: Data(keys.tx),
            createdAt: Date()
        )
    }
}

/// Manages the iPhone's identity keypair (persisted in Keychain)
struct IdentityKey {
    private static let keychainService = "com.centurion.ios.remote-identity"
    private static let keychainAccount = "primary"

    let publicKey: Data
    let secretKey: Data

    var fingerprint: String {
        let digest = SHA256.hash(data: publicKey)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    
    static func generate() throws -> IdentityKey {
        let sodium = Sodium()
        guard let keyPair = sodium.keyExchange.keyPair() else {
            throw CryptoError.keyGenerationFailed
        }

        return IdentityKey(
            publicKey: Data(keyPair.publicKey),
            secretKey: Data(keyPair.secretKey)
        )
    }

    static func loadOrCreate() throws -> IdentityKey {
        if let existing = try load() {
            return existing
        }

        let generated = try generate()
        try generated.save()
        return generated
    }

    private static func load() throws -> IdentityKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              data.count == 64 else {
            throw CryptoError.keyGenerationFailed
        }

        return IdentityKey(
            publicKey: data.prefix(32),
            secretKey: data.suffix(32)
        )
    }

    private func save() throws {
        var data = Data()
        data.append(publicKey)
        data.append(secretKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoError.keyGenerationFailed
        }
    }

    static func reset() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        ServerTrustStore.clearAll()
    }
}
