import Foundation
import SwiftUI

/// A single message in the unified mission chat stream.
/// Every message belongs to a conversation which is tied to a mission context.
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let conversationId: UUID
    let content: String
    let role: MessageRole
    let timestamp: Date

    init(id: UUID = UUID(), conversationId: UUID, content: String, role: MessageRole, timestamp: Date = Date()) {
        self.id = id
        self.conversationId = conversationId
        self.content = content
        self.role = role
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable {
    case user
    case centurion
    case system

    var tintColor: Color {
        switch self {
        case .user: return .accentColor
        case .centurion: return ColorTheme.accent()
        case .system: return ColorTheme.mutedText()
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
