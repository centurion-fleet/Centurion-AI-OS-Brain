import Foundation
import Combine

/// Manages conversations and message history with the Centurion.
/// All messages are encrypted before transmission via ConnectionManager.
/// Seeds sample data on launch so the app never feels empty.

@MainActor
final class MessageService: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentMessages: [Message] = []
    @Published var currentConversationId: UUID?
    
    private let connectionManager: ConnectionManager
    private var cancellables = Set<AnyCancellable>()
    
    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        seedSampleData()
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
        currentConversationId = id
        // Load sample messages for this conversation
        currentMessages = sampleMessages(for: id)
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
    
    // MARK: - Sample Data
    
    private func seedSampleData() {
        conversations = [
            Conversation(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000001")!,
                title: "Morning Briefing",
                lastMessage: "Your schedule today has three key priorities. First, the Q3 revenue review at 10am...",
                lastActive: Date().addingTimeInterval(-3600),
                messageCount: 12,
                isEncrypted: true
            ),
            Conversation(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000002")!,
                title: "Product Launch Strategy",
                lastMessage: "I've analysed the market positioning. Here's what differentiates us from the competition...",
                lastActive: Date().addingTimeInterval(-86400 * 2),
                messageCount: 28,
                isEncrypted: true
            ),
            Conversation(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000003")!,
                title: "Pipeline Review",
                lastMessage: "Three new opportunities this week. Total pipeline value: $127,000. Let me break down each one...",
                lastActive: Date().addingTimeInterval(-86400 * 5),
                messageCount: 45,
                isEncrypted: true
            ),
            Conversation(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000004")!,
                title: "Maori Partnership",
                lastMessage: "The POC framework is ready for your review. I've structured it around the three pillars we discussed...",
                lastActive: Date().addingTimeInterval(-86400 * 7),
                messageCount: 64,
                isEncrypted: true
            ),
        ]
    }
    
    private func sampleMessages(for conversationId: UUID) -> [Message] {
        switch conversationId {
        case UUID(uuidString: "10000001-0000-0000-0000-000000000001")!:
            return [
                Message(conversationId: conversationId, content: "Good morning. What's on my schedule today?", role: .user),
                Message(conversationId: conversationId, content: "Good morning! I've reviewed your calendar. Three priorities stand out:\n\n1. **Q3 Revenue Review** at 10am with the leadership team\n2. **Partner Onboarding Session** at 2pm — new integration partner\n3. **Product Demo** at 4pm with a prospective enterprise client\n\nI've prepped briefing notes for each. Would you like me to walk through them?", role: .centurion),
                Message(conversationId: conversationId, content: "Yes, start with the revenue review.", role: .user),
                Message(conversationId: conversationId, content: "The Q3 review covers three segments:\n\n• **Enterprise**: 127% of target — strong\n• **SMB**: 89% of target — room to grow\n• **Partners**: 215% of target — exceptional\n\nThe key discussion point will likely be resourcing for SMB. They're understaffed relative to the opportunity. I'd recommend proposing a reallocation from the enterprise team, which is overstaffed for current pipeline velocity.", role: .centurion),
            ]
        case UUID(uuidString: "10000001-0000-0000-0000-000000000002")!:
            return [
                Message(conversationId: conversationId, content: "I need a competitive analysis for the product launch.", role: .user),
                Message(conversationId: conversationId, content: "I've been tracking the competitive landscape. Here's the key differentiator:\n\nOur zero-server architecture is something **no competitor** can claim. Not Signal, not Telegram. Every other encrypted messenger routes through a central server.\n\nThis is the story we should lead with in the launch.", role: .centurion),
                Message(conversationId: conversationId, content: "What about pricing positioning?", role: .user),
                Message(conversationId: conversationId, content: "I recommend premium-tier pricing with a transparent value story:\n\n• **Hardware + lifetime software**: One purchase, no subscription\n• **Enterprise tier**: For teams needing fleet management\n• **No data harvesting**: Your privacy isn't the product\n\nThis positions us against both the free (surveillance) and expensive (enterprise) ends of the market.", role: .centurion),
            ]
        default:
            return [
                Message(conversationId: conversationId, content: "What are we working on today?", role: .user),
                Message(conversationId: conversationId, content: "Ready when you are. What would you like to focus on?", role: .centurion),
            ]
        }
    }
}
