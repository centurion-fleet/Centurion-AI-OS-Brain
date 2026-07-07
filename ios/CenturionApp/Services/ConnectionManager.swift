import Foundation
import Network

/// Manages the encrypted connection between iPhone and Centurion.
///
/// Connection priority:
/// 1. LAN (mDNS/Bonjour) — zero internet, zero latency, maximum privacy
/// 2. Tailscale — WireGuard tunnel when away from home
///
/// Encryption flow:
/// 1. Discover Centurion via Bonjour (LAN) or Tailscale IP
/// 2. Exchange X25519 public keys for key agreement
/// 3. Establish session key with Perfect Forward Secrecy
/// 4. All messages encrypted with XSalsa20-Poly1305

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var discoveredDevices: [CenturionDevice] = []
    @Published var connectedDevice: CenturionDevice?
    @Published var connectionState: ConnectionState = .disconnected
    
    private let bonjourDiscoverer = BonjourDiscoverer()
    private let secureChannel = SecureChannel()
    private var identityKey: IdentityKey?
    private var currentSessionKey: SessionKey?
    private var connection: NWConnection?
    
    enum ConnectionState: Equatable {
        case disconnected
        case discovering
        case connecting
        case connected
        case error(String)
    }
    
    init() {
        bonjourDiscoverer.delegate = self
    }
    
    func startDiscovery() {
        connectionState = .discovering
        do {
            identityKey = try IdentityKey.generate()
        } catch {
            connectionState = .error("Failed to generate identity: \(error.localizedDescription)")
            return
        }
        bonjourDiscoverer.startDiscovery()
    }
    
    func connect(to device: CenturionDevice) {
        connectionState = .connecting
        
        // Resolve the device's IP and port via Bonjour
        // Then perform Noise Protocol key exchange
        Task {
            do {
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(device.hostname),
                    port: NWEndpoint.Port(rawValue: UInt16(device.port)) ?? NWEndpoint.Port(integerLiteral: 9119)
                )
                
                connection = NWConnection(to: endpoint, using: .tcp)
                
                connection?.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        switch state {
                        case .ready:
                            self?.performKeyExchange()
                        case .failed(let error):
                            self?.connectionState = .error(error.localizedDescription)
                        case .cancelled:
                            self?.connectionState = .disconnected
                        default:
                            break
                        }
                    }
                }
                
                connection?.start(queue: .global(qos: .userInitiated))
                
            } catch {
                connectionState = .error("Connection failed: \(error.localizedDescription)")
            }
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        connectionState = .disconnected
    }
    
    func sendMessage(_ text: String) async throws {
        guard let sessionKey = currentSessionKey,
              let connection = connection,
              let messageData = text.data(using: .utf8) else {
            throw ConnectionError.notConnected
        }
        
        let encrypted = try secureChannel.encrypt(messageData, using: sessionKey)
        try await sendData(encrypted, over: connection)
    }
    
    // MARK: - Private
    
    private func performKeyExchange() {
        guard let identityKey = identityKey,
              let connection = connection else {
            connectionState = .error("No identity key available")
            return
        }
        
        // Send our public key
        var publicKey = identityKey.publicKey
        publicKey.insert(0x01, at: 0) // Message type: key exchange
        
        connection.send(content: publicKey, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.connectionState = .error("Key exchange failed: \(error.localizedDescription)")
                }
                return
            }
            
            // Receive their public key
            self?.connection?.receive(minimumIncompleteLength: 33, maximumLength: 33) { [weak self] data, _, _, error in
                guard let data = data, data.count == 33, data[0] == 0x01 else {
                    Task { @MainActor in
                        self?.connectionState = .error("Invalid key exchange response")
                    }
                    return
                }
                
                let theirPublicKey = data.dropFirst(1)
                
                Task { @MainActor in
                    do {
                        let sessionKey = try SessionKey.exchange(
                            theirPublicKey: theirPublicKey,
                            mySecretKey: identityKey.secretKey,
                            myPublicKey: identityKey.publicKey
                        )
                        self?.currentSessionKey = sessionKey
                        self?.connectionState = .connected
                        print("[Crypto] Secure channel established ✓")
                    } catch {
                        self?.connectionState = .error("Key exchange failed")
                    }
                }
            }
        }))
    }
    
    private func sendData(_ data: Data, over connection: NWConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }))
        }
    }
}

extension ConnectionManager: BonjourDiscovererDelegate {
    nonisolated func didDiscover(device: CenturionDevice) {
        Task { @MainActor in
            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device)
            }
        }
    }
    
    nonisolated func didLose(device: CenturionDevice) {
        Task { @MainActor in
            discoveredDevices.removeAll { $0.id == device.id }
        }
    }
}

enum ConnectionError: Error, LocalizedError {
    case notConnected
    case encryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to any Centurion"
        case .encryptionFailed: return "Message encryption failed"
        }
    }
}
