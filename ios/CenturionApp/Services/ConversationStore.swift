import Foundation

/// Persists imported conversations and messages in the app sandbox.
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

    private var attachmentsRoot: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("CenturionRemote/attachments", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
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

    func importTelegramBundle(
        _ bundle: TelegramImportBundle,
        into messageService: MessageService
    ) {
        guard bundle.ok else { return }
        let title = bundle.conversation?.title ?? "Telegram history"
        let context = ConversationContext.standalone(title: title)
        let conversation = Conversation(id: UUID(), context: context, lastActive: Date())
        let sessionRoot = attachmentsRoot.appendingPathComponent(
            bundle.sessionId ?? conversation.id.uuidString,
            isDirectory: true
        )
        try? fileManager.createDirectory(at: sessionRoot, withIntermediateDirectories: true)

        var importedMessages: [Message] = []
        for item in bundle.messages {
            let role: MessageRole = item.role == "user" ? .user : .centurion
            let timestamp: Date
            if let stamp = item.timestamp {
                timestamp = Date(timeIntervalSince1970: stamp)
            } else {
                timestamp = Date()
            }
            let attachments = item.attachments.map { file -> MessageAttachment in
                let dest = sessionRoot.appendingPathComponent(file.filename)
                var missing = file.missing ?? true
                if let encoded = file.contentBase64, !encoded.isEmpty,
                   let data = Data(base64Encoded: encoded) {
                    do {
                        try data.write(to: dest, options: .atomic)
                        missing = false
                    } catch {
                        missing = true
                    }
                } else if !fileManager.fileExists(atPath: dest.path) {
                    missing = true
                }
                return MessageAttachment(
                    id: file.id,
                    filename: file.filename,
                    localPath: dest.path,
                    missing: missing
                )
            }
            importedMessages.append(
                Message(
                    conversationId: conversation.id,
                    content: item.content,
                    role: role,
                    timestamp: timestamp,
                    attachments: attachments
                )
            )
        }

        messageService.mergeImportedConversation(conversation, messages: importedMessages)
        save(conversations: messageService.conversations, messages: messageService.allMessages)
    }

    func restore(into messageService: MessageService) {
        guard let snapshot = loadSnapshot(), !snapshot.conversations.isEmpty else { return }
        let messages = snapshot.messages.map {
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
            conversations: snapshot.conversations,
            messages: messages
        )
    }
}
