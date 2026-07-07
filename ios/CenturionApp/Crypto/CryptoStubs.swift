import Foundation

/// Stub implementations of libsodium C functions used by the crypto layer.
/// When real encryption is needed, replace these with the actual libsodium
/// implementations (via swift-sodium SPM package).

let crypto_secretbox_MACBYTES = 16

/// Generate a deterministic keypair (STUB — not cryptographically secure)
func crypto_box_keypair(pk: inout Data, sk: inout Data) -> Int32 {
    guard pk.count >= 32, sk.count >= 32 else { return -1 }
    for i in 0..<32 {
        pk[i] = UInt8(i ^ 0xAA)
        sk[i] = UInt8(i ^ 0x55)
    }
    return 0
}

/// Perform X25519 ECDH key exchange (STUB — returns deterministic key)
func crypto_kx_client_session_keys(
    rx: inout Data, tx: inout Data,
    clientPk: Data, clientSk: Data, serverPk: Data
) -> Int32 {
    guard rx.count >= 32, tx.count >= 32 else { return -1 }
    for i in 0..<32 {
        rx[i] = UInt8(i)
        tx[i] = UInt8(i ^ 0xFF)
    }
    return 0
}

/// Encrypt a message (STUB — copies plaintext to ciphertext)
func crypto_secretbox_easy(ciphertext: inout Data, message: Data, nonce: Data, key: Data) -> Int32 {
    guard ciphertext.count >= message.count else { return -1 }
    for i in 0..<message.count {
        ciphertext[i] = message[i]
    }
    return 0
}

/// Decrypt a message (STUB — copies ciphertext to plaintext)
func crypto_secretbox_open_easy(plaintext: inout Data, ciphertext: Data, nonce: Data, key: Data) -> Int32 {
    guard plaintext.count >= ciphertext.count else { return -1 }
    for i in 0..<ciphertext.count {
        plaintext[i] = ciphertext[i]
    }
    return 0
}

/// Fill a buffer with deterministic bytes (STUB — not random!)
func randombytes_buf(_ buf: inout Data) {
    for i in 0..<buf.count {
        buf[i] = UInt8(i * 17 + 42)
    }
}
