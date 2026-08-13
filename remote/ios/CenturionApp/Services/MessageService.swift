import Foundation
import SwiftUI
import Combine

/// Unified message service — the single source of truth for ALL messages in the app.
///
/// Messages flow from any entry point (Pulse tab chat, direct Chat tab) into
/// a single chronological stream. They are grouped into conversations by their
/// mission context (program / target / task / standalone).
///
/// This is the architecture behind the insight:
/// "Comments aren't separate from chat — they ARE chat."
@MainActor
final class MessageService: ObservableObject {
    /// Every message in the app, in chronological order.
    /// This powers the Chat tab's unified stream.
    @Published var allMessages: [Message] = []

    /// Conversations derived from messages grouped by their context.
    /// Powers the Conversations side panel (☰).
    @Published var conversations: [Conversation] = []

    /// The currently visible conversation in ChatView
    @Published var currentConversation: Conversation?

    private let connectionManager: ConnectionManager
    private let dataMode: AppDataMode
    private var cancellables = Set<AnyCancellable>()

    init(connectionManager: ConnectionManager, dataMode: AppDataMode) {
        self.connectionManager = connectionManager
        self.dataMode = dataMode
    }

    /// Remove seeded preview conversations once a live Centurion link is active.
    /// Purges demo threads from disk without wiping live Crypto Chat history.
    func clearDemoData() {
        let hadDemoSession = UserDefaults.standard.bool(forKey: "centurion.chatDemoActive")
        allMessages = []
        conversations = []
        currentConversation = nil
        ConversationStore.shared.removeDemoContent(includeLegacyTitleSeeds: hadDemoSession)
        UserDefaults.standard.set(false, forKey: "centurion.chatDemoActive")
    }

    /// Restore a full multi-conversation snapshot (live Crypto Chat + imports).
    func applySnapshot(conversations: [Conversation], messages: [Message]) {
        self.conversations = conversations.sorted { $0.lastActive > $1.lastActive }
        self.allMessages = messages.sorted { $0.timestamp < $1.timestamp }
        self.currentConversation = self.conversations.first
    }

    /// Seed a Discuss thread from Home Pulse and bind a Brain host topic when linked.
    func seedDiscussContext(
        title: String,
        detail: String,
        topicKind: String = "decision",
        topicRef: [String: Any]? = nil
    ) -> Conversation {
        let kind = topicKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let context: ConversationContext
        switch kind {
        case "decision":
            context = .decision(id: UUID().uuidString, title: title)
        case "document":
            context = .document(id: UUID().uuidString, title: title, missionId: nil)
        case "mission":
            context = .mission(id: UUID().uuidString, name: title, subjectName: nil)
        case "horizon":
            context = .horizon(layer: title)
        default:
            context = .standalone(title: title)
        }
        var conversation = findOrCreateConversation(for: context)
        let existing = messages(for: conversation.id)
        if existing.isEmpty {
            let note = Message(
                conversationId: conversation.id,
                content: "Context for this Crypto Chat:\n\(detail)",
                role: .system
            )
            appendMessage(note)
        }
        if connectionManager.isCryptoChatReady, conversation.hostSessionId == nil {
            Task {
                do {
                    var ref = topicRef ?? ["title": title, "kind": kind]
                    if ref["title"] == nil { ref["title"] = title }
                    let hostId = try await connectionManager.createHostSession(
                        title: title,
                        topicKind: kind.isEmpty ? "generic" : kind,
                        topicRef: ref
                    )
                    if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                        conversations[idx].hostSessionId = hostId
                        persistIfLive()
                    }
                    // Align Brain Focus when Discuss opens a mission with an id.
                    if kind == "mission",
                       let mid = ref["mission_id"] as? String,
                       !mid.isEmpty {
                        var focusExtra: [String: Any] = ["mission_id": mid]
                        if let tid = ref["target_id"] as? String, !tid.isEmpty {
                            focusExtra["target_id"] = tid
                        }
                        _ = try? await connectionManager.invokeLife(
                            "life_focus_set",
                            extra: focusExtra
                        )
                    }
                } catch {
                    // Local Discuss still works; host topic binds on next send path.
                }
            }
        }
        currentConversation = conversation
        return conversation
    }

    /// Pull Brain SessionDB remote sessions into the Chat tray (host topics).
    /// Creates or updates local `Conversation` rows bound by `hostSessionId`.
    @discardableResult
    func syncHostTopicsFromBrain() async -> Int {
        guard connectionManager.isCryptoChatReady else { return 0 }
        do {
            let rows = try await connectionManager.listHostSessions(limit: 50)
            var merged = 0
            for row in rows {
                guard let hostId = row["id"] as? String, !hostId.isEmpty else { continue }
                let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = (title?.isEmpty == false) ? title! : "Topic"
                let topicKind = (row["topic_kind"] as? String) ?? ""
                let context = Self.context(forTopicKind: topicKind, title: display, topicRef: row["topic_ref"])

                if let idx = conversations.firstIndex(where: { $0.hostSessionId == hostId }) {
                    conversations[idx].context = context
                    if let last = row["last_active"] as? Double {
                        conversations[idx].lastActive = Date(timeIntervalSince1970: last)
                    }
                    merged += 1
                    continue
                }
                // Prefer matching an existing local thread with same title and no host id yet.
                if let idx = conversations.firstIndex(where: {
                    $0.hostSessionId == nil && $0.displayTitle.caseInsensitiveCompare(display) == .orderedSame
                }) {
                    conversations[idx].hostSessionId = hostId
                    conversations[idx].context = context
                    merged += 1
                    continue
                }
                var conv = Conversation(
                    id: UUID(),
                    context: context,
                    lastActive: Date(),
                    hostSessionId: hostId
                )
                if let last = row["last_active"] as? Double {
                    conv.lastActive = Date(timeIntervalSince1970: last)
                }
                conversations.insert(conv, at: 0)
                merged += 1
            }
            conversations.sort { $0.lastActive > $1.lastActive }
            ConversationStore.shared.save(conversations: conversations, messages: allMessages)
            return merged
        } catch {
            return 0
        }
    }

    /// Open a host-backed topic: resume Brain history when the local thread is empty.
    func openHostTopic(_ conversation: Conversation) async -> Conversation {
        currentConversation = conversation
        guard let hostId = conversation.hostSessionId,
              connectionManager.isCryptoChatReady else {
            return conversation
        }
        let existing = messages(for: conversation.id)
        guard existing.isEmpty || existing.allSatisfy({ $0.role == .system }) else {
            return conversation
        }
        do {
            let resumed = try await connectionManager.resumeHostSession(hostId)
            if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[idx].hostSessionId = resumed.sessionId
                if !resumed.title.isEmpty {
                    conversations[idx].context = Self.context(
                        forTopicKind: resumed.topicKind,
                        title: resumed.title,
                        topicRef: resumed.topicRef
                    )
                }
            }
            for raw in resumed.messages {
                let roleRaw = (raw["role"] as? String) ?? ""
                let content = (raw["content"] as? String) ?? ""
                guard !content.isEmpty else { continue }
                let role: Message.Role
                switch roleRaw {
                case "assistant": role = .centurion
                case "user": role = .user
                default: role = .system
                }
                // Skip duplicate system framing if we already seeded one.
                if role == .system, existing.contains(where: { $0.content == content }) {
                    continue
                }
                appendMessage(
                    Message(
                        conversationId: conversation.id,
                        content: content,
                        role: role
                    )
                )
            }
            if resumed.truncated {
                appendMessage(
                    Message(
                        conversationId: conversation.id,
                        content: "Showing recent messages only — full history is available on home Wi‑Fi.",
                        role: .system
                    )
                )
            }
            return conversations.first(where: { $0.id == conversation.id }) ?? conversation
        } catch {
            let text = connectionManager.friendlyRemoteError(error)
            appendMessage(
                Message(
                    conversationId: conversation.id,
                    content: text,
                    role: .system
                )
            )
            return conversation
        }
    }

    private static func context(forTopicKind kind: String, title: String, topicRef: Any?) -> ConversationContext {
        let ref = topicRef as? [String: Any]
        switch kind.lowercased() {
        case "plan":
            let id = uuidFromRef(ref, keys: ["plan_id", "id"]) ?? UUID()
            return .plan(id: id, title: title)
        case "mission":
            if let targetId = uuidFromRef(ref, keys: ["target_id"]),
               let missionId = uuidFromRef(ref, keys: ["mission_id", "id"]) {
                let targetTitle = (ref?["target_title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .missionTarget(
                    id: targetId,
                    name: (targetTitle?.isEmpty == false) ? targetTitle! : title,
                    missionId: missionId,
                    missionName: title,
                    subjectName: ref?["subject_name"] as? String
                )
            }
            let id = uuidFromRef(ref, keys: ["mission_id", "id"]) ?? UUID()
            return .mission(id: id, name: title, subjectName: ref?["subject_name"] as? String)
        case "commitment":
            let id = uuidFromRef(ref, keys: ["commitment_id", "id"]) ?? UUID()
            return .commitment(id: id, title: title)
        case "collab":
            let id = uuidFromRef(ref, keys: ["id", "board_id"]) ?? UUID()
            let boardId = (ref?["board_id"] as? String) ?? id.uuidString
            return .collab(id: id, name: title, boardId: boardId)
        case "document":
            return .document(
                id: uuidFromRef(ref, keys: ["id"]),
                title: title,
                missionId: uuidFromRef(ref, keys: ["mission_id"])
            )
        case "decision":
            let id = uuidFromRef(ref, keys: ["decision_id", "id"]) ?? UUID()
            return .decision(id: id, title: title)
        case "horizon":
            let layer = (ref?["layer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .horizon(layer: (layer?.isEmpty == false) ? layer! : title)
        default:
            return .standalone(title: title)
        }
    }

    /// Persist Discuss metadata on the Brain session once `hostSessionId` is known.
    func ensureHostTopicMetadata(for conversationId: UUID) async {
        guard connectionManager.isCryptoChatReady,
              let idx = conversations.firstIndex(where: { $0.id == conversationId }),
              let hostId = conversations[idx].hostSessionId,
              let kind = conversations[idx].context.hostTopicKind else {
            return
        }
        do {
            try await connectionManager.setHostSessionTopic(
                sessionId: hostId,
                topicKind: kind,
                topicRef: conversations[idx].context.hostTopicRef
            )
        } catch {
            // Non-fatal — chat still works; metadata backfills on next Discuss open.
        }
    }

    /// Start a fresh freeform host topic (separate Brain session).
    func startNewFreeformTopic(title: String = "New topic") async -> Conversation {
        let context = ConversationContext.standalone(title: title)
        var conversation = findOrCreateConversation(for: context)
        guard connectionManager.isCryptoChatReady else {
            currentConversation = conversation
            return conversation
        }
        do {
            let hostId = try await connectionManager.createHostSession(
                title: title,
                topicKind: "generic",
                topicRef: ["title": title, "kind": "topic"]
            )
            if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[idx].hostSessionId = hostId
                conversation = conversations[idx]
            }
            persistIfLive()
        } catch {
            // Local-only until first send sticks a host session.
        }
        currentConversation = conversation
        return conversation
    }

    /// Rename a host-backed topic on Brain SessionDB and locally.
    @discardableResult
    func renameHostTopic(_ conversation: Conversation, title: String) async -> Conversation {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            return conversation
        }
        if let hostId = conversations[idx].hostSessionId,
           connectionManager.isCryptoChatReady {
            do {
                let saved = try await connectionManager.renameHostSession(
                    sessionId: hostId,
                    title: trimmed
                )
                conversations[idx].context = .standalone(title: saved)
            } catch {
                conversations[idx].context = renamedContext(
                    conversations[idx].context,
                    title: trimmed
                )
            }
        } else {
            conversations[idx].context = renamedContext(
                conversations[idx].context,
                title: trimmed
            )
        }
        persistIfLive()
        return conversations[idx]
    }

    /// Delete a host-backed topic (Brain + local).
    func deleteHostTopic(_ conversation: Conversation) async {
        if let hostId = conversation.hostSessionId,
           connectionManager.isCryptoChatReady {
            try? await connectionManager.deleteHostSession(sessionId: hostId)
        }
        allMessages.removeAll { $0.conversationId == conversation.id }
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        persistIfLive()
    }

    private func renamedContext(_ context: ConversationContext, title: String) -> ConversationContext {
        switch context {
        case .plan(let id, _): return .plan(id: id, title: title)
        case .commitment(let id, _): return .commitment(id: id, title: title)
        case .collab(let id, _, let boardId): return .collab(id: id, name: title, boardId: boardId)
        case .document(let id, _, let missionId): return .document(id: id, title: title, missionId: missionId)
        case .decision(let id, _): return .decision(id: id, title: title)
        case .horizon: return .horizon(layer: title)
        case .mission(let id, _, let subject): return .mission(id: id, name: title, subjectName: subject)
        case .missionTarget(let id, _, let missionId, let missionName, let subject):
            return .missionTarget(
                id: id,
                name: title,
                missionId: missionId,
                missionName: missionName,
                subjectName: subject
            )
        case .program(let id, _): return .program(id: id, name: title)
        case .target(let id, _, let program): return .target(id: id, name: title, programName: program)
        case .task(let id, _, let target, let program):
            return .task(id: id, name: title, targetName: target, programName: program)
        case .standalone: return .standalone(title: title)
        }
    }

    private static func uuidFromRef(_ ref: [String: Any]?, keys: [String]) -> UUID? {
        guard let ref else { return nil }
        for key in keys {
            if let s = ref[key] as? String, let u = UUID(uuidString: s) { return u }
        }
        return nil
    }

    /// Open or resume the stable Discuss thread for a Plan (same conversation anytime).
    func seedPlanDiscuss(plan: PlanArtifact, kickoffNote: String? = nil) -> Conversation {
        let context = ConversationContext.plan(id: plan.id, title: plan.title)
        let conversation = findOrCreateConversation(for: context)
        // Keep title in sync if the plan was renamed.
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].context = context
        }
        let existing = messages(for: conversation.id)
        guard existing.isEmpty else { return conversation }
        let detail = kickoffNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let detail, !detail.isEmpty {
            body = "Context for this Crypto Chat about this plan:\n\(detail)\n\n\(plan.markdownContent)"
        } else {
            body = "Context for this Crypto Chat about this plan:\n\n\(plan.markdownContent)"
        }
        appendMessage(
            Message(
                conversationId: conversation.id,
                content: body,
                role: .system
            )
        )
        return conversation
    }

    /// Call after the view has appeared to seed demo conversations when offline.
    func seedInitialData() {
        guard dataMode.showsDemoContent, conversations.isEmpty else { return }
        seedSampleData()
    }

    /// Send a message in a conversation context. Returns the conversation used.
    /// When `proposeFirst` is true, the host is framed to draft a plan only and stop.
    func sendMessage(
        _ text: String,
        in context: ConversationContext,
        missionStore: MissionStore? = nil,
        planStore: PlanStore? = nil,
        proposeFirst: Bool = false
    ) async throws -> Conversation {
        guard connectionManager.isCryptoChatReady else {
            throw MessageError.notConnected
        }

        let conversation = findOrCreateConversation(for: context)

        let userMessage = Message(
            conversationId: conversation.id,
            content: text,
            role: .user
        )
        appendMessage(userMessage)

        let outboundBody: String
        var lifeInject: [String: Any]?
        if proposeFirst {
            outboundBody = ProposeFirstChat.frameOutbound(userText: text)
        } else if case .plan(let id, _) = context,
                  let planStore,
                  let plan = planStore.plan(id: id) {
            outboundBody = PlanDiscussChat.frameOutbound(userText: text, plan: plan)
        } else if case .commitment(let id, _) = context,
           let missionStore,
           let commitment = missionStore.commitment(with: id) {
            outboundBody = MissionCommitmentChat.frameOutbound(
                userText: text,
                commitment: commitment,
                mission: missionStore.mission
            )
            var view: [String: Any] = [
                "mission_id": missionStore.stack.primary?.id.uuidString
                    ?? missionStore.mission.id.uuidString,
                "target_id": id.uuidString,
            ]
            if let subjectId = missionStore.stack.primary?.subjectId?.uuidString {
                view["subject_id"] = subjectId
            }
            lifeInject = [
                "message": outboundBody,
                "current_view": view,
            ]
        } else if case .collab(_, let name, let boardId) = context {
            outboundBody = TopicDiscussChat.frameCollab(
                userText: text,
                name: name,
                boardId: boardId
            )
        } else if case .document(let id, let title, let missionId) = context {
            outboundBody = TopicDiscussChat.frameDocument(
                userText: text,
                title: title,
                documentId: id?.uuidString,
                missionId: missionId?.uuidString
            )
            lifeInject = TopicDiscussChat.lifeInject(userText: outboundBody, context: context)
        } else if case .decision(_, let title) = context {
            outboundBody = TopicDiscussChat.frameDecision(userText: text, title: title)
            lifeInject = TopicDiscussChat.lifeInject(userText: outboundBody, context: context)
        } else if case .horizon(let layer) = context {
            outboundBody = TopicDiscussChat.frameHorizon(userText: text, layer: layer)
        } else if case .mission = context {
            outboundBody = text
            lifeInject = TopicDiscussChat.lifeInject(userText: text, context: context)
        } else if case .missionTarget = context {
            outboundBody = text
            lifeInject = TopicDiscussChat.lifeInject(userText: text, context: context)
        } else {
            outboundBody = text
        }

        let outbound = frameWithConversationHistory(
            latestUserText: outboundBody,
            conversationID: conversation.id
        )

        let rawResult = try await connectionManager.sendMessage(
            outbound,
            sessionId: conversation.hostSessionId,
            lifeInject: lifeInject
        )
        let rawResponse = rawResult.text
        if let hostSessionId = rawResult.sessionId, !hostSessionId.isEmpty {
            if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[idx].hostSessionId = hostSessionId
                persistIfLive()
            }
            await ensureHostTopicMetadata(for: conversation.id)
        }

        var displayResponse = MissionCommitmentChat.displayText(strippingUpdateBlockFrom: rawResponse)
        displayResponse = PlanDiscussChat.displayText(strippingUpdateBlockFrom: displayResponse)
        displayResponse = ProposeFirstChat.displayText(strippingArtifactFrom: displayResponse)

        if displayResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MessageError.emptyResponse
        }

        if let missionStore,
           let payload = MissionCommitmentChat.parseUpdate(from: rawResponse) {
            missionStore.applyCommitmentUpdate(payload)
            syncConversationTitle(for: conversation.id, missionStore: missionStore)
        }

        if let planStore,
           let payload = PlanDiscussChat.parseUpdate(from: rawResponse),
           planStore.applyDiscussUpdate(payload) {
            syncPlanConversationTitle(for: conversation.id, planStore: planStore)
            if let planId = UUID(uuidString: payload.plan_id),
               let updated = planStore.plan(id: planId) {
                await planStore.upsertAndSync(updated, connectionManager: connectionManager)
            }
        }

        if proposeFirst, let planStore {
            let artifact = ProposeFirstChat.parseArtifact(from: rawResponse)
                ?? ProposeFirstChat.fallbackArtifact(from: displayResponse.isEmpty ? rawResponse : displayResponse, userRequest: text)
            await planStore.upsertAndSync(artifact, connectionManager: connectionManager)
            if displayResponse.isEmpty {
                displayResponse = "I've drafted a plan for your review on Home — open Plans, Needs your choice, or Documents when you're ready."
            } else if !displayResponse.localizedCaseInsensitiveContains("home")
                        && !displayResponse.localizedCaseInsensitiveContains("plan") {
                displayResponse += "\n\nYou can review this plan on Home under Plans, Needs your choice, or Documents."
            }
        }

        appendMessage(
            Message(
                conversationId: conversation.id,
                content: displayResponse.isEmpty ? rawResponse : displayResponse,
                role: .centurion
            )
        )
        return conversation
    }

    /// Prefix Brain life context onto outbound user text (cache-safe; never mutates system prompt).
    private func prependLifeContextIfAvailable(
        userText: String,
        missionId: String?,
        targetId: String?,
        subjectId: String?
    ) async -> String {
        guard connectionManager.isCryptoChatReady else { return userText }
        do {
            let payload = try await connectionManager.injectLifeContext(
                message: userText,
                missionId: missionId,
                targetId: targetId,
                subjectId: subjectId
            )
            let formatted = (payload["formatted_for_ai"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !formatted.isEmpty else { return userText }
            return """
            [Sovereign AI Remote — Mission context]
            \(formatted)

            User message:
            \(userText)
            """
        } catch {
            return userText
        }
    }

    /// Include recent local Crypto Chat turns so oneshot brain sessions keep continuity.
    private func frameWithConversationHistory(
        latestUserText: String,
        conversationID: UUID
    ) -> String {
        // Newest message is the user turn we just appended — history is everything before it.
        let prior = messages(for: conversationID).dropLast().suffix(10)
        guard !prior.isEmpty else { return latestUserText }

        var lines: [String] = [
            "Earlier turns in this Crypto Chat (for context only):",
        ]
        for message in prior where message.role != .system {
            let speaker: String
            switch message.role {
            case .user: speaker = "User"
            case .centurion: speaker = "Sovereign"
            case .system: continue
            }
            lines.append("\(speaker): \(message.content)")
        }
        lines.append("")
        lines.append("Latest user message:")
        lines.append(latestUserText)
        lines.append("")
        lines.append("Reply as Sovereign to the latest user message.")
        return lines.joined(separator: "\n")
    }

    private func syncConversationTitle(for conversationID: UUID, missionStore: MissionStore) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              case .commitment(let id, _) = conversations[index].context,
              let commitment = missionStore.commitment(with: id) else {
            return
        }
        conversations[index].context = .commitment(id: id, title: commitment.title)
    }

    private func syncPlanConversationTitle(for conversationID: UUID, planStore: PlanStore) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              case .plan(let id, _) = conversations[index].context,
              let plan = planStore.plan(id: id) else {
            return
        }
        conversations[index].context = .plan(id: id, title: plan.title)
    }

    /// Find a conversation by its context, or create a new one.
    func findOrCreateConversation(for context: ConversationContext) -> Conversation {
        // Match plan/commitment/collab/decision by stable id so title renames reopen the same thread.
        if let planID = context.planID,
           let existing = conversations.first(where: { $0.context.planID == planID }) {
            return existing
        }
        if let commitmentID = context.commitmentID,
           let existing = conversations.first(where: { $0.context.commitmentID == commitmentID }) {
            return existing
        }
        if case .collab(let id, _, _) = context,
           let existing = conversations.first(where: {
               if case .collab(let other, _, _) = $0.context { return other == id }
               return false
           }) {
            return existing
        }
        if case .decision(let id, _) = context,
           let existing = conversations.first(where: {
               if case .decision(let other, _) = $0.context { return other == id }
               return false
           }) {
            return existing
        }
        if let existing = conversations.first(where: { $0.context == context }) {
            return existing
        }
        let conversation = Conversation(
            id: UUID(),
            context: context,
            lastActive: Date()
        )
        conversations.insert(conversation, at: 0)
        return conversation
    }

    /// Messages for a given conversation, in display order
    func messages(for conversationId: UUID) -> [Message] {
        allMessages.filter { $0.conversationId == conversationId }
    }

    // MARK: - Private

    private func appendMessage(_ message: Message) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            allMessages.append(message)
            // Update the conversation's last active time
            if let idx = conversations.firstIndex(where: { $0.id == message.conversationId }) {
                conversations[idx].lastActive = message.timestamp
                // Move to top
                let conv = conversations.remove(at: idx)
                conversations.insert(conv, at: 0)
            }
        }
        persistIfLive()
    }

    private func persistIfLive() {
        guard connectionManager.isCryptoChatReady else { return }
        ConversationStore.shared.save(
            conversations: conversations,
            messages: allMessages
        )
    }

    // MARK: - Sample Data

    private func seedSampleData() {
        let q3ProgramId = UUID()
        let partnerTargetId = UUID()
        let taskId = UUID()

        // Create conversations for each mission level
        let programContext = ConversationContext.program(id: q3ProgramId, name: "Q3 Go-to-Market")
        let targetContext = ConversationContext.target(id: partnerTargetId, name: "Partner Onboarding", programName: "Q3 Go-to-Market")
        let taskContext = ConversationContext.task(id: taskId, name: "Design visual assets", targetName: "Content Strategy", programName: "Q3 Go-to-Market")

        let programConv = Conversation(id: UUID(), context: programContext, lastActive: Date().addingTimeInterval(-3600), isDemoSeed: true)
        let targetConv = Conversation(id: UUID(), context: targetContext, lastActive: Date().addingTimeInterval(-86400), isDemoSeed: true)
        let taskConv = Conversation(id: UUID(), context: taskContext, lastActive: Date().addingTimeInterval(-86400 * 2), isDemoSeed: true)
        let standaloneConv = Conversation(id: UUID(), context: .standalone(title: "Morning Briefing"), lastActive: Date().addingTimeInterval(-7200), isDemoSeed: true)
        let pipelineConv = Conversation(id: UUID(), context: .standalone(title: "Pipeline Review"), lastActive: Date().addingTimeInterval(-86400 * 5), isDemoSeed: true)

        conversations = [programConv, standaloneConv, pipelineConv, targetConv, taskConv]

        // Program chat messages
        allMessages.append(contentsOf: [
            Message(conversationId: programConv.id, content: "How's the Q3 launch looking? I'm worried about the timeline.", role: .user, timestamp: Date().addingTimeInterval(-4000)),
            Message(conversationId: programConv.id, content: "The launch is tracking well. All three targets are active. Partner Onboarding is the main dependency — once that clears, we're in good shape. Want me to run through each target?", role: .centurion, timestamp: Date().addingTimeInterval(-3900)),
            Message(conversationId: programConv.id, content: "Yes, give me the highlights.", role: .user, timestamp: Date().addingTimeInterval(-3700)),
            Message(conversationId: programConv.id, content: "**Q3 Go-to-Market**: 74% complete, 12 tasks, 5 done. **Partner Onboarding**: backlogged — needs your sign-off. **Content Strategy**: in review, awaiting feedback on the messaging framework. The critical path runs through Partner Onboarding.", role: .centurion, timestamp: Date().addingTimeInterval(-3600)),
        ])

        // Target chat messages
        allMessages.append(contentsOf: [
            Message(conversationId: targetConv.id, content: "What's the status on Partner Onboarding? The integration partner is asking for timelines.", role: .user, timestamp: Date().addingTimeInterval(-90000)),
            Message(conversationId: targetConv.id, content: "Partner Onboarding is currently in backlog. The key dependencies are: 1) Legal review of partnership terms, 2) API documentation handover. I can draft the onboarding kit today if you want to kick things off.", role: .centurion, timestamp: Date().addingTimeInterval(-89800)),
            Message(conversationId: targetConv.id, content: "Yes, please draft it. I want to move this to active this week.", role: .user, timestamp: Date().addingTimeInterval(-89500)),
            Message(conversationId: targetConv.id, content: "Done. I've created the onboarding kit draft and moved Partner Onboarding to my active queue. I'll have the API docs ready for review by tomorrow.", role: .centurion, timestamp: Date().addingTimeInterval(-86400)),
        ])

        // Task chat messages
        allMessages.append(contentsOf: [
            Message(conversationId: taskConv.id, content: "The visual assets are blocked on the messaging framework. Can we push forward with placeholder designs?", role: .user, timestamp: Date().addingTimeInterval(-180000)),
            Message(conversationId: taskConv.id, content: "Good idea. I'll use the working draft from the messaging team and create concept mockups. We can refine once the final copy lands. I'll have three concepts by end of week.", role: .centurion, timestamp: Date().addingTimeInterval(-179800)),
        ])

        // Standalone: Morning Briefing
        allMessages.append(contentsOf: [
            Message(conversationId: standaloneConv.id, content: "Good morning. What's on my schedule today?", role: .user, timestamp: Date().addingTimeInterval(-8000)),
            Message(conversationId: standaloneConv.id, content: "Good morning! Three priorities today:\n\n1. **Q3 Revenue Review** at 10am\n2. **Partner Onboarding Session** at 2pm\n3. **Product Demo** at 4pm\n\nI've prepped briefing notes for each. Shall I walk through the revenue review first?", role: .centurion, timestamp: Date().addingTimeInterval(-7900)),
            Message(conversationId: standaloneConv.id, content: "Yes, start with the revenue review.", role: .user, timestamp: Date().addingTimeInterval(-7700)),
            Message(conversationId: standaloneConv.id, content: "Q3 Revenue: Enterprise at 127% of target, SMB at 89%, Partners at 215%. The key discussion point will be SMB resourcing — they're understaffed relative to the opportunity. I'd recommend reallocating from Enterprise.", role: .centurion, timestamp: Date().addingTimeInterval(-7200)),
        ])

        // Standalone: Pipeline Review
        allMessages.append(contentsOf: [
            Message(conversationId: pipelineConv.id, content: "Run the pipeline for this week.", role: .user, timestamp: Date().addingTimeInterval(-440000)),
            Message(conversationId: pipelineConv.id, content: "Three new opportunities this week. Total pipeline value: $127,000.\n\n1. **TechCorp** — $45k — Enterprise license — stage: negotiation\n2. **StartupXYZ** — $22k — SMB tier — stage: demo scheduled\n3. **DataFlow Inc** — $60k — Enterprise — stage: initial discovery\n\nTechCorp is closest to close — they're just finalising budget approval.", role: .centurion, timestamp: Date().addingTimeInterval(-439800)),
        ])

        // Sort all messages chronologically
        allMessages.sort { $0.timestamp < $1.timestamp }
        UserDefaults.standard.set(true, forKey: "centurion.chatDemoActive")
    }
}
