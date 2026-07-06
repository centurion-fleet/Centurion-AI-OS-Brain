import Foundation
import Combine

/// Manages conversations and message history with the Centurion.
/// All messages are encrypted before transmission via ConnectionManager.

@MainActor
final class MessageService: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentMessages: [Message] = []
    
    private let connectionManager: ConnectionManager
    private var cancellables = Set<AnyCancellable>()
    
    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    func sendMessage(_ text: String, to conversationId: UUID) async throws {
        // Add local message immediately (optimistic UI)
        let localMessage = Message(
            conversationId: conversationId,
            content: text,
            role: .user
        )
        currentMessages.append(localMessage)
        
        // Encrypt and send
        try await connectionManager.sendMessage(text)
        
        // In production: receive the encrypted response, decrypt it,
        // and append the Centurion's reply
    }
    
    func loadConversation(_ id: UUID) {
        // Load message history from local cache
        // In production: sync with Centurion via encrypted channel
    }
    
    func createNewConversation() -> Conversation {
        let conversation = Conversation(
            id: UUID(),
            title: "New Conversation",
            lastMessage: "",
            lastActive: Date(),
            messageCount: 0,
            isEncrypted: true
        )
        conversations.insert(conversation, at: 0)
        return conversation
    }
}
