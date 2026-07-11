import Foundation
import Network

/// Manages the encrypted connection between iPhone and Centurion.
///
/// Connection priority:
/// 1. LAN (mDNS/Bonjour) — zero internet, zero latency, maximum privacy
///
/// Encryption flow:
/// 1. Discover Centurion via Bonjour (LAN)
/// 2. Exchange X25519 public keys for key agreement
/// 3. Establish directional session keys
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
    private var pendingDevice: CenturionDevice?
    private var keepaliveTask: Task<Void, Never>?
    private let maximumFrameSize = 8 * 1024 * 1024
    private let handshakeTimeoutSeconds: UInt64 = 15

    private let chatTimeoutSeconds: UInt64 = 180

    enum ConnectionState: Equatable {
        case disconnected
        case discovering
        case connecting
        case connected
        case awaitingApproval(String)
        case error(String)
    }

    init() {
        bonjourDiscoverer.delegate = self
    }

    func startDiscovery() {
        connectionState = .discovering
        do {
            identityKey = try IdentityKey.loadOrCreate()
        } catch {
            connectionState = .error("Your secure iPhone identity could not be loaded.")
            return
        }
        bonjourDiscoverer.startDiscovery()
    }

    func connect(to device: CenturionDevice) {
        disconnect()
        connectionState = .connecting
        pendingDevice = device

        let endpoint: NWEndpoint
        if let name = device.serviceName,
           let type = device.serviceType,
           let domain = device.serviceDomain {
            endpoint = .service(name: name, type: type, domain: domain, interface: nil)
        } else {
            endpoint = .hostPort(
                host: NWEndpoint.Host(device.hostname),
                port: NWEndpoint.Port(rawValue: UInt16(device.port))
                    ?? NWEndpoint.Port(integerLiteral: 9119)
            )
        }

        let newConnection = NWConnection(to: endpoint, using: .tcp)
        connection = newConnection
        installConnectionHandler(for: newConnection)
        newConnection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        pendingDevice = nil
        currentSessionKey = nil
        connectionState = .disconnected
        markDiscoveredDevicesDisconnected()
    }

    func sendMessage(_ text: String) async throws -> String {
        guard let sessionKey = currentSessionKey,
              let connection = connection else {
            throw ConnectionError.notConnected
        }

        let requestID = UUID()
        let request = RemoteEnvelope(type: "chat", id: requestID, text: text)
        let plaintext = try JSONEncoder().encode(request)
        let encrypted = try secureChannel.encrypt(plaintext, using: sessionKey)
        try await sendFrame(encrypted, over: connection)

        let responseFrame = try await withTimeout(seconds: chatTimeoutSeconds) {
            try await receiveFrame(over: connection)
        }
        let responseData = try secureChannel.decrypt(responseFrame, using: sessionKey)
        let response = try JSONDecoder().decode(RemoteEnvelope.self, from: responseData)

        if response.type == "chat_response",
           response.id == requestID,
           let responseText = response.text {
            return responseText
        }
        if response.type == "error" {
            if response.code == "DEVICE_REVOKED" {
                handleDeviceRevoked(
                    response.message
                        ?? "This iPhone is no longer approved on your Centurion."
                )
                throw ConnectionError.serverRejected(
                    response.message
                        ?? "This iPhone is no longer approved on your Centurion."
                )
            }
            throw ConnectionError.serverRejected(
                response.message ?? "Your Centurion could not complete that request."
            )
        }
        throw ConnectionError.invalidResponse
    }

    // MARK: - Private

    private func installConnectionHandler(for newConnection: NWConnection) {
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            Task { @MainActor in
                guard let self, self.connection === newConnection else { return }
                switch state {
                case .ready:
                    if self.connectionState == .connecting {
                        self.performKeyExchange()
                    }
                case .failed(let error):
                    if self.connectionState == .connected {
                        self.handleConnectionLoss(self.friendlyConnectionError(error))
                    } else {
                        self.connectionState = .error(self.friendlyConnectionError(error))
                    }
                case .cancelled:
                    if self.connectionState == .connected {
                        self.handleConnectionLoss("Your Centurion closed the connection")
                    } else if self.connection === newConnection {
                        self.connectionState = .disconnected
                    }
                default:
                    break
                }
            }
        }
    }

    private func handleConnectionLoss(_ message: String) {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        pendingDevice = nil
        currentSessionKey = nil
        markDiscoveredDevicesDisconnected()
        connectionState = .error(message)
    }

    private func performKeyExchange() {
        guard let identityKey = identityKey,
              let connection = connection else {
            connectionState = .error("Your iPhone's secure identity couldn't be loaded.")
            return
        }

        Task {
            do {
                try await withTimeout(seconds: handshakeTimeoutSeconds) {
                    try await self.completeKeyExchange(
                        identityKey: identityKey,
                        connection: connection
                    )
                }
            } catch is TimeoutError {
                self.failConnection(
                    "The connection timed out. Check that both devices are on the same network."
                )
            } catch CryptoError.serverIdentityChanged {
                self.failConnection(
                    "This Centurion was reset. Remove its saved trust in Settings, then connect again."
                )
            } catch ConnectionError.serverRejected(let message) {
                self.failConnection(message)
            } catch {
                self.failConnection(
                    (error as? LocalizedError)?.errorDescription
                        ?? "The secure connection could not be established."
                )
            }
        }
    }

    private func completeKeyExchange(
        identityKey: IdentityKey,
        connection: NWConnection
    ) async throws {
        var publicKey = identityKey.publicKey
        publicKey.insert(0x01, at: 0)

        try await sendData(publicKey, over: connection)
        let data = try await receiveExactly(33, over: connection)
        guard data.count == 33, data[0] == 0x01 else {
            throw ConnectionError.invalidResponse
        }

        let serverPublicKey = Data(data.dropFirst())
        let sessionKey = try SessionKey.exchange(
            theirPublicKey: serverPublicKey,
            mySecretKey: identityKey.secretKey,
            myPublicKey: identityKey.publicKey
        )
        let statusFrame = try await receiveFrame(over: connection)
        let statusData = try secureChannel.decrypt(statusFrame, using: sessionKey)
        let status = try JSONDecoder().decode(RemoteEnvelope.self, from: statusData)
        if status.type == "error" {
            if status.code == "PAIRING_APPROVAL_REQUIRED" {
                await MainActor.run {
                    self.connection?.cancel()
                    self.connection = nil
                    self.currentSessionKey = nil
                    self.connectionState = .awaitingApproval(
                        status.message
                            ?? "Approve this iPhone on your Centurion, then try again."
                    )
                }
                return
            }
            throw ConnectionError.serverRejected(
                status.message ?? "Approve this iPhone on your Centurion, then try again."
            )
        }
        guard status.type == "ready" else {
            throw ConnectionError.invalidResponse
        }
        let trustIdentifier = pendingDevice?.serviceName
            ?? pendingDevice?.hostname
            ?? "default-centurion"
        try ServerTrustStore.verifyOrStore(
            identifier: trustIdentifier,
            publicKey: serverPublicKey
        )

        currentSessionKey = sessionKey
        if let pendingDevice {
            connectedDevice = pendingDevice.asConnected(
                publicKey: serverPublicKey,
                hostname: pendingDevice.hostname.nilIfEmpty,
                port: pendingDevice.port > 0 ? pendingDevice.port : 9119
            )
            markDiscoveredDeviceConnected(pendingDevice.id)
        }
        connectionState = .connected
        bonjourDiscoverer.stopDiscovery()
        startKeepalive()
    }

    private func handleDeviceRevoked(_ message: String) {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        markDiscoveredDevicesDisconnected()
        connectionState = .awaitingApproval(message)
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.connectionState == .connected else { return }
                do {
                    try await self.sendPing()
                } catch {
                    await MainActor.run {
                        if self.connectionState == .connected {
                            self.handleConnectionLoss(
                                "Your Centurion closed the connection"
                            )
                        }
                    }
                    return
                }
            }
        }
    }

    private func sendPing() async throws {
        guard let sessionKey = currentSessionKey,
              let connection = connection else {
            throw ConnectionError.notConnected
        }

        let request = RemoteEnvelope(type: "ping")
        let plaintext = try JSONEncoder().encode(request)
        let encrypted = try secureChannel.encrypt(plaintext, using: sessionKey)
        try await sendFrame(encrypted, over: connection)

        let responseFrame = try await withTimeout(seconds: 15) {
            try await receiveFrame(over: connection)
        }
        let responseData = try secureChannel.decrypt(responseFrame, using: sessionKey)
        let response = try JSONDecoder().decode(RemoteEnvelope.self, from: responseData)
        if response.type == "error", response.code == "DEVICE_REVOKED" {
            handleDeviceRevoked(
                response.message
                    ?? "This iPhone is no longer approved on your Centurion."
            )
            throw ConnectionError.serverRejected(
                response.message
                    ?? "This iPhone is no longer approved on your Centurion."
            )
        }
        guard response.type == "pong" else {
            throw ConnectionError.invalidResponse
        }
    }

    private func failConnection(_ message: String) {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        markDiscoveredDevicesDisconnected()
        connectionState = .error(message)
    }

    private func markDiscoveredDeviceConnected(_ deviceID: UUID) {
        discoveredDevices = discoveredDevices.map { device in
            guard device.id == deviceID else { return device }
            return device.asConnected(publicKey: device.publicKey)
        }
    }

    private func markDiscoveredDevicesDisconnected() {
        discoveredDevices = discoveredDevices.map { device in
            CenturionDevice(
                id: device.id,
                name: device.name,
                hostname: device.hostname,
                ipAddress: device.ipAddress,
                port: device.port,
                serviceName: device.serviceName,
                serviceType: device.serviceType,
                serviceDomain: device.serviceDomain,
                publicKey: device.publicKey,
                isConnected: false,
                connectionMethod: device.connectionMethod,
                lastSeen: device.lastSeen
            )
        }
    }

    private func sendData(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }))
        }
    }

    private func sendFrame(_ payload: Data, over connection: NWConnection) async throws {
        guard payload.count <= maximumFrameSize else {
            throw ConnectionError.messageTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        try await sendData(frame, over: connection)
    }

    private func receiveFrame(over connection: NWConnection) async throws -> Data {
        let header = try await receiveExactly(4, over: connection)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= maximumFrameSize else {
            throw ConnectionError.messageTooLarge
        }
        return try await receiveExactly(Int(length), over: connection)
    }

    private func receiveExactly(_ count: Int, over connection: NWConnection) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk = try await receiveChunk(maxLength: remaining, over: connection)
            result.append(chunk)
        }
        return result
    }

    private func receiveChunk(
        maxLength: Int,
        over connection: NWConnection
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receiveChunkContinuation(
                maxLength: maxLength,
                over: connection,
                continuation: continuation
            )
        }
    }

    private func receiveChunkContinuation(
        maxLength: Int,
        over connection: NWConnection,
        continuation: CheckedContinuation<Data, Error>
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) {
            [weak self] data, _, isComplete, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, !data.isEmpty {
                continuation.resume(returning: data)
            } else if isComplete {
                continuation.resume(throwing: ConnectionError.connectionClosed)
            } else {
                self?.receiveChunkContinuation(
                    maxLength: maxLength,
                    over: connection,
                    continuation: continuation
                )
            }
        }
    }

    private func friendlyConnectionError(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            return "This Centurion is visible but is not accepting connections yet."
        case .posix(.ETIMEDOUT):
            return "The connection timed out. Check that both devices are on the same network."
        default:
            return "Your Centurion could not be reached. Please try again."
        }
    }

    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private struct TimeoutError: Error {}

private struct RemoteEnvelope: Codable {
    let type: String
    let id: UUID?
    let text: String?
    let code: String?
    let message: String?
    let retryable: Bool?

    init(type: String, id: UUID? = nil, text: String? = nil) {
        self.type = type
        self.id = id
        self.text = text
        code = nil
        message = nil
        retryable = nil
    }
}

extension ConnectionManager: BonjourDiscovererDelegate {
    nonisolated func didDiscover(device: CenturionDevice) {
        Task { @MainActor in
            if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                discoveredDevices[index] = device
            } else {
                discoveredDevices.append(device)
            }
        }
    }

    nonisolated func didLose(device: CenturionDevice) {
        Task { @MainActor in
            discoveredDevices.removeAll { $0.id == device.id }
        }
    }

    nonisolated func didFailDiscovery(message: String) {
        Task { @MainActor in
            connectionState = .error(message)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum ConnectionError: Error, LocalizedError {
    case notConnected
    case encryptionFailed
    case connectionClosed
    case invalidResponse
    case messageTooLarge
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to any Centurion"
        case .encryptionFailed: return "Message encryption failed"
        case .connectionClosed: return "Your Centurion closed the connection"
        case .invalidResponse: return "Your Centurion sent an invalid response"
        case .messageTooLarge: return "This message is too large to send"
        case .serverRejected(let message): return message
        }
    }
}
