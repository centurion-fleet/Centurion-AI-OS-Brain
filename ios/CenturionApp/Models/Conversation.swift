import Foundation

/// A conversation thread with the user's Centurion
struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var lastMessage: String
    var lastActive: Date
    var messageCount: Int
    var isEncrypted: Bool
    
    static func preview() -> Conversation {
        Conversation(
            id: UUID(),
            title: "Morning Briefing",
            lastMessage: "Your schedule today has three key priorities...",
            lastActive: Date(),
            messageCount: 12,
            isEncrypted: true
        )
    }
}

/// A Centurion device discovered on the network
struct CenturionDevice: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let hostname: String
    let ipAddress: String
    let port: Int
    let publicKey: Data?
    let isConnected: Bool
    let connectionMethod: ConnectionMethod
    let lastSeen: Date
    
    enum ConnectionMethod: String, Codable {
        case lan      // Local network (mDNS)
        case tailscale // Tailscale tunnel
        
        var icon: String {
            switch self {
            case .lan: return "wifi"
            case .tailscale: return "shield.fill"
            }
        }
    }
}
