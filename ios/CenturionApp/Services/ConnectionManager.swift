import Foundation
import Network

/// Manages the encrypted connection between iPhone and Sovereign.
///
/// Connection priority (Tailscale-first for stability):
/// 1. Tailscale MagicDNS / Tailscale IP — preferred at home and away
/// 2. LAN (Bonjour / LAN IP) — only when Tailscale is unavailable
///
/// Encryption flow:
/// 1. Reach Centurion via Tailscale (or LAN fallback)
/// 2. Exchange X25519 public keys for key agreement
/// 3. Establish directional session keys
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

    /// Live session is up and messages are secretboxed.
    var isChannelEncrypted: Bool {
        connectionState == .connected && currentSessionKey != nil
    }

    /// "Tailscale" or "Wi‑Fi" when linked; empty otherwise.
    var linkPathBadge: String {
        guard connectionState == .connected,
              let device = connectedDevice ?? pendingDevice else { return "" }
        return device.isTailscalePath
            ? CenturionDevice.ConnectionMethod.tailscale.linkBadge
            : CenturionDevice.ConnectionMethod.lan.linkBadge
    }

    /// True when a previous Tailscale or LAN endpoint was saved for reconnect.
    var hasPersistedLink: Bool {
        loadLastDevice() != nil || loadLastLanDevice() != nil
    }

    private let bonjourDiscoverer = BonjourDiscoverer()
    private let secureChannel = SecureChannel()
    private var identityKey: IdentityKey?
    private var currentSessionKey: SessionKey?
    private var connection: NWConnection?
    private var pendingDevice: CenturionDevice?
    private var keepaliveTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var approvalRetryTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var pathDebounceTask: Task<Void, Never>?
    /// When a Tailscale attempt fails, allow one LAN fallback for this reconnect cycle.
    private var allowLanFallback = true
    /// After a Tailscale→LAN cascade, surface Tailscale-first recovery if LAN also fails.
    private var recoveryPrefersTailscale = false
    private let remoteIO = RemoteIOPipeline()
    private let maximumFrameSize = 8 * 1024 * 1024
    private let handshakeTimeoutSeconds: TimeInterval = 15
    private static let lastDeviceKey = "centurion.remote.lastDevice"
    private static let lastLanDeviceKey = "centurion.remote.lastLanDevice"

    private let chatTimeoutSeconds: TimeInterval = 180

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

    /// One-tap reconnect: Tailscale first, then LAN.
    func reconnect() {
        allowLanFallback = true
        recoveryPrefersTailscale = false
        reconnectWithPriority(stopApprovalLoop: true)
    }

    /// Reconnect without cancelling an active approval poll (used by the auto-retry loop).
    private func reconnectPending(stopApprovalLoop: Bool) {
        reconnectWithPriority(stopApprovalLoop: stopApprovalLoop)
    }

    /// Prefer Tailscale saved endpoint; LAN only if mesh is unavailable.
    private func reconnectWithPriority(stopApprovalLoop: Bool) {
        if stopApprovalLoop {
            stopApprovalRetryLoop()
        }

        // Keep Bonjour warm for LAN fallback inventory.
        if connectionState != .discovering {
            bonjourDiscoverer.startDiscovery()
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
        if let pending = pendingDevice {
            connect(to: pending, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let lan = loadLastLanDevice() {
            pendingDevice = lan
            connect(to: lan, stopApprovalLoop: stopApprovalLoop)
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

    /// After splash / on enter foreground: Tailscale first, Bonjour only as fallback.
    func attemptAutoReconnect() {
        guard connectionState == .disconnected || isErrorState else { return }
        guard loadLastDevice() != nil || loadLastLanDevice() != nil else { return }
        allowLanFallback = true
        reconnectWithPriority(stopApprovalLoop: true)
    }

    private var isErrorState: Bool {
        if case .error = connectionState { return true }
        return false
    }

    /// Manual Tailscale / IP connect. Tailscale hosts are tagged as the preferred path.
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

        // Prefer hostname for Tailscale MagicDNS so the mesh path stays stable.
        if device.isTailscalePath, !device.hostname.isEmpty {
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
        allowLanFallback = true
        recoveryPrefersTailscale = false
        connectionState = .disconnected
        markDiscoveredDevicesDisconnected()
    }

    /// Tears the socket down without wiping pairing context (approval retry).
    private func softTearDown(clearPending: Bool) {
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

    /// Persist Tailscale as primary when possible; keep a separate LAN fallback.
    private func persistLinkedDevice(_ linked: CenturionDevice) {
        if linked.isTailscalePath {
            persistLastDevice(linked)
        } else {
            persistLastLanDevice(linked)
            if let primary = loadLastDevice(), primary.isTailscalePath {
                // Keep MagicDNS / Tailscale as the preferred reconnect target.
            } else {
                persistLastDevice(linked)
            }
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

            // Prefer mesh whenever Tailscale is known — upgrade off LAN fallback.
            if self.connectionState == .connected,
               let current = self.connectedDevice, !current.isTailscalePath,
               let mesh = self.loadLastDevice(), mesh.isTailscalePath {
                self.allowLanFallback = true
                self.recoveryPrefersTailscale = false
                self.connect(to: mesh, stopApprovalLoop: true)
                return
            }

            guard self.connectionState == .disconnected || self.isErrorState else { return }
            guard self.loadLastDevice() != nil || self.loadLastLanDevice() != nil else { return }
            self.allowLanFallback = true
            self.recoveryPrefersTailscale = false
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

    func sendMessage(_ text: String) async throws -> String {
        guard let sessionKey = currentSessionKey,
              let connection = connection else {
            throw ConnectionError.notConnected
        }

        let requestID = UUID()
        let request = RemoteEnvelope(type: "chat", id: requestID, text: text)
        let plaintext = try JSONEncoder().encode(request)

        let responseData: Data
        do {
            responseData = try await withTimeout(seconds: chatTimeoutSeconds) {
                try await self.remoteIO.exchange(
                    connection: connection,
                    secureChannel: self.secureChannel,
                    sessionKey: sessionKey,
                    maximumFrameSize: self.maximumFrameSize,
                    plaintext: plaintext
                )
            }
        } catch is TimeoutError {
            let message = "Your Sovereign is taking too long to respond. Try again in a moment."
            lastLLMError = (message, "LLM_UNAVAILABLE", true)
            llmHealth = .broken(message, code: "LLM_UNAVAILABLE", retryable: true)
            throw ConnectionError.serverRejected(message)
        }
        let response = try JSONDecoder().decode(RemoteEnvelope.self, from: responseData)

        if response.type == "chat_response",
           response.id == requestID,
           let responseText = response.text {
            llmHealth = .healthy
            lastLLMError = nil
            if let routed = response.routedDisplayName, !routed.isEmpty {
                lastRoutedDisplayName = routed
            }
            if response.recovered == true {
                await refreshThinkingStatus()
            }
            return responseText
        }
        if response.type == "error" {
            if response.code == "DEVICE_REVOKED" {
                handleDeviceRevoked(
                    response.message
                        ?? "This iPhone is no longer approved on your Sovereign."
                )
                throw ConnectionError.serverRejected(
                    response.message
                        ?? "This iPhone is no longer approved on your Sovereign."
                )
            }
            let message = response.message ?? "Your Sovereign could not complete that request."
            let code = response.code
            let retryable = response.retryable ?? true
            lastLLMError = (message, code, retryable)
            llmHealth = .broken(message, code: code, retryable: retryable)
            throw ConnectionError.serverRejected(message)
        }
        throw ConnectionError.invalidResponse
    }

    func refreshThinkingStatus() async {
        guard connectionState == .connected else { return }
        do {
            let payload = try await invokeRemote(action: "provider_status")
            if let statusData = try? JSONSerialization.data(withJSONObject: payload["status"] ?? [:]),
               let status = try? JSONDecoder().decode(ThinkingServiceStatus.self, from: statusData) {
                thinkingStatus = status
                switch status.health {
                case "ok":
                    llmHealth = .healthy
                case "degraded":
                    llmHealth = .degraded(status.healthMessage)
                default:
                    llmHealth = .broken(status.healthMessage, code: nil, retryable: true)
                }
            }
        } catch {
            llmHealth = .unknown
        }
    }

    func refreshRoutingMode() async {
        guard connectionState == .connected else { return }
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
        if routingMode == "phoenix" {
            if let routed = lastRoutedDisplayName, !routed.isEmpty {
                return "Auto-select · last used \(routed)"
            }
            return "Picks an LLM based on your message"
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
            return "Checking with your Sovereign…"
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

    /// Load the built-in model list and merge live routing + active model from the Mac.
    func loadFallbackThinkingCatalog() async -> RemoteModelCatalog {
        thinkingCatalogUsedFallback = true
        await refreshThinkingStatus()
        await refreshRoutingMode()
        let activeID: String?
        if let status = thinkingStatus, !status.model.isEmpty {
            activeID = RemoteModelCatalog.connectorID(provider: status.provider, model: status.model)
        } else {
            activeID = remoteCatalog?.activeConnectorId
        }
        let catalog = RemoteModelCatalog.bundled(
            activeConnectorId: activeID,
            routingMode: routingMode
        )
        remoteCatalog = catalog
        return catalog
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
        timeoutSeconds: TimeInterval = 30
    ) async throws -> [String: Any] {
        guard let sessionKey = currentSessionKey,
              let connection = connection else {
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

        let responseData = try await withTimeout(seconds: timeoutSeconds) {
            try await self.remoteIO.exchange(
                connection: connection,
                secureChannel: self.secureChannel,
                sessionKey: sessionKey,
                maximumFrameSize: self.maximumFrameSize,
                plaintext: plaintext
            )
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
        ]

        if let expected = expectedResponses[responseType], expected == action {
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
        let status = try JSONDecoder().decode(RemoteEnvelope.self, from: statusData)
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
                ipAddress: resolvedIP
            )
            connectedDevice = linked
            persistLinkedDevice(linked)
            markDiscoveredDeviceConnected(pendingDevice.id)
            allowLanFallback = true
            recoveryPrefersTailscale = false
        }
        connectionState = .connected
        activeConnectionTarget = nil
        // Keep Bonjour browsing alive while linked — cancelling the browser can drop
        // NWConnections that were opened via a Bonjour service endpoint.
        startKeepalive()
        Task { await refreshThinkingStatus() }
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
        guard let sessionKey = currentSessionKey,
              let connection = connection else {
            throw ConnectionError.notConnected
        }

        let request = RemoteEnvelope(type: "ping")
        let plaintext = try JSONEncoder().encode(request)

        let responseData = try await withTimeout(seconds: 15) {
            try await self.remoteIO.exchange(
                connection: connection,
                secureChannel: self.secureChannel,
                sessionKey: sessionKey,
                maximumFrameSize: self.maximumFrameSize,
                plaintext: plaintext
            )
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
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        markDiscoveredDevicesDisconnected()
        activeConnectionTarget = nil

        let tailscaleRecovery = """
        Tailscale could not reach your Sovereign. Turn on Tailscale on this iPhone \
        and on your Sovereign, then tap Reconnect. If you are at home without Tailscale, \
        use Find my Sovereign on Wi‑Fi.
        """

        // Tailscale-first: if mesh failed, try LAN once before surfacing an error.
        if allowLanFallback, pendingDevice?.isTailscalePath == true {
            allowLanFallback = false
            if let lan = loadLastLanDevice()
                ?? discoveredDevices.first(where: { !$0.isTailscalePath })
                ?? discoveredDevices.first {
                recoveryPrefersTailscale = true
                pendingDevice = lan
                connect(to: lan, stopApprovalLoop: false)
                return
            }
            recoveryPrefersTailscale = false
            connectionState = .error(tailscaleRecovery)
            return
        }

        if recoveryPrefersTailscale {
            recoveryPrefersTailscale = false
            connectionState = .error(tailscaleRecovery)
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
            let result = try await group.next()!
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
        plaintext: Data
    ) async throws -> Data {
        let encrypted = try secureChannel.encrypt(plaintext, using: sessionKey)
        try await RemoteFrameIO.sendFrame(
            encrypted,
            over: connection,
            maximumFrameSize: maximumFrameSize
        )
        let responseFrame = try await RemoteFrameIO.receiveFrame(
            over: connection,
            maximumFrameSize: maximumFrameSize
        )
        return try secureChannel.decrypt(responseFrame, using: sessionKey)
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

    enum CodingKeys: String, CodingKey {
        case type, id, text, code, message, retryable, recovered, ok, status, options, result, restored
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

    init(type: String, id: UUID? = nil, text: String? = nil) {
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

enum ConnectionError: Error, LocalizedError {
    case notConnected
    case encryptionFailed
    case connectionClosed
    case invalidResponse
    case messageTooLarge
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to any Sovereign"
        case .encryptionFailed: return "Message encryption failed"
        case .connectionClosed: return "Your Sovereign closed the connection"
        case .invalidResponse: return "Your Sovereign sent an invalid response"
        case .messageTooLarge:
            return "Your Sovereign sent a response that was too large. Restart centurion-remote on your Mac, then try again."
        case .serverRejected(let message): return message
        }
    }
}
