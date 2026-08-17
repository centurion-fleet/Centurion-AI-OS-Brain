import Foundation

/// Away-path coordinator: prefer LAN Crypto Chat; else RelayTransport over Supabase Realtime.
/// Does not replace LAN pairing — pair once at home, then enable Anywhere on the Brain.
@MainActor
final class RelayAwayClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    @Published private(set) var brainOnline = false
    /// Brain-published Realtime conn epoch (phone adopts before KX).
    @Published private(set) var brainConnEpoch: String?

    private let session = RelayTransport.Session()
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var refCounter = 0
    private var topic = ""
    private var receiveLoopActive = false

    /// Inbound reassembled ciphertext (or KX) waiting for ConnectionManager.
    private var inboundCipherQueue: [Inbound] = []
    private var inboundWaiters: [CheckedContinuation<Inbound, Error>] = []
    private var joinContinuation: CheckedContinuation<Void, Error>?

    enum Inbound {
        case kxServer(Data)
        case frame(Data)
    }

    /// Bundled Centurion cloud endpoints (same App Store binary for every customer).
    /// Overridable via UserDefaults for staging.
    enum Cloud {
        static let productionControlBase = "https://1human1ai.com"
        static let productionSupabaseURL = "https://ypbzwsjklvrxfknsvrfo.supabase.co"
        /// Public anon / publishable key (same class as NEXT_PUBLIC_SUPABASE_ANON_KEY).
        static let productionSupabaseAnonKey = "sb_publishable_T6Z_f-JaQv8fZz8j7YHPLA_P-Xk9vfU"

        static var supabaseURL: String {
            let stored = UserDefaults.standard.string(forKey: "centurion.remoteRelay.supabaseURL") ?? ""
            if !stored.isEmpty { return stored }
            return productionSupabaseURL
        }

        static var supabaseAnonKey: String {
            let stored = UserDefaults.standard.string(forKey: "centurion.remoteRelay.supabaseAnonKey") ?? ""
            if !stored.isEmpty { return stored }
            return productionSupabaseAnonKey
        }

        static var controlBaseURL: URL {
            if let raw = UserDefaults.standard.string(forKey: "centurion.remoteRelay.controlBase"),
               let url = URL(string: raw), !raw.isEmpty {
                return url
            }
            return URL(string: productionControlBase)!
        }
    }

    var transportSession: RelayTransport.Session { session }

    func configure(supabaseURL: String, anonKey: String, controlBase: String? = nil) {
        UserDefaults.standard.set(supabaseURL, forKey: "centurion.remoteRelay.supabaseURL")
        UserDefaults.standard.set(anonKey, forKey: "centurion.remoteRelay.supabaseAnonKey")
        if let controlBase, !controlBase.isEmpty {
            UserDefaults.standard.set(controlBase, forKey: "centurion.remoteRelay.controlBase")
        }
    }

    /// Poll Brain presence via the Vercel control plane when away.
    func refreshPresence(installId: String) async {
        guard !installId.isEmpty else {
            brainOnline = false
            brainConnEpoch = nil
            return
        }
        var comps = URLComponents(
            url: Cloud.controlBaseURL.appendingPathComponent("api/remote-relay/presence"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "install_id", value: installId)]
        guard let url = comps?.url else {
            brainOnline = false
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let ok = obj["ok"] as? Bool, ok == false {
                brainOnline = false
                lastError = (obj["error"] as? String) ?? (obj["message"] as? String)
                return
            }
            brainOnline = (obj["online"] as? Bool) ?? false
            brainConnEpoch = obj["conn_epoch"] as? String
            lastError = nil
        } catch {
            brainOnline = false
            lastError = error.localizedDescription
        }
    }

    /// Connect Realtime when LAN is unavailable and Brain is online on the relay.
    func connect(installId: String) async throws {
        let base = Cloud.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = Cloud.supabaseAnonKey
        guard !base.isEmpty, !key.isEmpty else {
            throw RelayTransport.RelayError.brainOffline
        }
        await refreshPresence(installId: installId)
        guard brainOnline else {
            throw RelayTransport.RelayError.brainOffline
        }

        disconnect(resetEpoch: true)
        // Align conn epoch with Brain before any KX (stale-conn checks).
        if let epoch = brainConnEpoch, !epoch.isEmpty {
            session.adoptConn(epoch)
        }
        let wsURL = try Self.websocketURL(supabaseURL: base, apiKey: key)
        topic = "realtime:brain:\(installId)"
        let urlSession = URLSession(configuration: .default)
        self.urlSession = urlSession
        let task = urlSession.webSocketTask(with: wsURL)
        webSocket = task
        task.resume()
        try await joinChannel(installId: installId)
        isConnected = true
        lastError = nil
        receiveLoopActive = true
        Task { await self.receiveLoop() }
    }

    func disconnect(resetEpoch: Bool = true) {
        receiveLoopActive = false
        failWaiters(RelayTransport.RelayError.staleConn)
        joinContinuation?.resume(throwing: CancellationError())
        joinContinuation = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        inboundCipherQueue.removeAll()
        if resetEpoch {
            _ = session.resetConnection()
        }
    }

    /// Publish opaque ciphertext as RelayTransport envelopes (after KX).
    func sendCiphertext(_ data: Data) async throws {
        guard isConnected else { throw RelayTransport.RelayError.staleConn }
        let envelopes = try session.outboundFrame(body: data)
        for env in envelopes {
            try await broadcast(env)
        }
    }

    func sendKx(_ data: Data, client: Bool) async throws {
        guard isConnected else { throw RelayTransport.RelayError.staleConn }
        let envelopes = session.outboundKx(body: data, client: client)
        for env in envelopes {
            try await broadcast(env)
        }
    }

    func markKxComplete() {
        session.markKxComplete()
    }

    /// Wait for the next reassembled inbound body (KX server or ciphertext frame).
    func waitForInbound(timeoutSeconds: TimeInterval) async throws -> Inbound {
        if let next = inboundCipherQueue.first {
            inboundCipherQueue.removeFirst()
            return next
        }
        return try await withThrowingTaskGroup(of: Inbound.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Inbound, Error>) in
                    Task { @MainActor in
                        self.inboundWaiters.append(cont)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
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

    // MARK: - Phoenix Realtime

    private static func websocketURL(supabaseURL: String, apiKey: String) throws -> URL {
        var ws = supabaseURL
        if ws.hasPrefix("https://") {
            ws = "wss://" + ws.dropFirst("https://".count)
        } else if ws.hasPrefix("http://") {
            ws = "ws://" + ws.dropFirst("http://".count)
        }
        var components = URLComponents(string: "\(ws)/realtime/v1/websocket")
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components?.url else {
            throw RelayTransport.RelayError.staleConn
        }
        return url
    }

    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    private func joinChannel(installId: String) async throws {
        let join: [String: Any] = [
            "topic": topic,
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["ack": false, "self": false],
                    "presence": ["key": installId],
                ],
            ],
            "ref": nextRef(),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        self.joinContinuation = cont
                    }
                }
            }
            group.addTask { @MainActor in
                try await self.sendJSON(join)
                // Soft wait: if no phx_reply in 5s, proceed (some proxies omit reply).
                try await Task.sleep(nanoseconds: 5_000_000_000)
                if let pending = self.joinContinuation {
                    self.joinContinuation = nil
                    pending.resume()
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func broadcast(_ env: RelayTransport.Envelope) async throws {
        let payload: [String: Any] = [
            "topic": topic,
            "event": "broadcast",
            "payload": [
                "type": "broadcast",
                "event": "centurion_frame",
                "payload": [
                    "v": env.v,
                    "conn": env.conn,
                    "id": env.id,
                    "kind": env.kind,
                    "chunk_i": env.chunk_i,
                    "chunk_n": env.chunk_n,
                    "body_b64": env.body_b64,
                ],
            ],
            "ref": nextRef(),
        ]
        try await sendJSON(payload)
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let socket = webSocket else { throw RelayTransport.RelayError.staleConn }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RelayTransport.RelayError.invalidChunk
        }
        try await socket.send(.string(text))
    }

    private func receiveLoop() async {
        while receiveLoopActive, let socket = webSocket {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handlePhoenixMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handlePhoenixMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                // Mid-turn reconnect: fail waiters with a retryable relay error (not a raw socket message).
                lastError = error.localizedDescription
                isConnected = false
                _ = session.resetConnection()
                failWaiters(RelayTransport.RelayError.turnInterrupted)
                receiveLoopActive = false
                break
            }
        }
    }

    private func handlePhoenixMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let event = json["event"] as? String ?? ""
        if event == "phx_reply" {
            let status = (json["payload"] as? [String: Any])?["status"] as? String
            if status == "ok", let pending = joinContinuation {
                joinContinuation = nil
                pending.resume()
            }
            return
        }
        if event == "phx_error" {
            lastError = "Realtime channel error"
            return
        }
        guard event == "broadcast" || event == "phx_broadcast",
              let payload = json["payload"] as? [String: Any] else {
            return
        }
        let inner: [String: Any]?
        if (payload["event"] as? String) == "centurion_frame" {
            inner = payload["payload"] as? [String: Any]
        } else {
            inner = payload
        }
        guard let inner,
              let env = try? decodeEnvelope(inner) else {
            return
        }
        do {
            guard let body = try session.ingest(env) else { return }
            let inbound: Inbound
            if env.kind == "kx_server" || env.kind == "kx_client" {
                inbound = .kxServer(body)
            } else {
                inbound = .frame(body)
            }
            deliver(inbound)
        } catch {
            lastError = error.localizedDescription
            if case RelayTransport.RelayError.staleConn = error {
                _ = session.resetConnection()
                isConnected = false
                // Stale conn epoch mid-turn ⇒ same class as reconnect: retryable, no half UI approval.
                failWaiters(RelayTransport.RelayError.turnInterrupted)
            }
        }
    }

    private func deliver(_ inbound: Inbound) {
        if let waiter = inboundWaiters.first {
            inboundWaiters.removeFirst()
            waiter.resume(returning: inbound)
        } else {
            inboundCipherQueue.append(inbound)
        }
    }

    private func failWaiters(_ error: Error) {
        let waiters = inboundWaiters
        inboundWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    private func decodeEnvelope(_ dict: [String: Any]) throws -> RelayTransport.Envelope {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(RelayTransport.Envelope.self, from: data)
    }
}

private struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        "Chat from anywhere timed out waiting for your Sovereign. Retry when the link is steady."
    }
}
