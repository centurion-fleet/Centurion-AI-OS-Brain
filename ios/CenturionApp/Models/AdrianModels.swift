import Foundation

/// Adrian — Sovereign's cloud support guide (independent of the LAN Sovereign link).
struct AdrianMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    enum Role: String {
        case user
        case adrian
    }

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct AdrianSuggestedAction: Identifiable, Equatable {
    let id: String
    let label: String
}

struct AdrianChatContext: Encodable {
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

enum AdrianAction: String {
    case openConnect
    case tryAutoFix
    case openGetHelp
    case openMission
}

enum AdrianConfig {
    /// Adrian on iPhone uses the Help Center API — same articles as help.1human1ai.com.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "CenturionAdrianBaseURL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return CenturionHelp.baseURL
    }
}

/// Sovereign help center — single source of truth for support articles and Adrian answers.
enum CenturionHelp {
    static let baseURL = URL(string: "https://help.1human1ai.com")!

    static func article(category: String, slug: String) -> URL {
        baseURL.appending(path: "docs/\(category)/\(slug)")
    }

    static let linkIPhone = article(category: "link-your-iphone", slug: "find-and-link")
    static let thinkingService = article(category: "thinking-service", slug: "what-is-a-thinking-service")
    static let troubleshooting = baseURL.appending(path: "docs/troubleshooting")
    static let privacy = baseURL.appending(path: "docs/privacy-and-security")
}
