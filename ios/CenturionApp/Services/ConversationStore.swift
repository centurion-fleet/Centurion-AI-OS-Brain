import Foundation

/// Persists live Crypto Chat conversations and messages in the app sandbox.
@MainActor
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published private(set) var hasPersistedData = false

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storageURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("CenturionRemote", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("conversations.json")
    }

    struct Snapshot: Codable {
        var conversations: [Conversation]
        var messages: [StoredMessage]
    }

    struct StoredMessage: Codable, Equatable, Identifiable {
        let id: UUID
        let conversationId: UUID
        let content: String
        let role: MessageRole
        let timestamp: Date
        let attachments: [MessageAttachment]
    }

    func loadSnapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return nil }
        hasPersistedData = !snapshot.conversations.isEmpty
        return snapshot
    }

    func save(conversations: [Conversation], messages: [Message]) {
        let stored = messages.map {
            StoredMessage(
                id: $0.id,
                conversationId: $0.conversationId,
                content: $0.content,
                role: $0.role,
                timestamp: $0.timestamp,
                attachments: $0.attachments
            )
        }
        let snapshot = Snapshot(conversations: conversations, messages: stored)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
        hasPersistedData = !conversations.isEmpty
    }

    func restore(into messageService: MessageService) {
        guard let snapshot = loadSnapshot(), !snapshot.conversations.isEmpty else { return }
        let liveConversations = snapshot.conversations.filter { !$0.isDemoSeed }
        guard !liveConversations.isEmpty else {
            removeDemoContent()
            return
        }
        let liveIds = Set(liveConversations.map(\.id))
        let messages = snapshot.messages
            .filter { liveIds.contains($0.conversationId) }
            .map {
                Message(
                    id: $0.id,
                    conversationId: $0.conversationId,
                    content: $0.content,
                    role: $0.role,
                    timestamp: $0.timestamp,
                    attachments: $0.attachments
                )
            }
        messageService.applySnapshot(
            conversations: liveConversations,
            messages: messages
        )
    }

    /// Drop offline marketing sample threads from disk; keep live Crypto Chat.
    func removeDemoContent() {
        guard let snapshot = loadSnapshot() else {
            hasPersistedData = false
            return
        }
        let liveConversations = snapshot.conversations.filter { !$0.isDemoSeed }
        if liveConversations.isEmpty {
            try? fileManager.removeItem(at: storageURL)
            hasPersistedData = false
            return
        }
        let liveIds = Set(liveConversations.map(\.id))
        let liveMessages = snapshot.messages.filter { liveIds.contains($0.conversationId) }
        save(conversations: liveConversations, messages: liveMessages.map {
            Message(
                id: $0.id,
                conversationId: $0.conversationId,
                content: $0.content,
                role: $0.role,
                timestamp: $0.timestamp,
                attachments: $0.attachments
            )
        })
    }
}
