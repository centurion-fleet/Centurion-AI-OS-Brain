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
    func clearDemoData() {
        allMessages = []
        conversations = []
        currentConversation = nil
    }

    /// Restore a full multi-conversation snapshot (live Crypto Chat + imports).
    func applySnapshot(conversations: [Conversation], messages: [Message]) {
        self.conversations = conversations.sorted { $0.lastActive > $1.lastActive }
        self.allMessages = messages.sorted { $0.timestamp < $1.timestamp }
        self.currentConversation = self.conversations.first
    }

    /// Seed a one-time context note when opening Discuss from Home Pulse.
    func seedDiscussContext(title: String, detail: String) -> Conversation {
        let conversation = findOrCreateConversation(for: .standalone(title: title))
        let existing = messages(for: conversation.id)
        guard existing.isEmpty else { return conversation }
        let note = Message(
            conversationId: conversation.id,
            content: "Context for this Crypto Chat:\n\(detail)",
            role: .system
        )
        appendMessage(note)
        return conversation
    }

    /// Call after the view has appeared to seed demo conversations when offline.
    func seedInitialData() {
        guard dataMode.showsDemoContent, conversations.isEmpty else { return }
        seedSampleData()
    }

    /// Send a message in a conversation context. Returns the conversation used.
    func sendMessage(
        _ text: String,
        in context: ConversationContext,
        missionStore: MissionStore? = nil
    ) async throws -> Conversation {
        guard connectionManager.connectionState == .connected else {
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
        if case .commitment(let id, _) = context,
           let missionStore,
           let commitment = missionStore.commitment(with: id) {
            outboundBody = MissionCommitmentChat.frameOutbound(
                userText: text,
                commitment: commitment,
                mission: missionStore.mission
            )
        } else {
            outboundBody = text
        }

        let outbound = frameWithConversationHistory(
            latestUserText: outboundBody,
            conversationID: conversation.id
        )

        let rawResponse = try await connectionManager.sendMessage(outbound)
        let displayResponse = MissionCommitmentChat.displayText(strippingUpdateBlockFrom: rawResponse)

        if let missionStore,
           let payload = MissionCommitmentChat.parseUpdate(from: rawResponse) {
            missionStore.applyCommitmentUpdate(payload)
            syncConversationTitle(for: conversation.id, missionStore: missionStore)
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
            case .centurion: speaker = "Centurion"
            case .system: continue
            }
            lines.append("\(speaker): \(message.content)")
        }
        lines.append("")
        lines.append("Latest user message:")
        lines.append(latestUserText)
        lines.append("")
        lines.append("Reply as Centurion to the latest user message.")
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

    /// Find a conversation by its context, or create a new one.
    func findOrCreateConversation(for context: ConversationContext) -> Conversation {
        // Match by context identity (same program ID, target ID, etc.)
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
        guard connectionManager.connectionState == .connected else { return }
        ConversationStore.shared.save(
            conversations: conversations,
            messages: allMessages
        )
    }

    /// Generate a context-aware Centurion response for preview
    private func generateResponse(for text: String, in context: ConversationContext) -> String {
        // In production this comes from the LLM via the encrypted channel.
        // For preview we return contextual responses.
        let lower = text.lowercased()
        if lower.contains("status") || lower.contains("progress") {
            switch context {
            case .program(_, let name):
                return "**\(name)** is on track. \(Int.random(in: 60..<95))% of targets are active. Would you like a breakdown by target?"
            case .target(_, let name, _):
                return "**\(name)** progress: \(Int.random(in: 2..<5)) of \(Int.random(in: 4..<8)) tasks complete. There \(Bool.random() ? "is a blocked item" : "are no blockers") I'd like to discuss."
            case .task(_, let name, _, _):
                return "On **\(name)**: \(Bool.random() ? "I'm waiting on stakeholder feedback before I can proceed." : "Making good progress. Should have an update by end of day.")"
            case .commitment(_, let title):
                return "Let's look at **\(title)** together. Tell me what feels unclear or what you'd like to change."
            case .standalone:
                return "Good question. Let me check the current state of things and get back to you."
            }
        }
        if lower.contains("help") || lower.contains("suggest") {
            return "Here's what I'd suggest based on the current context: let's break this down into actionable next steps. What specific outcome are you looking for?"
        }
        if lower.contains("blocked") || lower.contains("stuck") || lower.contains("issue") {
            return "I understand this is blocking progress. Let me analyse what's needed to unblock it. The quickest path forward would be to \(Bool.random() ? "schedule a review with the stakeholder" : "reallocate resources from a lower-priority item")."
        }
        // Default contextual response
        switch context {
        case .program(_, let name):
            return "I've noted your thoughts on **\(name)**. I'll incorporate this into the next review cycle. Is there anything specific you want me to action?"
        case .target(_, let name, let program):
            return "Thanks for flagging this on **\(name)** (under \(program)). I'll update the task board and keep you posted on any changes."
        case .task(_, let name, _, _):
            return "Noted on **\(name)**. I'll adjust the approach. Let me know if you want me to escalate any blockers."
        case .commitment(_, let title):
            return "I've noted your thoughts on the commitment **\(title)**. Ask me to rename or refine it whenever you're ready."
        case .standalone:
            return "Got it. I'll think about this and follow up. Is there anything else on your mind?"
        }
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

        let programConv = Conversation(id: UUID(), context: programContext, lastActive: Date().addingTimeInterval(-3600))
        let targetConv = Conversation(id: UUID(), context: targetContext, lastActive: Date().addingTimeInterval(-86400))
        let taskConv = Conversation(id: UUID(), context: taskContext, lastActive: Date().addingTimeInterval(-86400 * 2))
        let standaloneConv = Conversation(id: UUID(), context: .standalone(title: "Morning Briefing"), lastActive: Date().addingTimeInterval(-7200))
        let pipelineConv = Conversation(id: UUID(), context: .standalone(title: "Pipeline Review"), lastActive: Date().addingTimeInterval(-86400 * 5))

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
    }
}
