import Foundation

/// Talks to Centurion Herald — cloud support guide, always available when online.
@MainActor
final class HeraldService: ObservableObject {
    @Published private(set) var messages: [HeraldMessage] = []
    @Published private(set) var suggestedActions: [HeraldSuggestedAction] = []
    @Published private(set) var isSending = false
    @Published var lastError: String?

    private let installIDKey = "centurion.herald.install_id"
    private let hasAcceptedPrivacyKey = "centurion.herald.privacy_accepted"
    private let session = URLSession.shared

    var hasAcceptedPrivacy: Bool {
        UserDefaults.standard.bool(forKey: hasAcceptedPrivacyKey)
    }

    func acceptPrivacy() {
        UserDefaults.standard.set(true, forKey: hasAcceptedPrivacyKey)
    }

    var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey), existing.count >= 8 {
            return existing
        }
        let fresh = "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(fresh, forKey: installIDKey)
        return fresh
    }

    func seedWelcomeIfNeeded() {
        guard messages.isEmpty else { return }
        messages = [
            HeraldMessage(
                role: .herald,
                content: """
                I'm Herald — Centurion's guide, here whenever you need help with this app.

                I work over the internet, separate from your Centurion on your computer, so I can \
                help even when you're not linked yet. Tell me what's in the way and we'll get you \
                back on mission.
                """
            ),
        ]
    }

    func send(
        _ text: String,
        connectionManager: ConnectionManager,
        missionStore: MissionStore,
        supportCode: String = ""
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        lastError = nil
        messages.append(HeraldMessage(role: .user, content: trimmed))
        isSending = true
        defer { isSending = false }

        let context = buildContext(
            connectionManager: connectionManager,
            missionStore: missionStore,
            supportCode: supportCode
        )

        do {
            let response = try await postChat(userMessage: trimmed, context: context)
            if response.ok {
                messages.append(HeraldMessage(role: .herald, content: response.reply))
                suggestedActions = response.suggestedActions
            } else {
                lastError = response.message.isEmpty ? "Herald couldn't respond right now." : response.message
            }
        } catch {
            lastError = "Couldn't reach Herald. Check your internet connection and try again."
        }
    }

    private func buildContext(
        connectionManager: ConnectionManager,
        missionStore: MissionStore,
        supportCode: String
    ) -> HeraldChatContext {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let missionSummary: String
        if missionStore.hasMissionStatement {
            missionSummary = String(missionStore.mission.statement.prefix(400))
        } else {
            missionSummary = ""
        }
        return HeraldChatContext(
            appVersion: appVersion,
            connectionState: connectionManager.connectionState.heraldLabel,
            thinkingHealth: connectionManager.llmHealth.heraldLabel,
            thinkingMessage: connectionManager.thinkingStatus?.healthMessage ?? connectionManager.llmHealth.label,
            hasMission: missionStore.hasMissionStatement,
            activeTargetCount: missionStore.activeTargets.count,
            missionSummary: missionSummary,
            supportCode: supportCode
        )
    }

    private struct ChatPayload: Encodable {
        let installId: String
        let messages: [WireMessage]
        let context: HeraldChatContext

        enum CodingKeys: String, CodingKey {
            case installId = "install_id"
            case messages
            case context
        }

        struct WireMessage: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ChatResponse: Decodable {
        let ok: Bool
        let reply: String
        let suggestedActions: [HeraldSuggestedActionWire]
        let message: String

        enum CodingKeys: String, CodingKey {
            case ok
            case reply
            case suggestedActions = "suggested_actions"
            case message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ok = try container.decode(Bool.self, forKey: .ok)
            reply = try container.decodeIfPresent(String.self, forKey: .reply) ?? ""
            suggestedActions = try container.decodeIfPresent([HeraldSuggestedActionWire].self, forKey: .suggestedActions) ?? []
            message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        }

        struct HeraldSuggestedActionWire: Decodable {
            let id: String
            let label: String
        }

        var actions: [HeraldSuggestedAction] {
            suggestedActions.map { HeraldSuggestedAction(id: $0.id, label: $0.label) }
        }
    }

    private func postChat(userMessage: String, context: HeraldChatContext) async throws -> (
        ok: Bool,
        reply: String,
        suggestedActions: [HeraldSuggestedAction],
        message: String
    ) {
        var wireMessages: [ChatPayload.WireMessage] = messages
            .filter { $0.role == .user || $0.role == .herald }
            .suffix(12)
            .map { msg in
                ChatPayload.WireMessage(
                    role: msg.role == .user ? "user" : "assistant",
                    content: msg.content
                )
            }
        if wireMessages.last?.role != "user" {
            wireMessages.append(ChatPayload.WireMessage(role: "user", content: userMessage))
        }

        let payload = ChatPayload(installId: installID, messages: wireMessages, context: context)
        var request = URLRequest(url: HeraldConfig.baseURL.appendingPathComponent("v1/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installID, forHTTPHeaderField: "X-Centurion-Install-ID")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 45

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        if http.statusCode >= 400 && !decoded.ok {
            return (false, "", [], decoded.message)
        }
        return (decoded.ok, decoded.reply, decoded.actions, decoded.message)
    }
}

// MARK: - Herald context labels

private extension ConnectionManager.ConnectionState {
    var heraldLabel: String {
        switch self {
        case .disconnected: return "disconnected"
        case .discovering: return "discovering"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .awaitingApproval: return "awaiting_approval"
        case .error: return "error"
        }
    }
}

private extension LLMHealthState {
    var heraldLabel: String {
        switch self {
        case .unknown: return "unknown"
        case .healthy: return "working_normally"
        case .degraded: return "needs_attention"
        case .broken: return "needs_attention"
        }
    }
}
