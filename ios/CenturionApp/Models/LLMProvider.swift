import SwiftUI

/// LLM backends your Centurion can think through.
/// Status is surfaced in You so provider outages never feel like Centurion failures.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case claude
    case chatgpt
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .claude:   return "Claude"
        case .chatgpt:  return "ChatGPT"
        case .grok:     return "Grok"
        }
    }

    var shortLabel: String {
        switch self {
        case .deepseek: return "DS"
        case .claude:   return "CL"
        case .chatgpt:  return "GP"
        case .grok:     return "GK"
        }
    }

    var description: String {
        switch self {
        case .deepseek: return "Fast, powerful, and cost-effective. Our primary recommendation."
        case .claude:   return "Excellent reasoning and long context. Great for complex tasks."
        case .chatgpt:  return "Widely capable with strong general knowledge."
        case .grok:     return "Real-time knowledge with a helpful, maximum-truth-seeking personality."
        }
    }

    var isRecommended: Bool { self == .deepseek }

    /// Placeholder health — replace with live Centurion gateway status when wired.
    var status: ProviderConnectionStatus {
        switch self {
        case .deepseek: return .healthy
        case .claude:   return .healthy
        case .chatgpt:  return .degraded
        case .grok:     return .healthy
        }
    }
}

enum ProviderConnectionStatus: Equatable {
    case healthy
    case degraded
    case broken

    var label: String {
        switch self {
        case .healthy:  return "Healthy"
        case .degraded: return "Degraded"
        case .broken:   return "Issue"
        }
    }

    var color: Color {
        switch self {
        case .healthy:  return ColorTheme.success()
        case .degraded: return .orange
        case .broken:   return ColorTheme.error()
        }
    }

    var reassurance: String? {
        switch self {
        case .healthy:
            return nil
        case .degraded:
            return "Responses may be slower. Your Centurion is still working — this provider is under strain."
        case .broken:
            return "This provider is unreachable. Switch the dial to keep your Centurion responsive."
        }
    }
}
