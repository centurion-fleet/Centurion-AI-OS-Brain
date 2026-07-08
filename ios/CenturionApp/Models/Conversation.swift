import Foundation
import SwiftUI

/// Wrapper for sheet(item:) presentation — avoids timing issues with separate
/// chatContext + showChat state vars.
struct ChatSheetTarget: Identifiable {
    let id = UUID()
    let context: ConversationContext
}

/// Where in the mission hierarchy a conversation lives.
/// Every chat is attached to a mission element — or standalone.
enum ConversationContext: Codable, Equatable, Hashable {
    case program(id: UUID, name: String)
    case target(id: UUID, name: String, programName: String)
    case task(id: UUID, name: String, targetName: String, programName: String)
    case standalone(title: String)

    var displayTitle: String {
        switch self {
        case .program(_, let name): return name
        case .target(_, let name, _): return name
        case .task(_, let name, _, _): return name
        case .standalone(let title): return title
        }
    }

    var contextPath: String {
        switch self {
        case .program(_, let name): return name
        case .target(_, let name, let program): return "\(program) > \(name)"
        case .task(_, let name, let target, let program): return "\(program) > \(target) > \(name)"
        case .standalone: return "Chat"
        }
    }

    var icon: String {
        switch self {
        case .program: return "target"
        case .target: return "arrow.triangle.branch"
        case .task: return "checkmark.circle"
        case .standalone: return "message.fill"
        }
    }

    /// The leading mission-level badge shown on each message in the global stream
    var missionBadge: (name: String, color: Color) {
        switch self {
        case .program(_, let name):
            return (name, ColorTheme.accent())
        case .target(_, let name, let program):
            return ("\(program) > \(name)", ColorTheme.accent().opacity(0.8))
        case .task(_, let name, let target, let program):
            return ("\(program) > \(target) > \(name)", ColorTheme.dimAccent())
        case .standalone:
            return ("Chat", ColorTheme.mutedText())
        }
    }

    /// Coding keys — flattened for Codable conformance
    enum CodingKeys: String, CodingKey {
        case type, id, name, programName, targetName, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "program":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            self = .program(id: id, name: name)
        case "target":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let programName = try container.decode(String.self, forKey: .programName)
            self = .target(id: id, name: name, programName: programName)
        case "task":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let targetName = try container.decode(String.self, forKey: .targetName)
            let programName = try container.decode(String.self, forKey: .programName)
            self = .task(id: id, name: name, targetName: targetName, programName: programName)
        case "standalone":
            let title = try container.decode(String.self, forKey: .title)
            self = .standalone(title: title)
        default:
            self = .standalone(title: "Chat")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .program(let id, let name):
            try container.encode("program", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
        case .target(let id, let name, let programName):
            try container.encode("target", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(programName, forKey: .programName)
        case .task(let id, let name, let targetName, let programName):
            try container.encode("task", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(targetName, forKey: .targetName)
            try container.encode(programName, forKey: .programName)
        case .standalone(let title):
            try container.encode("standalone", forKey: .type)
            try container.encode(title, forKey: .title)
        }
    }
}

/// A Centurion device discovered on the local network via Bonjour.
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

/// A conversation thread — always tied to a mission context.
/// The gold grouping unit in the app.
struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var context: ConversationContext
    var lastActive: Date

    var displayTitle: String { context.displayTitle }
    var contextPath: String { context.contextPath }
    var icon: String { context.icon }
    var missionBadge: (name: String, color: Color) { context.missionBadge }
}

extension ConversationContext {
    var isStandalone: Bool {
        if case .standalone = self { return true }
        return false
    }
}
