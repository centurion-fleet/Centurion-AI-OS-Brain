import Foundation
import SwiftUI

/// A single message in a conversation with the user's Centurion
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let conversationId: UUID
    let content: String
    let role: MessageRole
    let timestamp: Date
    let encrypted: Bool
    
    init(id: UUID = UUID(), conversationId: UUID, content: String, role: MessageRole, encrypted: Bool = true) {
        self.id = id
        self.conversationId = conversationId
        self.content = content
        self.role = role
        self.timestamp = Date()
        self.encrypted = encrypted
    }
}

enum MessageRole: String, Codable {
    case user
    case centurion
    case system
    
    var tintColor: Color {
        switch self {
        case .user: return .accentColor
        case .centurion: return Color(red: 1.0, green: 0.84, blue: 0.0) // Centurion gold
        case .system: return .secondary
        }
    }
    
    var displayName: String {
        switch self {
        case .user: return "You"
        case .centurion: return "Centurion"
        case .system: return ""
        }
    }
}
