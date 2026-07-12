import Foundation

/// Herald — Centurion's cloud support guide (independent of the LAN Centurion link).
struct HeraldMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    enum Role: String {
        case user
        case herald
    }

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct HeraldSuggestedAction: Identifiable, Equatable {
    let id: String
    let label: String
}

struct HeraldChatContext: Encodable {
    let appVersion: String
    let connectionState: String
    let thinkingHealth: String
    let thinkingMessage: String
    let hasMission: Bool
    let activeTargetCount: Int
    let missionSummary: String
    let supportCode: String

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case connectionState = "connection_state"
        case thinkingHealth = "thinking_health"
        case thinkingMessage = "thinking_message"
        case hasMission = "has_mission"
        case activeTargetCount = "active_target_count"
        case missionSummary = "mission_summary"
        case supportCode = "support_code"
    }
}

enum HeraldAction: String {
    case openConnect
    case tryAutoFix
    case openGetHelp
    case openMission
}

enum HeraldConfig {
    /// Production endpoint — Centurion-operated, customer API keys not required.
    static let defaultBaseURL = "https://herald.centurion.ai"

    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "CenturionHeraldBaseURL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: defaultBaseURL)!
    }
}
