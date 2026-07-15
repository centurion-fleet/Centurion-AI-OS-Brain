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
    @Published var llmHealth: LLMHealthState = .unknown
    @Published var thinkingStatus: ThinkingServiceStatus?
    @Published var lastLLMError: (message: String, code: String?, retryable: Bool)?
    @Published var remoteCatalog: RemoteModelCatalog?
    @Published var routingMode: String = "manual"
    @Published var lastRoutedDisplayName: String?
    /// True when the model list came from the on-device fallback instead of the Centurion.
    @Published private(set) var thinkingCatalogUsedFallback = false
    /// Display name of the Centurion being linked (shown during pairing).
    @Published private(set) var activeConnectionTarget: String?
    /// SHA256 fingerprint of this iPhone’s identity key (for host `approve`).
    @Published private(set) var clientFingerprint: String?

    /// Live session is up and messages are secretboxed.
    var isChannelEncrypted: Bool {
        connectionState == .connected && currentSessionKey != nil
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
    private let remoteIO = RemoteIOPipeline()
    private let maximumFrameSize = 8 * 1024 * 1024
    private let handshakeTimeoutSeconds: UInt64 = 15
    private static let lastDeviceKey = "centurion.remote.lastDevice"

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
        do {
            let identity = try IdentityKey.loadOrCreate()
            identityKey = identity
            clientFingerprint = identity.fingerprint
        } catch {
            // Identity loads again in startDiscovery / connect paths.
        }
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

    /// Reconnect without cancelling an active approval poll (used by the auto-retry loop).
    private func reconnectPending(stopApprovalLoop: Bool) {
        if stopApprovalLoop {
            stopApprovalRetryLoop()
        }
        if let pendingDevice {
            connect(to: pendingDevice, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let saved = loadLastDevice() {
            connect(to: saved, stopApprovalLoop: stopApprovalLoop)
            return
        }
        if let device = discoveredDevices.first {
            connect(to: device, stopApprovalLoop: stopApprovalLoop)
            return
        }
        startDiscovery()
    }

    /// After splash / on enter foreground: rediscover and join the last trusted Centurion.
    func attemptAutoReconnect() {
        guard connectionState == .disconnected || isErrorState else { return }
        guard let saved = loadLastDevice() else { return }
        pendingDevice = saved
        startDiscovery()
        // Give Bonjour a moment, then connect to saved or matching discovery row.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard self.connectionState == .discovering
                    || self.connectionState == .disconnected
                    || self.isErrorState else { return }
            if let match = self.discoveredDevices.first(where: {
                $0.serviceName == saved.serviceName
                    || (!$0.hostname.isEmpty && $0.hostname == saved.hostname)
                    || (!$0.ipAddress.isEmpty && $0.ipAddress == saved.ipAddress)
            }) {
                self.connect(to: match)
            } else {
                self.connect(to: saved)
            }
        }
    }

    private var isErrorState: Bool {
        if case .error = connectionState { return true }
        return false
    }

    /// Manual Tailscale / IP fallback when Bonjour cannot see the brain.
    func connect(host: String, port: Int = 9119, name: String = "Centurion") {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            connectionState = .error("Enter the Centurion’s hostname or IP address.")
            return
        }
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
            connectionMethod: trimmed.contains("ts.net") || trimmed.contains("tailscale")
                ? .tailscale
                : .lan,
            lastSeen: Date()
        )
        connect(to: device)
    }

    /// Use the Bonjour service endpoint when available — that matches how discovery
    /// found the device. Fall back to hostname/IP only when service metadata is missing.
    private func connectionEndpoint(for device: CenturionDevice) -> NWEndpoint {
        let port = NWEndpoint.Port(rawValue: UInt16(device.port))
            ?? NWEndpoint.Port(integerLiteral: 9119)

        if let name = device.serviceName,
           let type = device.serviceType,
           let domain = device.serviceDomain {
            return .service(name: name, type: type, domain: domain, interface: nil)
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

        return .hostPort(host: NWEndpoint.Host("localhost"), port: port)
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
        clearLastDevice()
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
            let message = "Your Centurion is taking too long to respond. Try again in a moment."
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
                        ?? "This iPhone is no longer approved on your Centurion."
                )
                throw ConnectionError.serverRejected(
                    response.message
                        ?? "This iPhone is no longer approved on your Centurion."
                )
            }
            let message = response.message ?? "Your Centurion could not complete that request."
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

    /// User-facing name for the active LLM (not the Centurion device name).
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
            return "Your Centurion can answer messages."
        case .unknown:
            return "Checking with your Centurion…"
        default:
            return "Your Centurion may not be able to reply right now."
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

    func fetchBeneficiarySnapshot() async throws -> [String: Any] {
        let payload = try await invokeRemote(action: "beneficiary_snapshot")
        return payload["snapshot"] as? [String: Any] ?? [:]
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
        timeoutSeconds: UInt64 = 30
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
            "beneficiary_snapshot_response": "beneficiary_snapshot",
            "beneficiary_set_family_member_response": "beneficiary_set_family_member",
            "beneficiary_submit_colleague_response": "beneficiary_submit_colleague",
            "remote_model_catalog_response": "remote_model_catalog",
            "remote_model_apply_response": "remote_model_apply",
            "remote_model_save_key_response": "remote_model_save_key",
            "remote_routing_mode_response": "remote_routing_mode",
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
                    self.connection?.cancel()
                    self.connection = nil
                    self.currentSessionKey = nil
                    self.activeConnectionTarget = nil
                    // Keep pendingDevice so Try Again / auto-retry can reconnect.
                    self.connectionState = .awaitingApproval(
                        status.message
                            ?? "Approve this iPhone on your Centurion computer, then wait — we will retry automatically."
                    )
                    self.startApprovalRetryLoop()
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

        stopApprovalRetryLoop()
        currentSessionKey = sessionKey
        clearConnectionTimeout()
        if let pendingDevice {
            let linked = pendingDevice.asConnected(
                publicKey: serverPublicKey,
                hostname: pendingDevice.hostname.nilIfEmpty,
                port: pendingDevice.port > 0 ? pendingDevice.port : 9119
            )
            connectedDevice = linked
            persistLastDevice(linked)
            markDiscoveredDeviceConnected(pendingDevice.id)
        }
        connectionState = .connected
        activeConnectionTarget = nil
        bonjourDiscoverer.stopDiscovery()
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
        clearConnectionTimeout()
        keepaliveTask?.cancel()
        keepaliveTask = nil
        connection?.cancel()
        connection = nil
        connectedDevice = nil
        currentSessionKey = nil
        markDiscoveredDevicesDisconnected()
        activeConnectionTarget = nil
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
        case .notConnected: return "Not connected to any Centurion"
        case .encryptionFailed: return "Message encryption failed"
        case .connectionClosed: return "Your Centurion closed the connection"
        case .invalidResponse: return "Your Centurion sent an invalid response"
        case .messageTooLarge:
            return "Your Centurion sent a response that was too large. Restart centurion-remote on your Mac, then try again."
        case .serverRejected(let message): return message
        }
    }
}
