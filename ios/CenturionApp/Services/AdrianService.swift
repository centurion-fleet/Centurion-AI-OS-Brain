import Foundation

/// Talks to Adrian — the online presence of Sovereign's creator; caring expert guidance when online.
@MainActor
final class AdrianService: ObservableObject {
    @Published private(set) var messages: [AdrianMessage] = []
    @Published private(set) var suggestedActions: [AdrianSuggestedAction] = []
    @Published private(set) var isSending = false
    @Published var lastError: String?

    private let installIDKey = "centurion.adrian.install_id"
    private let legacyInstallIDKey = "centurion.herald.install_id"
    private let hasAcceptedPrivacyKey = "centurion.adrian.privacy_accepted"
    private let legacyPrivacyKey = "centurion.herald.privacy_accepted"
    private let session = URLSession.shared

    var hasAcceptedPrivacy: Bool {
        UserDefaults.standard.bool(forKey: hasAcceptedPrivacyKey)
            || UserDefaults.standard.bool(forKey: legacyPrivacyKey)
    }

    func acceptPrivacy() {
        UserDefaults.standard.set(true, forKey: hasAcceptedPrivacyKey)
    }

    var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey), existing.count >= 8 {
            return existing
        }
        if let legacy = UserDefaults.standard.string(forKey: legacyInstallIDKey), legacy.count >= 8 {
            UserDefaults.standard.set(legacy, forKey: installIDKey)
            return legacy
        }
        let fresh = "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(fresh, forKey: installIDKey)
        return fresh
    }

    func seedWelcomeIfNeeded() {
        guard messages.isEmpty else { return }
        messages = [
            AdrianMessage(
                role: .adrian,
                content: """
                I'm Adrian — your guide to Sovereign. Ask me anything: getting set up, \
                linking your iPhone, privacy, or fixing a problem. I'll walk you through it, one \
                clear step at a time.

                My answers come from the same Help Center articles at help.1human1ai.com — \
                update those once, and both the website and this chat stay in sync.

                I work over the internet, separate from your Sovereign on your Sovereign brain. \
                I see only what helps — link status, thinking health, and a short mission summary \
                if you've set one. Never your chat history or secrets.

                What would you like help with?
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
        messages.append(AdrianMessage(role: .user, content: trimmed))
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
                messages.append(AdrianMessage(role: .adrian, content: response.reply))
                suggestedActions = response.suggestedActions
            } else {
                lastError = response.message.isEmpty ? "Adrian couldn't respond right now." : response.message
            }
        } catch {
            lastError = "Couldn't reach Adrian. Check your internet connection and try again."
        }
    }

    private func buildContext(
        connectionManager: ConnectionManager,
        missionStore: MissionStore,
        supportCode: String
    ) -> AdrianChatContext {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let missionSummary: String
        if missionStore.hasMissionStatement {
            missionSummary = String(missionStore.mission.statement.prefix(400))
        } else {
            missionSummary = ""
        }
        return AdrianChatContext(
            appVersion: appVersion,
            connectionState: connectionManager.connectionState.adrianLabel,
            thinkingHealth: connectionManager.llmHealth.adrianLabel,
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
        let context: AdrianChatContext

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
        let suggestedActions: [AdrianSuggestedActionWire]
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
            suggestedActions = try container.decodeIfPresent([AdrianSuggestedActionWire].self, forKey: .suggestedActions) ?? []
            message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        }

        struct AdrianSuggestedActionWire: Decodable {
            let id: String
            let label: String
        }

        var actions: [AdrianSuggestedAction] {
            suggestedActions.map { AdrianSuggestedAction(id: $0.id, label: $0.label) }
        }
    }

    private func postChat(userMessage: String, context: AdrianChatContext) async throws -> (
        ok: Bool,
        reply: String,
        suggestedActions: [AdrianSuggestedAction],
        message: String
    ) {
        var wireMessages: [ChatPayload.WireMessage] = messages
            .filter { $0.role == .user || $0.role == .adrian }
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
        var request = URLRequest(url: AdrianConfig.baseURL.appendingPathComponent("api/v1/chat"))
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

private extension ConnectionManager.ConnectionState {
    var adrianLabel: String {
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
    var adrianLabel: String {
        switch self {
        case .unknown: return "unknown"
        case .healthy: return "working_normally"
        case .degraded: return "needs_attention"
        case .broken: return "needs_attention"
        }
    }
}
