import Foundation
import Network

/// Manages the encrypted connection between iPhone and Sovereign.
///
/// Connection priority (remote-first):
/// 1. Saved remote pairing endpoint — preferred at home and away
/// 2. LAN (same Wi‑Fi / Bonjour) — bonus when on the same network
/// 3. Tailscale — optional legacy mesh if previously saved
///
/// Encryption flow:
/// 1. Reach Centurion via remote host (or LAN / Tailscale fallback)
/// 2. Exchange X25519 public keys for key agreement
/// 3. If PairRequired: send encrypted pairing token, then Ready
/// 4. All messages encrypted with XSalsa20-Poly1305

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var discoveredDevices: [CenturionDevice] = []
    @Published var connectedDevice: CenturionDevice?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var llmHealth: LLMHealthState = .unknown
    @Published var thinkingStatus: ThinkingServiceStatus?
    @Published var lastLLMError: (message: String, code: String?, retryable: Bool)?
    @Published var remoteCatalog: RemoteModelCatalog?
    @Published var routingMode: String = "manual"
    @Published var lastRoutedDisplayName: String?
    /// True when the model list came from the on-device fallback instead of the Sovereign.
    @Published private(set) var thinkingCatalogUsedFallback = false
    /// Display name of the Sovereign being linked (shown during pairing).
    @Published private(set) var activeConnectionTarget: String?
    /// SHA256 fingerprint of this iPhone’s identity key (for host `approve`).
    @Published private(set) var clientFingerprint: String?
    /// Dangerous-tool approval waiting for the owner during an in-flight Crypto Chat turn.
    @Published var pendingToolApproval: PendingToolApproval?
    /// Honest waiting — short activity hint while a turn is in flight (no PII).
    @Published var turnActivityHint: String?
    /// Live assistant draft while a turn streams (cleared on final/error).
    @Published var streamingAssistantText: String = ""
    private var streamTtftMarked = false
    private var sendStartedAt: Date?
    /// True while Chat is waiting on the Brain — Focus must not pile RPCs on the same pipe.
    @Published private(set) var isRemoteTurnInFlight = false
    /// True while post-pair mission/plan RPCs own the pipe — Chat composer stays locked.
    @Published private(set) var isHydratingAfterLink = false
    /// True after this link already finished (or skipped) mission hydrate. Reset on disconnect.
    @Published private(set) var didHydrateAfterLink = false
    /// Invalidates an in-flight hydrate if the socket drops mid-load.
    private(set) var linkHydrationGeneration = 0
    private var hydrationFetchStarted = false

    /// Side RPCs (keepalive, thinking, beneficiaries) must wait for Chat *and* hydrate.
    var isPipeBusyForSideTraffic: Bool {
        isRemoteTurnInFlight || isHydratingAfterLink
    }

    /// Composer may send only when Crypto Chat is up and mission hydrate has finished.
    var isChatComposerReady: Bool {
        isCryptoChatReady && !isHydratingAfterLink
    }

    /// Prefer LAN Crypto Chat when linked; RelayTransport is the away fallback.
    @Published private(set) var transportPreference: TransportPreference = .lanPreferred
    @Published private(set) var remoteRelayStatus: [String: Any] = [:]
    /// Away Realtime pipe (Supabase). Idle while LAN Crypto Chat is up.
    let relayAway = RelayAwayClient()

    enum TransportPreference: String, Equatable {
        case lanPreferred
        case relayAway
    }

    /// True when LAN Crypto Chat is up — always preferred over the cloud relay.
    var prefersLanCryptoChat: Bool {
        connectionState == .connected && currentSessionKey != nil
    }

    /// Away pipe is live (Realtime joined). Still not a substitute for LAN DoD.
    var isRelayAwayConnected: Bool {
        transportPreference == .relayAway && relayAway.isConnected
    }

    /// Live session is up and messages are secretboxed (LAN or Away relay).
    var isChannelEncrypted: Bool {
        currentSessionKey != nil && (connectionState == .connected || isRelayAwayConnected)
    }

    /// True when either LAN Crypto Chat or Away relay Crypto Chat is ready.
    var isCryptoChatReady: Bool {
        currentSessionKey != nil && (connection != nil || isRelayAwayConnected)
    }

    /// "Remote", "Away", "Tailscale", or "Wi‑Fi" when linked; empty otherwise.
    var linkPathBadge: String {
        if isRelayAwayConnected {
            return "Away"
        }
        guard connectionState == .connected,
              let device = connectedDevice ?? pendingDevice else { return "" }
        if device.isRemotePath {
            return CenturionDevice.ConnectionMethod.remote.linkBadge
        }
        return device.isTailscalePath
            ? CenturionDevice.ConnectionMethod.tailscale.linkBadge
            : CenturionDevice.ConnectionMethod.lan.linkBadge
    }

    /// True when a previous remote, Tailscale, or LAN endpoint was saved for reconnect.
    var hasPersistedLink: Bool {
        loadLastRemoteDevice() != nil
            || loadLastDevice() != nil
            || loadLastLanDevice() != nil
    }

    private let bonjourDiscoverer = BonjourDiscoverer()
    private let secureChannel = SecureChannel()
    private var identityKey: IdentityKey?
    private var currentSessionKey: SessionKey?
    private var connection: NWConnection?
    private var pendingDevice: CenturionDevice?
    /// Pairing token for the in-flight remote connect (also persisted in Keychain).
    private var pendingPairingToken: String?
    private var keepaliveTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var approvalRetryTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var pathDebounceTask: Task<Void, Never>?
    /// When a primary attempt fails, allow one LAN fallback for this reconnect cycle.
    private var allowLanFallback = true
    /// After a primary→LAN cascade, surface primary-path recovery if LAN also fails.
    private var recoveryPrefersPrimary = false
    private let remoteIO = RemoteIOPipeline()
    private let maximumFrameSize = 8 * 1024 * 1024
    private let handshakeTimeoutSeconds: TimeInterval = 15
    private static let lastDeviceKey = "centurion.remote.lastDevice"
    private static let lastLanDeviceKey = "centurion.remote.lastLanDevice"
    private static let lastRemoteDeviceKey = "centurion.remote.lastRemoteDevice"

    private let chatTimeoutSeconds: TimeInterval = 180
    /// Transport + TTFT overhead markers (Workstream C — no PII).
    private(set) var lastTransportRttMs: Double?
    private(set) var lastTtftOverheadMs: Double?
    private(set) var lastColdConnectMs: Double?
    private(set) var lastApprovalAppearMs: Double?
    /// Rolling soak samples for `python -m centurion_cli.remote_relay_speed` (no PII).
    private var rttSamplesMs: [Double] = []
    private var ttftSamplesMs: [Double] = []
    private var coldConnectSamplesMs: [Double] = []
    private var approvalAppearSamplesMs: [Double] = []
    private let maxSpeedSamples = 32

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
        do {
            let identity = try IdentityKey.loadOrCreate()
            identityKey = identity
            clientFingerprint = identity.fingerprint
        } catch {
            // Identity loads again in startDiscovery / connect paths.
        }
        startPathMonitor()
    }

    func startDiscovery() {
        connectionState = .discovering
        do {
            let identity = try IdentityKey.loadOrCreate()
            identityKey = identity
            clientFingerprint = identity.fingerprint
        } catch {
            connectionState = .error("Your secure iPhone identity could not be loaded.")
            return
        }
        bonjourDiscoverer.startDiscovery()
    }

    /// Soft reconnect after the brain operator has approved this fingerprint.
    func retryConnection() {
        reconnectPending(stopApprovalLoop: true)
    }

    /// Return the pairing sheet to a clean form after a failed attempt.
    func resetPairingAttempt() {
        stopApprovalRetryLoop()
        softTearDown(clearPending: false)
        connectionState = .disconnected
        activeConnectionTarget = nil
    }

    /// One-tap reconnect: remote first, then LAN, then legacy Tailscale.
    func reconnect() {
        allowLanFallback = true
        recoveryPrefersPrimary = false
        reconnectWithPriority(stopApprovalLoop: true)
    }

    /// Reconnect without cancelling an active approval poll (used by the auto-retry loop).
    private func reconnectPending(stopApprovalLoop: Bool) {
        reconnectWithPriority(stopApprovalLoop: stopApprovalLoop)
    }

    /// Prefer saved remote endpoint; LAN next; Tailscale only as legacy.
    private func reconnectWithPriority(stopApprovalLoop: Bool) {
        if stopApprovalLoop {
            stopApprovalRetryLoop()
        }

        // Keep Bonjour warm for LAN fallback inventory.
        if connectionState != .discovering {
            bonjourDiscoverer.startDiscovery()
        }

        if let pending = pendingDevice, pending.isRemotePath {
            pendingPairingToken = RemotePairingTokenStore.load()
            connect(to: pending, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let remote = loadLastRemoteDevice() {
            pendingDevice = remote
            pendingPairingToken = RemotePairingTokenStore.load()
            connect(to: remote, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let pending = pendingDevice, !pending.isTailscalePath {
            connect(to: pending, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let lan = loadLastLanDevice() {
            pendingDevice = lan
            connect(to: lan, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let pending = pendingDevice, pending.isTailscalePath {
            connect(to: pending, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let saved = loadLastDevice(), saved.isTailscalePath {
            pendingDevice = saved
            connect(to: saved, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let saved = loadLastDevice() {
            pendingDevice = saved
            connect(to: saved, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let device = discoveredDevices.first {
            connect(to: device, stopApprovalLoop: stopApprovalLoop)
            return
        }
        startDiscovery()
    }

    /// After splash / on enter foreground: remote first, then LAN / Tailscale.
    func attemptAutoReconnect() {
        guard connectionState == .disconnected || isErrorState else { return }
        guard hasPersistedLink else { return }
        allowLanFallback = true
        reconnectWithPriority(stopApprovalLoop: true)
    }

    private var isErrorState: Bool {
        if case .error = connectionState { return true }
        return false
    }

    /// Link using a remote pairing connection string (`token:…@host:port`).
    func connectRemote(connectionString: String) {
        guard let components = RemoteConnectionString.parse(connectionString) else {
            connectionState = .error(
                "That pairing code looks incomplete. Paste the full code from your Centurion (it starts with token:)."
            )
            return
        }
        connectRemote(token: components.token, host: components.host, port: components.port)
    }

    /// Link to a remote host with an authenticated pairing token.
    func connectRemote(token: String, host: String, port: Int = 9119, name: String = "Sovereign") {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, !trimmedToken.isEmpty else {
            connectionState = .error("Enter the pairing code from your Centurion.")
            return
        }
        RemotePairingTokenStore.save(trimmedToken)
        pendingPairingToken = trimmedToken
        let device = CenturionDevice(
            id: UUID(),
            name: name,
            hostname: trimmedHost.contains(where: \.isLetter) ? trimmedHost : "",
            ipAddress: trimmedHost.contains(where: \.isLetter) ? "" : trimmedHost,
            port: port > 0 ? port : 9119,
            serviceName: nil,
            serviceType: nil,
            serviceDomain: nil,
            publicKey: nil,
            isConnected: false,
            connectionMethod: .remote,
            lastSeen: Date()
        )
        allowLanFallback = true
        connect(to: device)
    }

    /// Manual host / IP connect. Remote hosts use `.lan` unless Tailscale is detected.
    func connect(host: String, port: Int = 9119, name: String = "Sovereign") {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            connectionState = .error("Enter the Sovereign’s hostname or IP address.")
            return
        }
        let isTailscale = CenturionDevice.isTailscaleHost(trimmed)
        let device = CenturionDevice(
            id: UUID(),
            name: name,
            hostname: trimmed.contains(where: \.isLetter) ? trimmed : "",
            ipAddress: trimmed.contains(where: \.isLetter) ? "" : trimmed,
            port: port > 0 ? port : 9119,
            serviceName: nil,
            serviceType: nil,
            serviceDomain: nil,
            publicKey: nil,
            isConnected: false,
            connectionMethod: isTailscale ? .tailscale : .lan,
            lastSeen: Date()
        )
        allowLanFallback = true
        connect(to: device)
    }

    /// Prefer a stable host/IP endpoint. Bonjour `.service` endpoints are fragile:
    /// stopping or refreshing the browser can cancel sockets opened that way, which
    /// showed up as a brief success then "could not be reached" on reconnect.
    private func connectionEndpoint(for device: CenturionDevice) -> NWEndpoint {
        let port = NWEndpoint.Port(rawValue: UInt16(device.port))
            ?? NWEndpoint.Port(integerLiteral: 9119)

        // Prefer hostname for remote / Tailscale MagicDNS so the path stays stable.
        if (device.isRemotePath || device.isTailscalePath), !device.hostname.isEmpty {
            return .hostPort(host: NWEndpoint.Host(device.hostname), port: port)
        }

        if !device.ipAddress.isEmpty {
            return .hostPort(host: NWEndpoint.Host(device.ipAddress), port: port)
        }

        if !device.hostname.isEmpty {
            let host = device.hostname.contains(".")
                ? device.hostname
                : "\(device.hostname).local"
            return .hostPort(host: NWEndpoint.Host(host), port: port)
        }

        if let name = device.serviceName,
           let type = device.serviceType,
           let domain = device.serviceDomain {
            return .service(name: name, type: type, domain: domain, interface: nil)
        }

        return .hostPort(host: NWEndpoint.Host("localhost"), port: port)
    }

    private func resolvedRemoteIP(from connection: NWConnection) -> String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return nil }
        switch endpoint {
        case .hostPort(let host, _):
            let value = "\(host)"
            // Strip optional zone id (e.g. fe80::1%en0).
            if let percent = value.firstIndex(of: "%") {
                return String(value[..<percent])
            }
            return value
        default:
            return nil
        }
    }

    private func connectionParameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }

    func connect(to device: CenturionDevice, stopApprovalLoop: Bool = true) {
        if stopApprovalLoop {
            stopApprovalRetryLoop()
        }
        softTearDown(clearPending: false)
        connectionState = .connecting
        activeConnectionTarget = device.name
        pendingDevice = device

        let endpoint = connectionEndpoint(for: device)
        let newConnection = NWConnection(to: endpoint, using: connectionParameters())
        connection = newConnection
        installConnectionHandler(for: newConnection)
        startConnectionTimeout()
        newConnection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        stopApprovalRetryLoop()
        softTearDown(clearPending: true)
        bonjourDiscoverer.stopDiscovery()
        clearLastDevice()
        clearLastLanDevice()
        clearLastRemoteDevice()
        RemotePairingTokenStore.clear()
        pendingPairingToken = nil
        allowLanFallback = true
        recoveryPrefersPrimary = false
        connectionState = .disconnected
        markDiscoveredDevicesDisconnected()
    }

    /// Tears the socket down without wiping pairing context (approval retry).
    private func softTearDown(clearPending: Bool) {
        abortInFlightTurn(clearApproval: true)
        resetPostLinkHydration()
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        activeConnectionTarget = nil
        if clearPending {
            pendingDevice = nil
        }
    }

    private func persistLastDevice(_ device: CenturionDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        UserDefaults.standard.set(data, forKey: Self.lastDeviceKey)
    }

    private func loadLastDevice() -> CenturionDevice? {
        guard let data = UserDefaults.standard.data(forKey: Self.lastDeviceKey) else { return nil }
        return try? JSONDecoder().decode(CenturionDevice.self, from: data)
    }

    private func clearLastDevice() {
        UserDefaults.standard.removeObject(forKey: Self.lastDeviceKey)
    }

    private func persistLastLanDevice(_ device: CenturionDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        UserDefaults.standard.set(data, forKey: Self.lastLanDeviceKey)
    }

    private func loadLastLanDevice() -> CenturionDevice? {
        guard let data = UserDefaults.standard.data(forKey: Self.lastLanDeviceKey) else { return nil }
        return try? JSONDecoder().decode(CenturionDevice.self, from: data)
    }

    private func clearLastLanDevice() {
        UserDefaults.standard.removeObject(forKey: Self.lastLanDeviceKey)
    }

    private func persistLastRemoteDevice(_ device: CenturionDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        UserDefaults.standard.set(data, forKey: Self.lastRemoteDeviceKey)
    }

    private func loadLastRemoteDevice() -> CenturionDevice? {
        guard let data = UserDefaults.standard.data(forKey: Self.lastRemoteDeviceKey) else { return nil }
        return try? JSONDecoder().decode(CenturionDevice.self, from: data)
    }

    private func clearLastRemoteDevice() {
        UserDefaults.standard.removeObject(forKey: Self.lastRemoteDeviceKey)
    }

    /// Persist remote as primary when possible; keep LAN / Tailscale as secondary.
    private func persistLinkedDevice(_ linked: CenturionDevice) {
        if linked.isRemotePath {
            persistLastRemoteDevice(linked)
            persistLastDevice(linked)
            return
        }
        if linked.isTailscalePath {
            persistLastDevice(linked)
            return
        }
        persistLastLanDevice(linked)
        if loadLastRemoteDevice() == nil,
           let primary = loadLastDevice(),
           primary.isTailscalePath || primary.isRemotePath {
            // Keep remote / Tailscale as the preferred reconnect target.
        } else if loadLastRemoteDevice() == nil {
            persistLastDevice(linked)
        }
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handlePathChange()
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    private func handlePathChange() {
        pathDebounceTask?.cancel()
        pathDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled else { return }

            // Prefer saved remote whenever available — upgrade off LAN fallback.
            if self.connectionState == .connected,
               let current = self.connectedDevice, !current.isRemotePath,
               let remote = self.loadLastRemoteDevice() {
                self.allowLanFallback = true
                self.recoveryPrefersPrimary = false
                self.pendingPairingToken = RemotePairingTokenStore.load()
                self.connect(to: remote, stopApprovalLoop: true)
                return
            }

            guard self.connectionState == .disconnected || self.isErrorState else { return }
            // Away candidate: try Realtime when LAN/remote TCP is down and Brain is online.
            Task { await self.considerRelayAway() }
            guard self.hasPersistedLink else { return }
            self.allowLanFallback = true
            self.recoveryPrefersPrimary = false
            self.reconnectWithPriority(stopApprovalLoop: true)
        }
    }

    private func startApprovalRetryLoop() {
        stopApprovalRetryLoop()
        approvalRetryTask = Task { @MainActor [weak self] in
            // Poll gently so the user only needs to approve on Fedora once.
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self else { return }
                guard case .awaitingApproval = self.connectionState else { return }
                self.reconnectPending(stopApprovalLoop: false)
                // Wait for this attempt to settle before looping.
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if self.connectionState == .connected { return }
                if case .awaitingApproval = self.connectionState { continue }
                if case .connecting = self.connectionState {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                }
                if self.connectionState == .connected { return }
            }
        }
    }

    private func stopApprovalRetryLoop() {
        approvalRetryTask?.cancel()
        approvalRetryTask = nil
    }

    func sendMessage(
        _ text: String,
        sessionId: String? = nil,
        lifeInject: [String: Any]? = nil
    ) async throws -> (text: String, sessionId: String?) {
        guard currentSessionKey != nil, isCryptoChatReady else {
            throw ConnectionError.notConnected
        }
        guard !isHydratingAfterLink else {
            throw ConnectionError.hydrating
        }

        let requestID = UUID()
        var body: [String: Any] = [
            "type": "chat",
            "id": requestID.uuidString,
            "text": text,
        ]
        if let sessionId, !sessionId.isEmpty {
            body["session_id"] = sessionId
        }
        if let lifeInject, !lifeInject.isEmpty {
            body["life_inject"] = lifeInject
        }
        let plaintext = try JSONSerialization.data(withJSONObject: body)

        let sendStarted = Date()
        turnActivityHint = "Waiting on your Sovereign…"
        streamingAssistantText = ""
        streamTtftMarked = false
        sendStartedAt = sendStarted
        isRemoteTurnInFlight = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self else { return }
            guard self.isRemoteTurnInFlight, self.sendStartedAt == sendStarted else { return }
            guard self.streamingAssistantText.isEmpty else { return }
            if self.turnActivityHint == "Waiting on your Sovereign…" {
                self.turnActivityHint = "Still starting on your Sovereign. Stay on Chat — do not open Focus."
            }
        }
        let responseData: Data
        do {
            responseData = try await withTimeout(seconds: chatTimeoutSeconds) {
                try await self.exchangeEncrypted(
                    plaintext: plaintext,
                    onPush: { [weak self] push in
                        await MainActor.run {
                            self?.handlePushedRemoteMessage(push)
                        }
                    }
                )
            }
        } catch is TimeoutError {
            abortInFlightTurn(clearApproval: true)
            poisonPipelineAndReconnect()
            let message = "Your Sovereign is taking too long to respond. Try again in a moment."
            lastLLMError = (message, "LLM_UNAVAILABLE", true)
            throw ConnectionError.serverRejected(message)
        } catch let relay as RelayTransport.RelayError {
            abortInFlightTurn(clearApproval: true)
            let message = relay.errorDescription
                ?? "Chat from anywhere dropped. Retry the turn."
            let code = relay.isRetryableMidTurn ? "RELAY_RECONNECT" : "RELAY_ERROR"
            lastLLMError = (message, code, relay.isRetryableMidTurn)
            if relay.isRetryableMidTurn {
                // Drop session keys so the next send re-KXs after reconnect.
                currentSessionKey = nil
                Task { await self.considerRelayAway() }
            }
            throw ConnectionError.serverRejected(message)
        } catch {
            abortInFlightTurn(clearApproval: true)
            if Self.isDroppedSocket(error) {
                poisonPipelineAndReconnect()
            }
            throw error
        }
        if !streamTtftMarked {
            let ms = Date().timeIntervalSince(sendStarted) * 1000
            lastTtftOverheadMs = ms
            recordSpeedSample(ms, into: &ttftSamplesMs)
        }
        turnActivityHint = nil
        streamingAssistantText = ""
        pendingToolApproval = nil
        sendStartedAt = nil
        isRemoteTurnInFlight = false
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let responseType = json["type"] as? String else {
            throw ConnectionError.invalidResponse
        }

        if responseType == "chat_response",
           let responseText = json["text"] as? String {
            let responseId = (json["id"] as? String).flatMap(UUID.init(uuidString:))
            if let responseId, responseId != requestID {
                throw ConnectionError.invalidResponse
            }
            llmHealth = .healthy
            lastLLMError = nil
            if let routed = json["routed_display_name"] as? String, !routed.isEmpty {
                lastRoutedDisplayName = routed
            }
            if json["recovered"] as? Bool == true {
                await refreshThinkingStatus()
            }
            let hostSession = json["session_id"] as? String
            return (responseText, hostSession)
        }
        if responseType == "error" {
            let code = json["code"] as? String
            if code == "DEVICE_REVOKED" {
                let message = (json["message"] as? String)
                    ?? "This iPhone is no longer approved on your Sovereign."
                handleDeviceRevoked(message)
                throw ConnectionError.serverRejected(message)
            }
            let message = (json["message"] as? String)
                ?? "Your Sovereign could not complete that request."
            let retryable = json["retryable"] as? Bool ?? true
            lastLLMError = (message, code, retryable)
            if LLMHealthState.isThinkingSetupProblem(code) {
                llmHealth = .broken(message, code: code, retryable: retryable)
            }
            throw ConnectionError.serverRejected(message)
        }
        throw ConnectionError.invalidResponse
    }

    @MainActor
    private func handlePushedRemoteMessage(_ push: [String: Any]) {
        guard let type = push["type"] as? String else { return }
        if type == "approval_request" {
            turnActivityHint = "Approval needed"
            if let started = sendStartedAt {
                let ms = Date().timeIntervalSince(started) * 1000
                lastApprovalAppearMs = ms
                recordSpeedSample(ms, into: &approvalAppearSamplesMs)
            }
            pendingToolApproval = PendingToolApproval(
                approvalId: (push["approval_id"] as? String) ?? "",
                sessionKey: (push["session_key"] as? String) ?? "",
                command: (push["command"] as? String) ?? "",
                description: (push["description"] as? String) ?? "This action needs your approval.",
                patternKey: push["pattern_key"] as? String,
                choices: (push["choices"] as? [String]) ?? ["once", "session", "always", "deny"]
            )
            return
        }
        if type == "stream_delta" || type == "partial" {
            let chunk = (push["text"] as? String) ?? (push["delta"] as? String) ?? ""
            guard !chunk.isEmpty else { return }
            if !streamTtftMarked {
                streamTtftMarked = true
                if let started = sendStartedAt {
                    let ms = Date().timeIntervalSince(started) * 1000
                    lastTtftOverheadMs = ms
                    recordSpeedSample(ms, into: &ttftSamplesMs)
                }
                turnActivityHint = nil
            }
            streamingAssistantText += chunk
            return
        }
        if type == "activity" || type == "tool_progress" || type == "status" {
            // Prefer live stream text over status chatter once tokens started.
            if !streamingAssistantText.isEmpty { return }
            let detail = (push["message"] as? String)
                ?? (push["text"] as? String)
                ?? (push["line"] as? String)
                ?? (push["description"] as? String)
                ?? (push["preview"] as? String)
                ?? (push["tool"] as? String)
                ?? "Working…"
            turnActivityHint = detail
        }
    }

    func respondToToolApproval(choice: String, resolveAll: Bool = false) async throws {
        guard let pending = pendingToolApproval else { return }
        _ = try await invokeRemote(
            action: "approval_respond",
            extra: [
                "approval_id": pending.approvalId,
                "session_key": pending.sessionKey.isEmpty ? pending.approvalId : pending.sessionKey,
                "choice": choice,
                "all": resolveAll,
            ],
            timeoutSeconds: 30
        )
        if choice == "deny" {
            pendingToolApproval = nil
        }
    }

    func refreshGatewayStatus() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "gateway_status")
        return (payload["status"] as? [String: Any]) ?? payload
    }

    func gatewayStart() async throws -> [String: Any] {
        try await invokeRemote(action: "gateway_start", timeoutSeconds: 60)
    }

    func gatewayStop() async throws -> [String: Any] {
        try await invokeRemote(action: "gateway_stop", timeoutSeconds: 60)
    }

    func gatewayRestart() async throws -> [String: Any] {
        try await invokeRemote(action: "gateway_restart", timeoutSeconds: 90)
    }

    func gatewayPlatformSet(platform: String, enabled: Bool, restart: Bool = true) async throws -> [String: Any] {
        try await invokeRemote(
            action: "gateway_platform_set",
            extra: [
                "platform": platform,
                "enabled": enabled,
                "restart": restart,
            ],
            timeoutSeconds: 90
        )
    }

    func listHostSessions(limit: Int = 20) async throws -> [[String: Any]] {
        let payload = try await invokeRemote(
            action: "session_list",
            extra: ["limit": limit, "source": "remote"]
        )
        return (payload["sessions"] as? [[String: Any]]) ?? []
    }

    /// Refresh Brain `remote_relay` status. LAN stays preferred when connected.
    @discardableResult
    func refreshRemoteRelayStatus() async -> [String: Any] {
        guard connectionState == .connected else {
            await considerRelayAway()
            return remoteRelayStatus
        }
        // LAN up — tear down any away socket (product rule: prefer :9119).
        if relayAway.isConnected {
            relayAway.disconnect(resetEpoch: true)
        }
        do {
            let payload = try await invokeRemote(action: "remote_relay_status")
            remoteRelayStatus = payload
            // Cache cloud endpoints from Brain for away reconnect without LAN.
            if let url = payload["supabase_url"] as? String, !url.isEmpty,
               let key = payload["supabase_anon_key"] as? String, !key.isEmpty {
                let control = payload["control_base"] as? String
                relayAway.configure(supabaseURL: url, anonKey: key, controlBase: control)
            }
            if let installId = payload["install_id"] as? String, !installId.isEmpty {
                UserDefaults.standard.set(installId, forKey: "centurion.remoteRelay.installId")
            }
            let enabled = payload["enabled"] as? Bool ?? false
            let online = ((payload["presence"] as? [String: Any])?["online"] as? Bool) ?? false
            // Product rule: if LAN is up, stay on LAN even when relay is enabled.
            if prefersLanCryptoChat {
                transportPreference = .lanPreferred
            } else if enabled && online {
                transportPreference = .relayAway
            } else {
                transportPreference = .lanPreferred
            }
            return payload
        } catch {
            return remoteRelayStatus
        }
    }

    /// When LAN Crypto Chat is down, join Realtime if Brain presence is online.
    func considerRelayAway() async {
        if prefersLanCryptoChat {
            if relayAway.isConnected {
                relayAway.disconnect(resetEpoch: true)
            }
            transportPreference = .lanPreferred
            return
        }
        let enabled = (remoteRelayStatus["enabled"] as? Bool)
            ?? UserDefaults.standard.bool(forKey: "centurion.remoteRelay.enabledHint")
        let installId = (remoteRelayStatus["install_id"] as? String)
            ?? UserDefaults.standard.string(forKey: "centurion.remoteRelay.installId")
            ?? ""
        guard enabled || !installId.isEmpty else {
            transportPreference = .lanPreferred
            return
        }
        if !installId.isEmpty {
            UserDefaults.standard.set(installId, forKey: "centurion.remoteRelay.installId")
        }
        if let enabledFlag = remoteRelayStatus["enabled"] as? Bool {
            UserDefaults.standard.set(enabledFlag, forKey: "centurion.remoteRelay.enabledHint")
        }
        // Prefer cached cloud endpoints when LAN is down.
        if RelayAwayClient.Cloud.supabaseURL.isEmpty,
           let url = UserDefaults.standard.string(forKey: "centurion.remoteRelay.supabaseURL"),
           let key = UserDefaults.standard.string(forKey: "centurion.remoteRelay.supabaseAnonKey"),
           !url.isEmpty, !key.isEmpty {
            relayAway.configure(supabaseURL: url, anonKey: key)
        }
        await relayAway.refreshPresence(installId: installId)
        guard relayAway.brainOnline else {
            transportPreference = .lanPreferred
            // Honest offline — same class as gateway-down (never fall back to demo).
            if connection == nil {
                let detail = relayAway.lastError?.trimmingCharacters(in: .whitespacesAndNewlines)
                let message: String
                if let detail, !detail.isEmpty {
                    message = "Your Sovereign is offline for Chat from anywhere. \(detail)"
                } else {
                    message = "Your Sovereign is offline. Chat from anywhere needs the Brain online and awake."
                }
                connectionState = .error(message)
            }
            return
        }
        do {
            let kxStarted = Date()
            if !relayAway.isConnected {
                try await relayAway.connect(installId: installId)
            }
            if currentSessionKey == nil || !relayAway.transportSession.sessionKeysValid {
                try await performRelayKeyExchange()
            }
            let coldMs = Date().timeIntervalSince(kxStarted) * 1000
            lastColdConnectMs = coldMs
            recordSpeedSample(coldMs, into: &coldConnectSamplesMs)
            transportPreference = .relayAway
            connectionState = .connected
            beginPostLinkHydration()
            startKeepalive()
            Task { await refreshThinkingStatus() }
        } catch {
            transportPreference = .lanPreferred
            if connection == nil {
                let detail = (error as? LocalizedError)?.errorDescription
                    ?? relayAway.lastError
                    ?? error.localizedDescription
                connectionState = .error(
                    "Could not reach your Sovereign over Chat from anywhere. \(detail)"
                )
            }
        }
    }

    /// KX + Ready over RelayTransport (mirrors LAN ``completeKeyExchange``).
    private func performRelayKeyExchange() async throws {
        guard let identityKey else {
            throw ConnectionError.notConnected
        }
        var publicKey = identityKey.publicKey
        publicKey.insert(0x01, at: 0)
        try await relayAway.sendKx(publicKey, client: true)
        let kxInbound = try await relayAway.waitForInbound(timeoutSeconds: handshakeTimeoutSeconds)
        guard case .kxServer(let data) = kxInbound, data.count == 33, data[0] == 0x01 else {
            throw ConnectionError.invalidResponse
        }
        let serverPublicKey = Data(data.dropFirst())
        let sessionKey = try SessionKey.exchange(
            theirPublicKey: serverPublicKey,
            mySecretKey: identityKey.secretKey,
            myPublicKey: identityKey.publicKey
        )
        relayAway.markKxComplete()
        // Ready / PairRequired (encrypted status frame).
        let statusInbound = try await relayAway.waitForInbound(timeoutSeconds: handshakeTimeoutSeconds)
        guard case .frame(let statusFrame) = statusInbound else {
            throw ConnectionError.invalidResponse
        }
        let statusData = try secureChannel.decrypt(statusFrame, using: sessionKey)
        var status = try JSONDecoder().decode(RemoteEnvelope.self, from: statusData)

        if status.type == "pair_required" {
            let token = pendingPairingToken ?? RemotePairingTokenStore.load()
            guard let token, !token.isEmpty else {
                throw ConnectionError.serverRejected(
                    "Your Centurion needs a pairing code. Pair once on home Wi‑Fi first."
                )
            }
            let pairRequest = RemoteEnvelope(type: "pair", token: token)
            let pairPlain = try JSONEncoder().encode(pairRequest)
            currentSessionKey = sessionKey
            let pairResponseData = try await exchangeEncrypted(plaintext: pairPlain)
            status = try JSONDecoder().decode(RemoteEnvelope.self, from: pairResponseData)
            if status.type == "pair_rejected" || status.type == "error" {
                currentSessionKey = nil
                throw ConnectionError.serverRejected(
                    status.message ?? "That pairing code could not be verified."
                )
            }
        }

        if status.type == "error" {
            if status.code == "PAIRING_APPROVAL_REQUIRED" {
                currentSessionKey = nil
                connectionState = .awaitingApproval(
                    status.message
                        ?? "Approve this iPhone on your Sovereign computer, then try Chat from anywhere again."
                )
                throw ConnectionError.serverRejected(status.message ?? "Approval required")
            }
            throw ConnectionError.serverRejected(
                status.message ?? "Approve this iPhone on your Sovereign, then try again."
            )
        }
        guard status.type == "ready" else {
            throw ConnectionError.invalidResponse
        }
        let trustIdentifier = pendingDevice?.serviceName
            ?? pendingDevice?.hostname
            ?? connectedDevice?.serviceName
            ?? connectedDevice?.hostname
            ?? "default-centurion"
        try ServerTrustStore.verifyOrStore(
            identifier: trustIdentifier,
            publicKey: serverPublicKey
        )
        currentSessionKey = sessionKey
    }

    /// Encrypt + send over LAN TCP or Away relay; demux approval pushes.
    private func exchangeEncrypted(
        plaintext: Data,
        onPush: (([String: Any]) async -> Void)? = nil
    ) async throws -> Data {
        guard let sessionKey = currentSessionKey else {
            throw ConnectionError.notConnected
        }
        if prefersLanCryptoChat, let connection {
            return try await remoteIO.exchange(
                connection: connection,
                secureChannel: secureChannel,
                sessionKey: sessionKey,
                maximumFrameSize: maximumFrameSize,
                plaintext: plaintext,
                onPush: onPush
            )
        }
        if isRelayAwayConnected {
            let encrypted = try secureChannel.encrypt(plaintext, using: sessionKey)
            try await relayAway.sendCiphertext(encrypted)
            while true {
                let inbound = try await relayAway.waitForInbound(timeoutSeconds: chatTimeoutSeconds)
                guard case .frame(let frame) = inbound else { continue }
                let decrypted = try secureChannel.decrypt(frame, using: sessionKey)
                if let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any],
                   let type = json["type"] as? String,
                   type == "approval_request"
                    || type == "activity"
                    || type == "tool_progress"
                    || type == "status"
                    || type == "stream_delta"
                    || type == "partial" {
                    if let onPush {
                        await onPush(json)
                    }
                    continue
                }
                return decrypted
            }
        }
        throw ConnectionError.notConnected
    }

    /// Enable Chat from anywhere on the linked Brain (control plane + presence).
    func enableRemoteRelay(supabaseUrl: String? = nil, anonKey: String? = nil) async throws -> [String: Any] {
        var extra: [String: Any] = [:]
        if let supabaseUrl, !supabaseUrl.isEmpty { extra["supabase_url"] = supabaseUrl }
        if let anonKey, !anonKey.isEmpty { extra["supabase_anon_key"] = anonKey }
        let payload = try await invokeRemote(action: "remote_relay_enable", extra: extra)
        if let ok = payload["ok"] as? Bool, ok == false {
            throw ConnectionError.serverRejected(
                (payload["message"] as? String)
                    ?? (payload["error"] as? String)
                    ?? "Could not enable Chat from anywhere."
            )
        }
        remoteRelayStatus = payload
        if let url = payload["supabase_url"] as? String, !url.isEmpty,
           let key = payload["supabase_anon_key"] as? String, !key.isEmpty {
            relayAway.configure(
                supabaseURL: url,
                anonKey: key,
                controlBase: payload["control_base"] as? String
            )
        }
        if let installId = payload["install_id"] as? String, !installId.isEmpty {
            UserDefaults.standard.set(installId, forKey: "centurion.remoteRelay.installId")
        }
        UserDefaults.standard.set(true, forKey: "centurion.remoteRelay.enabledHint")
        return payload
    }

    func createHostSession(
        title: String? = nil,
        previousSessionId: String? = nil,
        topicKind: String? = nil,
        topicRef: [String: Any]? = nil
    ) async throws -> String {
        var extra: [String: Any] = [:]
        if let title, !title.isEmpty { extra["title"] = title }
        if let previousSessionId, !previousSessionId.isEmpty {
            extra["previous_session_id"] = previousSessionId
        }
        if let topicKind, !topicKind.isEmpty {
            extra["topic_kind"] = topicKind
            if let topicRef { extra["topic_ref"] = topicRef }
        }
        let payload = try await invokeRemote(action: "session_new", extra: extra)
        guard let sessionId = payload["session_id"] as? String, !sessionId.isEmpty else {
            throw ConnectionError.invalidResponse
        }
        return sessionId
    }

    func setHostSessionTopic(
        sessionId: String,
        topicKind: String?,
        topicRef: [String: Any]? = nil
    ) async throws {
        var extra: [String: Any] = ["session_id": sessionId]
        if let topicKind, !topicKind.isEmpty {
            extra["topic_kind"] = topicKind
            if let topicRef { extra["topic_ref"] = topicRef }
        } else {
            extra["topic_kind"] = ""
        }
        _ = try await invokeRemote(action: "session_set_topic", extra: extra)
    }

    func renameHostSession(sessionId: String, title: String) async throws -> String {
        let payload = try await invokeRemote(
            action: "session_rename",
            extra: ["session_id": sessionId, "title": title]
        )
        return (payload["title"] as? String) ?? title
    }

    func deleteHostSession(sessionId: String) async throws {
        _ = try await invokeRemote(
            action: "session_delete",
            extra: ["session_id": sessionId]
        )
    }

    func disableRemoteRelay() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "remote_relay_disable")
        remoteRelayStatus = payload
        UserDefaults.standard.set(false, forKey: "centurion.remoteRelay.enabledHint")
        relayAway.disconnect(resetEpoch: true)
        if prefersLanCryptoChat {
            transportPreference = .lanPreferred
        }
        return payload
    }

    // MARK: - Desk ops (Brain Settings parity)

    func opsGlance() async throws -> [String: Any] {
        try await invokeRemote(action: "ops_glance")
    }

    func licenseStatus() async throws -> [String: Any] {
        try await invokeRemote(action: "license_status")
    }

    func licenseRedeem(code: String) async throws -> [String: Any] {
        try await invokeRemote(
            action: "license_redeem",
            extra: ["code": code],
            timeoutSeconds: 60
        )
    }

    func setToolEnv(key: String, value: String) async throws -> [String: Any] {
        try await invokeRemote(
            action: "tool_env_set",
            extra: ["key": key, "value": value],
            timeoutSeconds: 45
        )
    }

    func toolsSkillsSnapshot() async throws -> [String: Any] {
        try await invokeRemote(action: "tools_skills_snapshot")
    }

    func fleetStatus() async throws -> [String: Any] {
        try await invokeRemote(action: "fleet_status")
    }

    func pluginList() async throws -> [String: Any] {
        try await invokeRemote(action: "plugin_list")
    }

    func telegramImportPreview() async throws -> [String: Any] {
        try await invokeRemote(action: "telegram_import_preview", timeoutSeconds: 60)
    }

    func bridgePing() async throws -> [String: Any] {
        try await invokeRemote(action: "bridge_ping", timeoutSeconds: 15)
    }

    func resumeHostSession(_ sessionId: String) async throws -> (
        sessionId: String,
        title: String,
        topicKind: String,
        topicRef: Any?,
        messages: [[String: Any]],
        truncated: Bool
    ) {
        // Away Realtime frames have a hard encrypted payload ceiling; ask Brain
        // to cap history and retry smaller if a frame still won't fit.
        var limit: Int? = isRelayAwayConnected ? 120 : nil
        var lastError: Error?
        for _ in 0..<4 {
            var extra: [String: Any] = ["session_id": sessionId]
            if let limit {
                extra["limit"] = limit
            }
            do {
                let payload = try await invokeRemote(
                    action: "session_resume",
                    extra: extra
                )
                let tip = (payload["session_id"] as? String) ?? sessionId
                let messages = (payload["messages"] as? [[String: Any]]) ?? []
                let title = (payload["title"] as? String) ?? ""
                let topicKind = (payload["topic_kind"] as? String) ?? ""
                let truncated = (payload["truncated"] as? Bool) ?? false
                return (tip, title, topicKind, payload["topic_ref"], messages, truncated)
            } catch RelayTransport.RelayError.payloadTooLarge {
                lastError = RelayTransport.RelayError.payloadTooLarge
                if let current = limit {
                    limit = max(20, current / 2)
                    continue
                }
                throw RelayTransport.RelayError.payloadTooLarge
            } catch {
                throw error
            }
        }
        throw lastError ?? RelayTransport.RelayError.payloadTooLarge
    }

    func refreshThinkingStatus(forceProbe: Bool = false) async {
        guard isCryptoChatReady else { return }
        if isPipeBusyForSideTraffic, !forceProbe { return }
        do {
            let payload = try await invokeRemote(
                action: "provider_status",
                extra: ["skip_probe": !forceProbe]
            )
            if let statusData = try? JSONSerialization.data(withJSONObject: payload["status"] ?? [:]),
               let status = try? JSONDecoder().decode(ThinkingServiceStatus.self, from: statusData) {
                thinkingStatus = status
                if thinkingCatalogUsedFallback || remoteCatalog == nil {
                    remoteCatalog = bundledCatalogFromKnownStatus()
                }
                switch status.health {
                case "ok":
                    llmHealth = .healthy
                case "degraded":
                    llmHealth = .degraded(status.healthMessage)
                case "broken":
                    llmHealth = .broken(
                        status.healthMessage,
                        code: "LLM_CONFIG_INVALID",
                        retryable: true
                    )
                default:
                    llmHealth = .unknown
                }
            }
        } catch {
            llmHealth = .unknown
        }
    }

    func refreshRoutingMode() async {
        guard connectionState == .connected else { return }
        if isPipeBusyForSideTraffic { return }
        do {
            let payload = try await invokeRemote(action: "remote_routing_mode")
            if let mode = payload["routing_mode"] as? String, !mode.isEmpty {
                routingMode = mode
            }
        } catch {
            // Keep the last known routing mode.
        }
    }

    /// User-facing name for the active LLM (not the Sovereign device name).
    var thinkingServiceHeadline: String {
        if isHydratingAfterLink {
            return "Loading missions"
        }
        if isRemoteTurnInFlight, llmHealth == .unknown {
            return "Waiting on Chat"
        }
        if routingMode == "phoenix", lastRoutedDisplayName?.isEmpty != false {
            return "Auto-select"
        }
        if let name = activeThinkingDisplayName {
            return name
        }
        return llmHealth.label
    }

    /// Secondary line under the thinking-service headline.
    var thinkingServiceSubtitle: String {
        if isHydratingAfterLink {
            return "Mission data is loading. Chat opens when that’s done."
        }
        if isRemoteTurnInFlight, llmHealth == .unknown {
            return "Status waits until Chat finishes — the link is up."
        }
        if routingMode == "phoenix" {
            if let routed = lastRoutedDisplayName, !routed.isEmpty {
                return "Auto-select · last used \(routed)"
            }
            return "Picks a thinking service based on your message"
        }
        if let status = thinkingStatus, !status.model.isEmpty {
            return status.healthMessage.isEmpty
                ? "Using \(thinkingServiceHeadline)"
                : status.healthMessage
        }
        switch llmHealth {
        case .healthy:
            return "Your Sovereign can answer messages."
        case .unknown:
            return isCryptoChatReady
                ? "Link is up. Thinking status has not come back yet."
                : "Checking with your Sovereign…"
        default:
            return "Your Sovereign may not be able to reply right now."
        }
    }

    private var activeThinkingDisplayName: String? {
        if let routed = lastRoutedDisplayName, !routed.isEmpty {
            return routed
        }
        if let catalog = remoteCatalog,
           let activeID = catalog.activeConnectorId,
           let row = catalog.allConnectors.first(where: { $0.id == activeID }) {
            return row.displayName
        }
        if let status = thinkingStatus, !status.model.isEmpty {
            return RemoteModelCatalog.displayName(provider: status.provider, model: status.model)
                ?? humanReadableModelName(status.model)
        }
        return nil
    }

    func friendlyRemoteError(_ error: Error) -> String {
        if let relayError = error as? RelayTransport.RelayError {
            return relayError.errorDescription ?? relayError.localizedDescription
        }
        if let connectionError = error as? ConnectionError {
            return connectionError.localizedDescription
        }
        if let nwError = error as? NWError {
            return friendlyConnectionError(nwError)
        }
        let ns = error as NSError
        if ns.domain == "Network.NWError" || ns.domain.contains("NWError") {
            // POSIX 53 = ECONNABORTED — peer/OS aborted a still-"linked" socket.
            if ns.code == Int(POSIXErrorCode.ECONNABORTED.rawValue) {
                return "Your Sovereign closed the connection. Tap Find my Sovereign and link again."
            }
            if ns.code == Int(POSIXErrorCode.ECONNRESET.rawValue) {
                return "The link to your Sovereign was reset. Tap Find my Sovereign and link again."
            }
        }
        return error.localizedDescription
    }

    private static func isDroppedSocket(_ error: Error) -> Bool {
        if let connectionError = error as? ConnectionError {
            switch connectionError {
            case .connectionClosed, .messageTooLarge, .invalidResponse:
                return true
            default:
                break
            }
        }
        if let nwError = error as? NWError {
            if case .posix(.ECONNABORTED) = nwError { return true }
            if case .posix(.ECONNRESET) = nwError { return true }
        }
        let ns = error as NSError
        if ns.domain == "Network.NWError" || ns.domain.contains("NWError") {
            return ns.code == Int(POSIXErrorCode.ECONNABORTED.rawValue)
                || ns.code == Int(POSIXErrorCode.ECONNRESET.rawValue)
        }
        return false
    }

    /// Clear mid-turn UI so a reconnect never leaves a half-shown approval stuck.
    private func abortInFlightTurn(clearApproval: Bool) {
        turnActivityHint = nil
        streamingAssistantText = ""
        streamTtftMarked = false
        sendStartedAt = nil
        isRemoteTurnInFlight = false
        if clearApproval {
            pendingToolApproval = nil
        }
    }

    /// Lock Chat immediately after KX so keepalive/thinking cannot beat mission load.
    @discardableResult
    func beginPostLinkHydration() -> Int {
        if isHydratingAfterLink { return linkHydrationGeneration }
        linkHydrationGeneration += 1
        isHydratingAfterLink = true
        didHydrateAfterLink = false
        hydrationFetchStarted = false
        return linkHydrationGeneration
    }

    /// One caller may run the mission RPCs for this link.
    func claimHydrationFetch() -> Int? {
        guard isHydratingAfterLink, !didHydrateAfterLink, !hydrationFetchStarted else { return nil }
        hydrationFetchStarted = true
        return linkHydrationGeneration
    }

    /// Unlock Chat after mission hydrate (success or fail). No-op if the link dropped.
    func endPostLinkHydration(generation: Int) {
        guard generation == linkHydrationGeneration else { return }
        isHydratingAfterLink = false
        didHydrateAfterLink = true
        hydrationFetchStarted = false
    }

    private func resetPostLinkHydration() {
        linkHydrationGeneration += 1
        isHydratingAfterLink = false
        didHydrateAfterLink = false
        hydrationFetchStarted = false
    }

    /// User tapped Stop — drop the wedged receive so Chat can send again.
    func cancelInFlightChat() {
        abortInFlightTurn(clearApproval: true)
        lastLLMError = nil
        poisonPipelineAndReconnect()
    }

    private func recordSpeedSample(_ ms: Double, into samples: inout [Double]) {
        guard ms.isFinite, ms >= 0 else { return }
        samples.append(ms)
        if samples.count > maxSpeedSamples {
            samples.removeFirst(samples.count - maxSpeedSamples)
        }
    }

    /// Paste into `python -m centurion_cli.remote_relay_speed --away --rtt …` (soak, no PII).
    func speedSoakExportText(away: Bool = true) -> String {
        func join(_ values: [Double]) -> String {
            values.map { String(format: "%.0f", $0) }.joined(separator: ",")
        }
        var parts: [String] = ["python -m centurion_cli.remote_relay_speed"]
        if away { parts.append("--away") }
        if !rttSamplesMs.isEmpty {
            parts.append("--rtt \(join(rttSamplesMs))")
        }
        if !ttftSamplesMs.isEmpty {
            parts.append("--ttft \(join(ttftSamplesMs))")
        }
        if away, !coldConnectSamplesMs.isEmpty {
            parts.append("--cold \(join(coldConnectSamplesMs))")
        }
        let cmd = parts.joined(separator: " ")
        var lines = [
            cmd,
            "",
            "last_rtt_ms=\(lastTransportRttMs.map { String(format: "%.0f", $0) } ?? "n/a")",
            "last_ttft_overhead_ms=\(lastTtftOverheadMs.map { String(format: "%.0f", $0) } ?? "n/a")",
            "last_cold_connect_ms=\(lastColdConnectMs.map { String(format: "%.0f", $0) } ?? "n/a")",
            "last_approval_appear_ms=\(lastApprovalAppearMs.map { String(format: "%.0f", $0) } ?? "n/a")",
            "samples_rtt=\(rttSamplesMs.count) ttft=\(ttftSamplesMs.count) cold=\(coldConnectSamplesMs.count) approval=\(approvalAppearSamplesMs.count)",
        ]
        if !approvalAppearSamplesMs.isEmpty {
            lines.append("approval_appear_ms=\(join(approvalAppearSamplesMs))")
        }
        return lines.joined(separator: "\n")
    }

    /// Load the built-in model list and merge live routing + active model from the Mac.
    /// When the live catalog RPC fails, do **not** force “Needs access” on every row —
    /// infer configured key families from the host thinking status.
    func loadFallbackThinkingCatalog() async -> RemoteModelCatalog {
        thinkingCatalogUsedFallback = true
        let catalog = bundledCatalogFromKnownStatus()
        remoteCatalog = catalog
        Task { [weak self] in
            guard let self else { return }
            await self.refreshThinkingStatus()
            await self.refreshRoutingMode()
            self.remoteCatalog = self.bundledCatalogFromKnownStatus()
        }
        return catalog
    }

    private func bundledCatalogFromKnownStatus() -> RemoteModelCatalog {
        let bundled = RemoteModelCatalog.bundled()
        var configuredKeyEnvs = Set<String>()
        var activeID: String?

        if let status = thinkingStatus {
            let provider = status.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let model = status.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !provider.isEmpty {
                let matches = bundled.allConnectors.filter { row in
                    row.provider.lowercased() == provider
                        || row.provider.lowercased().hasPrefix(provider)
                        || provider.hasPrefix(row.provider.lowercased())
                }
                for row in matches {
                    configuredKeyEnvs.insert(row.keyEnv)
                }
                activeID = matches.first { $0.model.lowercased() == model }?.id
                    ?? matches.first?.id
            }
        }

        if configuredKeyEnvs.isEmpty, let previous = remoteCatalog {
            activeID = activeID ?? previous.activeConnectorId
            for row in previous.allConnectors where row.configured {
                configuredKeyEnvs.insert(row.keyEnv)
            }
        }

        return RemoteModelCatalog.bundled(
            activeConnectorId: activeID,
            routingMode: routingMode,
            configuredKeyEnvs: configuredKeyEnvs
        )
    }

    private func humanReadableModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func restoreLastThinkingSetup() async -> ProviderSwitchResult {
        do {
            let payload = try await invokeRemote(action: "provider_restore")
            let ok = payload["ok"] as? Bool ?? false
            let result = payload["result"] as? [String: Any] ?? [:]
            let message = (payload["message"] as? String)
                ?? (result["message"] as? String)
                ?? (ok ? "Restored your last working setup." : "No saved setup to restore.")
            if ok {
                await refreshThinkingStatus()
            }
            return ProviderSwitchResult(
                ok: ok,
                message: message,
                provider: result["provider"] as? String ?? "",
                model: result["model"] as? String ?? ""
            )
        } catch let error as ConnectionError {
            return ProviderSwitchResult(ok: false, message: error.localizedDescription, provider: "", model: "")
        } catch {
            return ProviderSwitchResult(ok: false, message: error.localizedDescription, provider: "", model: "")
        }
    }

    func requestSupportBundle() async -> SupportBundleResult {
        do {
            let payload = try await invokeRemote(action: "support_bundle")
            return SupportBundleResult(
                ok: payload["ok"] as? Bool ?? false,
                code: payload["code"] as? String ?? "",
                summary: payload["summary"] as? String ?? "",
                thinkingHealth: payload["thinking_health"] as? String ?? "",
                message: payload["message"] as? String ?? "Could not create a support code."
            )
        } catch let error as ConnectionError {
            return SupportBundleResult(ok: false, code: "", summary: "", thinkingHealth: "", message: error.localizedDescription)
        } catch {
            return SupportBundleResult(ok: false, code: "", summary: "", thinkingHealth: "", message: error.localizedDescription)
        }
    }

    func runHealthCheck() async -> HealthCheckResult {
        do {
            let payload = try await invokeRemote(action: "health_check")
            let snapshot = payload["snapshot"] as? [String: Any] ?? [:]
            return HealthCheckResult(
                ok: payload["ok"] as? Bool ?? false,
                summary: payload["summary"] as? String ?? "",
                thinkingHealth: payload["thinking_health"] as? String ?? "",
                issueCount: snapshot["issue_count"] as? Int ?? 0
            )
        } catch let error as ConnectionError {
            return HealthCheckResult(ok: false, summary: error.localizedDescription, thinkingHealth: "", issueCount: 0)
        } catch {
            return HealthCheckResult(ok: false, summary: error.localizedDescription, thinkingHealth: "", issueCount: 0)
        }
    }

    func autoFixThinking() async -> AutoFixResult {
        do {
            let payload = try await invokeRemote(action: "support_auto_fix")
            let ok = payload["ok"] as? Bool ?? false
            if ok {
                await refreshThinkingStatus()
            }
            return AutoFixResult(
                ok: ok,
                message: payload["message"] as? String ?? "",
                thinkingHealth: payload["thinking_health"] as? String ?? "",
                restored: payload["restored"] as? Bool ?? false
            )
        } catch let error as ConnectionError {
            return AutoFixResult(ok: false, message: error.localizedDescription, thinkingHealth: "", restored: false)
        } catch {
            return AutoFixResult(ok: false, message: error.localizedDescription, thinkingHealth: "", restored: false)
        }
    }

    func fetchSwarmSnapshot() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "swarm_snapshot")
        return payload["snapshot"] as? [String: Any] ?? [:]
    }

    /// Join a friend collaboration on this Centurion (Mission Control credentials).
    @discardableResult
    func connectSwarm(
        token: String,
        installId: String,
        projectId: String
    ) async throws -> String {
        let payload = try await invokeRemote(
            action: "swarm_connect",
            extra: [
                "token": token,
                "install_id": installId,
                "project_id": projectId,
            ]
        )
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not connect collaboration."
            )
        }
        return payload["message"] as? String
            ?? "Mission Control connected."
    }

    /// Invite another Centurion owner onto the current swarm project.
    @discardableResult
    func inviteSwarmFriend(customerId: String, projectId: String? = nil) async throws -> String {
        var extra: [String: Any] = ["invited_customer_id": customerId]
        if let projectId, !projectId.isEmpty {
            extra["project_id"] = projectId
        }
        let payload = try await invokeRemote(action: "swarm_invite", extra: extra)
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not send invite."
            )
        }
        return payload["message"] as? String
            ?? "Invite sent."
    }

    /// Resolve a Collaboration Signal on the Brain (Needs your choice → continue).
    @discardableResult
    func resolveSwarmSignal(signalId: String, choiceNote: String = "") async throws -> [String: Any] {
        var extra: [String: Any] = ["signal_id": signalId]
        if !choiceNote.isEmpty {
            extra["choice_note"] = choiceNote
        }
        let payload = try await invokeRemote(action: "swarm_resolve_signal", extra: extra)
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not record your choice."
            )
        }
        return payload["result"] as? [String: Any] ?? payload
    }

    /// Start a collaboration board on this Sovereign (LAN / local Brain).
    @discardableResult
    func createSwarmBoard(
        name: String,
        objective: String = "",
        missionId: String? = nil
    ) async throws -> [String: Any] {
        var extra: [String: Any] = [
            "name": name,
            "objective": objective,
        ]
        if let missionId, !missionId.isEmpty {
            extra["mission_id"] = missionId
        }
        let payload = try await invokeRemote(action: "swarm_create_board", extra: extra)
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not start collaboration."
            )
        }
        return payload
    }

    /// List Centurion profiles for Form collaboration pickers.
    func listProfiles() async throws -> [[String: Any]] {
        let payload = try await invokeRemote(action: "profiles_list")
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not list worker profiles."
            )
        }
        return payload["profiles"] as? [[String: Any]] ?? []
    }

    /// Form a local Kanban swarm (workers + verifier + synthesizer) that can dispatch.
    @discardableResult
    func createLocalSwarm(
        goal: String,
        workers: [[String: Any]],
        verifier: String,
        synthesizer: String,
        name: String = "",
        missionId: String? = nil
    ) async throws -> [String: Any] {
        var         extra: [String: Any] = [
            "goal": goal,
            "workers": workers,
            "verifier_assignee": verifier,
            "synthesizer_assignee": synthesizer,
            // Gateway dispatcher picks up ready workers. Inline dispatch can hang
            // the phone/Brain with no feedback.
            "dispatch": false,
        ]
        if !name.isEmpty {
            extra["name"] = name
        }
        if let missionId, !missionId.isEmpty {
            extra["mission_id"] = missionId
        }
        let payload = try await invokeRemote(action: "swarm_create", extra: extra)
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not form collaboration."
            )
        }
        return payload
    }

    func fetchBeneficiarySnapshot() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "beneficiary_snapshot")
        return payload["snapshot"] as? [String: Any] ?? [:]
    }

    func fetchOversight() async throws -> [String: Any] {
        try await invokeRemote(action: "oversight_get")
    }

    func fetchMemoryHorizon() async throws -> [String: Any] {
        try await invokeRemote(action: "memory_horizon_snapshot")
    }

    // MARK: - Plans

    func fetchPlans(status: String = "all") async throws -> [PlanArtifact] {
        let payload = try await invokeRemote(
            action: "plans_list",
            extra: ["status": status]
        )
        guard payload["ok"] as? Bool ?? false else {
            throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not load plans.")
        }
        let raw = payload["plans"] as? [[String: Any]] ?? []
        return raw.compactMap(PlanArtifact.decode(from:))
    }

    func putPlan(_ plan: PlanArtifact) async throws -> PlanArtifact? {
        let payload = try await invokeRemote(
            action: "plan_put",
            extra: ["plan": plan.hostPayload]
        )
        guard payload["ok"] as? Bool ?? false else {
            throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not save plan.")
        }
        if let dict = payload["plan"] as? [String: Any] {
            return PlanArtifact.decode(from: dict)
        }
        return nil
    }

    func decidePlan(
        planId: String,
        choice: String,
        note: String? = nil,
        reviewerCustomerId: String? = nil
    ) async throws -> PlanArtifact? {
        var extra: [String: Any] = [
            "plan_id": planId,
            "choice": choice,
        ]
        if let note, !note.isEmpty { extra["note"] = note }
        if let reviewerCustomerId, !reviewerCustomerId.isEmpty {
            extra["reviewer_customer_id"] = reviewerCustomerId
        }
        let payload = try await invokeRemote(action: "plan_decide", extra: extra)
        guard payload["ok"] as? Bool ?? false else {
            throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not record decision.")
        }
        if let dict = payload["plan"] as? [String: Any] {
            return PlanArtifact.decode(from: dict)
        }
        return nil
    }

    func sharePlan(
        planId: String,
        reviewerCustomerId: String,
        role: String = "observer"
    ) async throws -> PlanArtifact? {
        let payload = try await invokeRemote(
            action: "plan_share",
            extra: [
                "plan_id": planId,
                "reviewer_customer_id": reviewerCustomerId,
                "role": role,
            ]
        )
        guard payload["ok"] as? Bool ?? false else {
            throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not share plan.")
        }
        if let dict = payload["plan"] as? [String: Any] {
            return PlanArtifact.decode(from: dict)
        }
        return nil
    }

    func fetchPlanTemplates() async throws -> [PlanTemplate] {
        let payload = try await invokeRemote(action: "plan_templates_list")
        guard payload["ok"] as? Bool ?? false else {
            throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not load templates.")
        }
        let raw = payload["templates"] as? [[String: Any]] ?? []
        return raw.compactMap(PlanTemplate.decode(from:))
    }

    func instantiatePlanTemplate(templateId: String) async throws -> PlanArtifact? {
        let payload = try await invokeRemote(
            action: "plan_template_instantiate",
            extra: ["template_id": templateId]
        )
        guard payload["ok"] as? Bool ?? false else {
            throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not create plan from template.")
        }
        if let dict = payload["plan"] as? [String: Any] {
            return PlanArtifact.decode(from: dict)
        }
        return nil
    }

    func putOversight(
        _ oversight: [String: Any],
        applyLevelPreset: Bool = true
    ) async throws -> [String: Any] {
        let payload = try await invokeRemote(
            action: "oversight_put",
            extra: [
                "oversight": oversight,
                "apply_level_preset": applyLevelPreset,
            ]
        )
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not save oversight preferences."
            )
        }
        return payload
    }

    func fetchSoul() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "soul_get")
        return payload["soul"] as? [String: Any] ?? [:]
    }

    func putSoul(_ fields: [String: Any]) async throws -> [String: Any] {
        let payload = try await invokeRemote(
            action: "soul_put",
            extra: ["soul": fields]
        )
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not save your Sovereign's Soul."
            )
        }
        return payload["soul"] as? [String: Any] ?? [:]
    }

    func fetchMission() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "mission_get")
        return payload["mission"] as? [String: Any] ?? [:]
    }

    func putMission(_ fields: [String: Any]) async throws -> [String: Any] {
        let payload = try await invokeRemote(
            action: "mission_put",
            extra: ["mission": fields]
        )
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String ?? "Could not save your Life Mission."
            )
        }
        return payload["mission"] as? [String: Any] ?? [:]
    }

    /// Offline Life Missions — Crypto Chat `life_call` → Brain `life_*` bridge actions.
    @discardableResult
    func invokeLife(_ call: String, extra: [String: Any] = [:]) async throws -> [String: Any] {
        var body = extra
        body["call"] = call
        let payload = try await invokeRemote(action: "life_call", extra: body)
        if let ok = payload["ok"] as? Bool, !ok {
            throw ConnectionError.serverRejected(
                payload["message"] as? String
                    ?? ((payload["result"] as? [String: Any])?["message"] as? String)
                    ?? "Life Missions request failed."
            )
        }
        if let result = payload["result"] as? [String: Any] {
            return result
        }
        return payload
    }

    func fetchLifeStack() async throws -> [String: Any] {
        try await invokeLife("life_stack_get")
    }

    func fetchLifeSubjects() async throws -> [[String: Any]] {
        let r = try await invokeLife("life_subjects_list")
        return r["subjects"] as? [[String: Any]] ?? []
    }

    func fetchLifeSnapshot(since: String? = nil) async throws -> [String: Any] {
        var extra: [String: Any] = [:]
        if let since { extra["since"] = since }
        let r = try await invokeLife("life_snapshot", extra: extra)
        return r["snapshot"] as? [String: Any] ?? r
    }

    func resolveLifeDecision(decisionId: UUID, chosen: String = "Proceed") async throws {
        _ = try await invokeLife(
            "life_decision_resolve",
            extra: [
                "decision_id": decisionId.uuidString.lowercased(),
                "chosen": chosen,
            ]
        )
    }

    func injectLifeContext(
        message: String,
        missionId: String? = nil,
        targetId: String? = nil,
        subjectId: String? = nil
    ) async throws -> [String: Any] {
        var extra: [String: Any] = ["message": message]
        if let missionId { extra["mission_id"] = missionId }
        if let targetId { extra["target_id"] = targetId }
        if let subjectId { extra["subject_id"] = subjectId }
        return try await invokeLife("life_context_inject", extra: extra)
    }

    func setFamilyBeneficiary(firstName: String) async throws -> [String: Any] {
        let payload = try await invokeRemote(
            action: "beneficiary_set_family_member",
            extra: ["first_name": firstName]
        )
        if let snapshot = payload["snapshot"] as? [String: Any] {
            return snapshot
        }
        throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not save beneficiary.")
    }

    func submitColleagueReferral(
        name: String,
        email: String,
        phone: String,
        nonFamilyAttested: Bool
    ) async throws -> [String: Any] {
        let payload = try await invokeRemote(
            action: "beneficiary_submit_colleague",
            extra: [
                "name": name,
                "email": email,
                "phone": phone,
                "non_family_attested": nonFamilyAttested,
            ]
        )
        if let snapshot = payload["snapshot"] as? [String: Any] {
            return snapshot
        }
        throw ConnectionError.serverRejected(payload["message"] as? String ?? "Could not submit referral.")
    }

    func fetchRemoteModelCatalog() async -> RemoteModelCatalog {
        if isPipeBusyForSideTraffic {
            return remoteCatalog ?? bundledCatalogFromKnownStatus()
        }
        do {
            let payload = try await invokeRemote(action: "remote_model_catalog")
            guard let catalogData = payload["catalog"] as? [String: Any] else {
                return await loadFallbackThinkingCatalog()
            }
            let data = try JSONSerialization.data(withJSONObject: catalogData)
            let catalog = try JSONDecoder().decode(RemoteModelCatalog.self, from: data)
            remoteCatalog = catalog
            routingMode = catalog.routingMode
            thinkingCatalogUsedFallback = false
            return catalog
        } catch {
            return await loadFallbackThinkingCatalog()
        }
    }

    func applyRemoteModel(connectorId: String) async -> ProviderSwitchResult {
        do {
            let payload = try await invokeRemote(
                action: "remote_model_apply",
                extra: ["connector_id": connectorId]
            )
            let ok = payload["ok"] as? Bool ?? false
            let result = payload["result"] as? [String: Any] ?? [:]
            if let mode = payload["routing_mode"] as? String {
                routingMode = mode
            }
            if ok {
                await refreshThinkingStatus()
                _ = await fetchRemoteModelCatalog()
            }
            return ProviderSwitchResult(
                ok: ok,
                message: (result["message"] as? String) ?? (ok ? "Thinking service updated." : "Could not switch."),
                provider: result["provider"] as? String ?? "",
                model: result["model"] as? String ?? ""
            )
        } catch let error as ConnectionError {
            return ProviderSwitchResult(ok: false, message: error.localizedDescription, provider: "", model: "")
        } catch {
            return ProviderSwitchResult(ok: false, message: error.localizedDescription, provider: "", model: "")
        }
    }

    func saveRemoteAPIKey(connectorId: String, key: String) async -> ProviderSwitchResult {
        do {
            let payload = try await invokeRemote(
                action: "remote_model_save_key",
                extra: ["connector_id": connectorId, "key": key]
            )
            let ok = payload["ok"] as? Bool ?? false
            let result = payload["result"] as? [String: Any] ?? [:]
            if ok {
                _ = await fetchRemoteModelCatalog()
            }
            return ProviderSwitchResult(
                ok: ok,
                message: (result["message"] as? String) ?? (payload["message"] as? String) ?? "Could not save key.",
                provider: "",
                model: ""
            )
        } catch let error as ConnectionError {
            return ProviderSwitchResult(ok: false, message: error.localizedDescription, provider: "", model: "")
        } catch {
            return ProviderSwitchResult(ok: false, message: error.localizedDescription, provider: "", model: "")
        }
    }

    func setRoutingMode(_ mode: String) async -> Bool {
        do {
            let payload = try await invokeRemote(
                action: "remote_routing_mode",
                extra: ["mode": mode]
            )
            let ok = payload["ok"] as? Bool ?? false
            if let routing = payload["routing_mode"] as? String {
                routingMode = routing
            }
            return ok
        } catch {
            return false
        }
    }

    private func invokeRemote(
        action: String,
        extra: [String: Any] = [:],
        timeoutSeconds: TimeInterval = 90
    ) async throws -> [String: Any] {
        guard currentSessionKey != nil, isCryptoChatReady else {
            throw ConnectionError.notConnected
        }

        let requestID = UUID()
        var body: [String: Any] = [
            "type": action,
            "id": requestID.uuidString,
        ]
        for (key, value) in extra {
            body[key] = value
        }
        let plaintext = try JSONSerialization.data(withJSONObject: body)

        let responseData: Data
        do {
            responseData = try await withTimeout(seconds: timeoutSeconds) {
                try await self.exchangeEncrypted(plaintext: plaintext)
            }
        } catch is TimeoutError {
            if isRemoteTurnInFlight {
                throw ConnectionError.serverRejected(
                    "Chat is still waiting on your Centurion. Try this again when Chat finishes."
                )
            }
            if isHydratingAfterLink {
                throw ConnectionError.serverRejected(
                    "Mission data is still loading. Chat will open when that’s done."
                )
            }
            poisonPipelineAndReconnect()
            throw ConnectionError.serverRejected(
                "Your Sovereign took too long to respond. Reconnecting…"
            )
        } catch {
            if Self.isDroppedSocket(error) {
                poisonPipelineAndReconnect()
            }
            throw error
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let responseType = json["type"] as? String else {
            throw ConnectionError.invalidResponse
        }

        let expectedResponses: [String: String] = [
            "provider_status_response": "provider_status",
            "provider_options_response": "provider_options",
            "provider_validate_response": "provider_validate",
            "provider_apply_response": "provider_apply",
            "provider_restore_response": "provider_restore",
            "health_check_response": "health_check",
            "support_bundle_response": "support_bundle",
            "support_auto_fix_response": "support_auto_fix",
            "swarm_snapshot_response": "swarm_snapshot",
            "swarm_connect_response": "swarm_connect",
            "swarm_invite_response": "swarm_invite",
            "swarm_resolve_signal_response": "swarm_resolve_signal",
            "swarm_create_board_response": "swarm_create_board",
            "swarm_create_response": "swarm_create",
            "profiles_list_response": "profiles_list",
            "beneficiary_snapshot_response": "beneficiary_snapshot",
            "beneficiary_set_family_member_response": "beneficiary_set_family_member",
            "beneficiary_submit_colleague_response": "beneficiary_submit_colleague",
            "remote_model_catalog_response": "remote_model_catalog",
            "remote_model_apply_response": "remote_model_apply",
            "remote_model_save_key_response": "remote_model_save_key",
            "remote_routing_mode_response": "remote_routing_mode",
            "oversight_get_response": "oversight_get",
            "oversight_put_response": "oversight_put",
            "soul_get_response": "soul_get",
            "soul_put_response": "soul_put",
            "mission_get_response": "mission_get",
            "mission_put_response": "mission_put",
            "life_call_response": "life_call",
            "memory_horizon_snapshot_response": "memory_horizon_snapshot",
            "plans_list_response": "plans_list",
            "plan_get_response": "plan_get",
            "plan_put_response": "plan_put",
            "plan_decide_response": "plan_decide",
            "plan_share_response": "plan_share",
            "plan_comment_response": "plan_comment",
            "plan_templates_list_response": "plan_templates_list",
            "plan_template_instantiate_response": "plan_template_instantiate",
            "plan_save_template_response": "plan_save_template",
            "gateway_status_response": "gateway_status",
            "gateway_lifecycle_response": "gateway_start",
            "gateway_platform_set_response": "gateway_platform_set",
            "session_list_response": "session_list",
            "session_new_response": "session_new",
            "session_resume_response": "session_resume",
            "session_history_response": "session_history",
            "approval_respond_response": "approval_respond",
            "remote_relay_status_response": "remote_relay_status",
            "remote_relay_enable_response": "remote_relay_enable",
            "remote_relay_disable_response": "remote_relay_disable",
            "settings_snapshot_response": "settings_snapshot",
            "tool_env_get_response": "tool_env_get",
            "tool_env_set_response": "tool_env_set",
            "license_status_response": "license_status",
            "license_activate_response": "license_activate",
            "license_redeem_response": "license_redeem",
            "tools_skills_snapshot_response": "tools_skills_snapshot",
            "fleet_status_response": "fleet_status",
            "fleet_ping_response": "fleet_ping",
            "plugin_list_response": "plugin_list",
            "ops_glance_response": "ops_glance",
            "telegram_import_preview_response": "telegram_import_preview",
            "telegram_import_bundle_response": "telegram_import_bundle",
        ]

        if let expected = expectedResponses[responseType], expected == action {
            return json
        }
        // Allow `<action>_response` for any bridge action (life_* via life_call already mapped).
        if responseType == "\(action)_response" {
            return json
        }
        // Lifecycle start/stop/restart share one response type.
        if responseType == "gateway_lifecycle_response",
           ["gateway_start", "gateway_stop", "gateway_restart"].contains(action) {
            return json
        }

        if responseType == "error" {
            throw ConnectionError.serverRejected(json["message"] as? String ?? "Request failed.")
        }
        throw ConnectionError.invalidResponse
    }

    // MARK: - Private

    private func startConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run {
                guard let self, self.connectionState == .connecting else { return }
                self.failConnection(
                    "The connection timed out. Confirm both devices are on the same Wi‑Fi and Local Network access is enabled for this app in Settings."
                )
            }
        }
    }

    private func clearConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

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
                    } else if self.connectionState == .connecting {
                        self.failConnection(self.friendlyConnectionError(error))
                    } else {
                        self.connectionState = .error(self.friendlyConnectionError(error))
                    }
                case .cancelled:
                    guard self.connection === newConnection else { return }
                    if self.connectionState == .connected {
                        self.handleConnectionLoss("Your Sovereign closed the connection")
                    } else if case .awaitingApproval = self.connectionState {
                        // Pairing challenge intentionally closed the socket — keep waiting UI.
                        break
                    } else if self.connectionState == .connecting {
                        self.connectionState = .disconnected
                    }
                default:
                    break
                }
            }
        }
    }

    private func handleConnectionLoss(_ message: String) {
        abortInFlightTurn(clearApproval: true)
        resetPostLinkHydration()
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        pendingDevice = nil
        currentSessionKey = nil
        activeConnectionTarget = nil
        markDiscoveredDevicesDisconnected()
        connectionState = .error(message)
    }

    /// A timed-out receive does not cancel NWConnection.receive — drop the
    /// socket so later RPCs (chat, catalog) are not queued behind a dead frame.
    private func poisonPipelineAndReconnect() {
        abortInFlightTurn(clearApproval: true)
        resetPostLinkHydration()
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        currentSessionKey = nil
        reconnect()
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
                    "This Sovereign was reset. Remove its saved trust in Settings, then connect again."
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

        try await RemoteFrameIO.sendData(publicKey, over: connection)
        let data = try await RemoteFrameIO.receiveExactly(33, over: connection)
        guard data.count == 33, data[0] == 0x01 else {
            throw ConnectionError.invalidResponse
        }

        let serverPublicKey = Data(data.dropFirst())
        let sessionKey = try SessionKey.exchange(
            theirPublicKey: serverPublicKey,
            mySecretKey: identityKey.secretKey,
            myPublicKey: identityKey.publicKey
        )
        let statusFrame = try await RemoteFrameIO.receiveFrame(
            over: connection,
            maximumFrameSize: maximumFrameSize
        )
        let statusData = try secureChannel.decrypt(statusFrame, using: sessionKey)
        var status = try JSONDecoder().decode(RemoteEnvelope.self, from: statusData)

        if status.type == "pair_required" {
            let token = pendingPairingToken ?? RemotePairingTokenStore.load()
            guard let token, !token.isEmpty else {
                throw ConnectionError.serverRejected(
                    "Your Centurion needs a pairing code. Paste the code from Remote pairing on your computer."
                )
            }
            let pairRequest = RemoteEnvelope(type: "pair", token: token)
            let pairPlain = try JSONEncoder().encode(pairRequest)
            let pairResponseData = try await remoteIO.exchange(
                connection: connection,
                secureChannel: secureChannel,
                sessionKey: sessionKey,
                maximumFrameSize: maximumFrameSize,
                plaintext: pairPlain
            )
            status = try JSONDecoder().decode(RemoteEnvelope.self, from: pairResponseData)
            if status.type == "pair_rejected" {
                throw ConnectionError.serverRejected(
                    status.message ?? "That pairing code could not be verified."
                )
            }
            if status.type == "error" {
                throw ConnectionError.serverRejected(
                    status.message ?? "That pairing code could not be verified."
                )
            }
        }

        if status.type == "error" {
            if status.code == "PAIRING_APPROVAL_REQUIRED" {
                clearConnectionTimeout()
                await MainActor.run {
                    // Set awaiting-approval before cancelling so the socket teardown
                    // handler does not briefly flash "Not linked".
                    self.currentSessionKey = nil
                    self.activeConnectionTarget = nil
                    self.connectionState = .awaitingApproval(
                        status.message
                            ?? "Approve this iPhone on your Sovereign computer, then wait — we will retry automatically."
                    )
                    self.connection?.cancel()
                    self.connection = nil
                    self.startApprovalRetryLoop()
                }
                return
            }
            throw ConnectionError.serverRejected(
                status.message ?? "Approve this iPhone on your Sovereign, then try again."
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

        stopApprovalRetryLoop()
        currentSessionKey = sessionKey
        clearConnectionTimeout()
        if let pendingDevice {
            let resolvedIP = resolvedRemoteIP(from: connection)
                ?? pendingDevice.ipAddress.nilIfEmpty
            let linked = pendingDevice.asConnected(
                publicKey: serverPublicKey,
                hostname: pendingDevice.hostname.nilIfEmpty,
                port: pendingDevice.port > 0 ? pendingDevice.port : 9119,
                ipAddress: resolvedIP,
                connectionMethod: pendingDevice.connectionMethod
            )
            connectedDevice = linked
            persistLinkedDevice(linked)
            markDiscoveredDeviceConnected(pendingDevice.id)
            allowLanFallback = true
            recoveryPrefersPrimary = false
        }
        connectionState = .connected
        activeConnectionTarget = nil
        beginPostLinkHydration()
        // Keep Bonjour browsing alive while linked — cancelling the browser can drop
        // NWConnections that were opened via a Bonjour service endpoint.
        startKeepalive()
    }

    private func handleDeviceRevoked(_ message: String) {
        resetPostLinkHydration()
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
                if self.isPipeBusyForSideTraffic { continue }
                do {
                    try await self.sendPing()
                } catch {
                    await MainActor.run {
                        if self.connectionState == .connected {
                            self.handleConnectionLoss(
                                "Your Sovereign closed the connection"
                            )
                        }
                    }
                    return
                }
            }
        }
    }

    private func sendPing() async throws {
        guard currentSessionKey != nil, isCryptoChatReady else {
            throw ConnectionError.notConnected
        }

        let request = RemoteEnvelope(type: "ping")
        let plaintext = try JSONEncoder().encode(request)
        let pingStarted = Date()

        let responseData: Data
        do {
            responseData = try await withTimeout(seconds: 15) {
                try await self.exchangeEncrypted(plaintext: plaintext)
            }
        } catch is TimeoutError {
            poisonPipelineAndReconnect()
            throw ConnectionError.serverRejected(
                "Your Sovereign took too long to respond. Reconnecting…"
            )
        }
        lastTransportRttMs = Date().timeIntervalSince(pingStarted) * 1000
        if let ms = lastTransportRttMs {
            recordSpeedSample(ms, into: &rttSamplesMs)
        }
        let response = try JSONDecoder().decode(RemoteEnvelope.self, from: responseData)
        if response.type == "error", response.code == "DEVICE_REVOKED" {
            handleDeviceRevoked(
                response.message
                    ?? "This iPhone is no longer approved on your Sovereign."
            )
            throw ConnectionError.serverRejected(
                response.message
                    ?? "This iPhone is no longer approved on your Sovereign."
            )
        }
        guard response.type == "pong" else {
            throw ConnectionError.invalidResponse
        }
    }

    private func failConnection(_ message: String) {
        clearConnectionTimeout()
        resetPostLinkHydration()
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        markDiscoveredDevicesDisconnected()
        activeConnectionTarget = nil

        let remoteRecovery = """
        Couldn’t reach your Centurion remotely. Make sure this brain is reachable \
        away from home (secure tunnel or firewall), then tap Reconnect. On the same Wi‑Fi, \
        use Find my Sovereign.
        """

        // If remote/Tailscale failed, try LAN once before surfacing an error.
        if allowLanFallback,
           pendingDevice?.isRemotePath == true || pendingDevice?.isTailscalePath == true {
            allowLanFallback = false
            if let lan = loadLastLanDevice()
                ?? discoveredDevices.first(where: { !$0.isTailscalePath && !$0.isRemotePath })
                ?? discoveredDevices.first {
                recoveryPrefersPrimary = true
                pendingDevice = lan
                connect(to: lan, stopApprovalLoop: false)
                return
            }
            recoveryPrefersPrimary = false
            connectionState = .error(
                pendingDevice?.isRemotePath == true ? remoteRecovery : """
                Tailscale could not reach your Sovereign. Turn on Tailscale on this iPhone \
                and on your Sovereign, then tap Reconnect. If you are at home without Tailscale, \
                use Find my Sovereign on Wi‑Fi.
                """
            )
            return
        }

        if recoveryPrefersPrimary {
            recoveryPrefersPrimary = false
            connectionState = .error(
                loadLastRemoteDevice() != nil ? remoteRecovery : """
                Tailscale could not reach your Sovereign. Turn on Tailscale on this iPhone \
                and on your Sovereign, then tap Reconnect. If you are at home without Tailscale, \
                use Find my Sovereign on Wi‑Fi.
                """
            )
            return
        }

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

    private func friendlyConnectionError(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            return "This Sovereign is visible but is not accepting connections yet."
        case .posix(.ETIMEDOUT):
            return "The connection timed out. Check that both devices are on the same network."
        case .posix(.ECONNABORTED), .posix(.ECONNRESET):
            return "Your Sovereign closed the connection. Tap Find my Sovereign and link again."
        default:
            return "Your Sovereign could not be reached. Please try again."
        }
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

/// Serializes encrypted frame traffic so chat and keepalive cannot race on one socket.
private actor RemoteIOPipeline {
    func exchange(
        connection: NWConnection,
        secureChannel: SecureChannel,
        sessionKey: SessionKey,
        maximumFrameSize: Int,
        plaintext: Data,
        onPush: (([String: Any]) async -> Void)? = nil
    ) async throws -> Data {
        let encrypted = try secureChannel.encrypt(plaintext, using: sessionKey)
        try await RemoteFrameIO.sendFrame(
            encrypted,
            over: connection,
            maximumFrameSize: maximumFrameSize
        )
        while true {
            let responseFrame = try await RemoteFrameIO.receiveFrame(
                over: connection,
                maximumFrameSize: maximumFrameSize
            )
            let decrypted = try secureChannel.decrypt(responseFrame, using: sessionKey)
            if let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any],
               let type = json["type"] as? String {
                if type == "approval_request"
                    || type == "activity"
                    || type == "tool_progress"
                    || type == "status"
                    || type == "stream_delta"
                    || type == "partial" {
                    if let onPush {
                        await onPush(json)
                    }
                    continue
                }
            }
            return decrypted
        }
    }
}

private enum RemoteFrameIO {
    static func sendData(_ data: Data, over connection: NWConnection) async throws {
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

    static func sendFrame(
        _ payload: Data,
        over connection: NWConnection,
        maximumFrameSize: Int
    ) async throws {
        guard payload.count <= maximumFrameSize else {
            throw ConnectionError.messageTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        try await sendData(frame, over: connection)
    }

    static func receiveFrame(
        over connection: NWConnection,
        maximumFrameSize: Int
    ) async throws -> Data {
        let header = try await receiveExactly(4, over: connection)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= maximumFrameSize else {
            throw ConnectionError.messageTooLarge
        }
        return try await receiveExactly(Int(length), over: connection)
    }

    static func receiveExactly(_ count: Int, over connection: NWConnection) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk = try await receiveChunk(maxLength: remaining, over: connection)
            result.append(chunk)
        }
        return result
    }

    private static func receiveChunk(
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

    private static func receiveChunkContinuation(
        maxLength: Int,
        over connection: NWConnection,
        continuation: CheckedContinuation<Data, Error>
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) {
            data, _, isComplete, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, !data.isEmpty {
                continuation.resume(returning: data)
            } else if isComplete {
                continuation.resume(throwing: ConnectionError.connectionClosed)
            } else {
                receiveChunkContinuation(
                    maxLength: maxLength,
                    over: connection,
                    continuation: continuation
                )
            }
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
    let recovered: Bool?
    let routedDisplayName: String?
    let ok: Bool?
    let status: [String: AnyCodable]?
    let options: [String: AnyCodable]?
    let result: [String: AnyCodable]?
    let restored: Bool?
    let token: String?

    enum CodingKeys: String, CodingKey {
        case type, id, text, code, message, retryable, recovered, ok, status, options, result, restored, token
        case routedDisplayName = "routed_display_name"
    }

    var payload: [String: Any]? {
        if let status {
            return ["status": status.mapValues(\.value), "ok": true]
        }
        if let options {
            return ["options": options.mapValues(\.value), "ok": true]
        }
        if let result {
            var dict: [String: Any] = ["result": result.mapValues(\.value)]
            dict["ok"] = ok ?? true
            if let restored {
                dict["restored"] = restored
            }
            if let message {
                dict["message"] = message
            }
            return dict
        }
        return nil
    }

    init(type: String, id: UUID? = nil, text: String? = nil, token: String? = nil) {
        self.type = type
        self.id = id
        self.text = text
        code = nil
        message = nil
        retryable = nil
        recovered = nil
        routedDisplayName = nil
        ok = nil
        status = nil
        options = nil
        result = nil
        restored = nil
        self.token = token
    }
}

private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encodeNil()
        }
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

struct PendingToolApproval: Equatable, Identifiable {
    var id: String { approvalId.isEmpty ? sessionKey : approvalId }
    let approvalId: String
    let sessionKey: String
    let command: String
    let description: String
    let patternKey: String?
    let choices: [String]
}

enum ConnectionError: Error, LocalizedError {
    case notConnected
    case encryptionFailed
    case connectionClosed
    case invalidResponse
    case messageTooLarge
    case hydrating
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to any Sovereign"
        case .encryptionFailed: return "Message encryption failed"
        case .connectionClosed: return "Your Sovereign closed the connection"
        case .invalidResponse: return "Your Sovereign sent an invalid response"
        case .messageTooLarge:
            return "Your Sovereign sent a response that was too large. Restart centurion-remote on your Mac, then try again."
        case .hydrating:
            return "Loading mission data. Please wait — Chat opens when that’s done."
        case .serverRejected(let message): return message
        }
    }
}
