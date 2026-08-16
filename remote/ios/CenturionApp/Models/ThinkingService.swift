import Foundation

/// Live thinking-service status from the connected Centurion host.
struct ThinkingServiceStatus: Codable, Equatable {
    let provider: String
    let model: String
    let baseURL: String?
    let health: String
    let healthMessage: String
    let lastGoodAvailable: Bool
    let probeLatencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case baseURL = "base_url"
        case health
        case healthMessage = "health_message"
        case lastGoodAvailable = "last_good_available"
        case probeLatencyMs = "probe_latency_ms"
    }

    var isHealthy: Bool { health == "ok" }
}

enum LLMHealthState: Equatable {
    case unknown
    case healthy
    case degraded(String)
    case broken(String, code: String?, retryable: Bool)

    var label: String {
        switch self {
        case .unknown: return "Checking…"
        case .healthy: return "Working normally"
        case .degraded: return "May be slow"
        case .broken: return "Needs attention"
        }
    }

    /// True only for a missing/invalid thinking setup — not a slow reply or a dropped pipe.
    var needsAttention: Bool {
        switch self {
        case .broken(_, let code, _):
            return Self.isThinkingSetupProblem(code)
        case .healthy, .unknown, .degraded:
            return false
        }
    }

    static func isThinkingSetupProblem(_ code: String?) -> Bool {
        switch code {
        case "LLM_AUTH_MISSING",
             "LLM_AUTH_INVALID",
             "LLM_CONFIG_INVALID",
             "LLM_MODEL_INVALID":
            return true
        default:
            return false
        }
    }
}

struct SupportBundleResult: Equatable {
    let ok: Bool
    let code: String
    let summary: String
    let thinkingHealth: String
    let message: String
}

struct HealthCheckResult: Equatable {
    let ok: Bool
    let summary: String
    let thinkingHealth: String
    let issueCount: Int
}

struct AutoFixResult: Equatable {
    let ok: Bool
    let message: String
    let thinkingHealth: String
    let restored: Bool
}

struct LLMRecoveryAction: Equatable {
    let title: String
    let kind: Kind

    enum Kind: Equatable {
        case retry
        case restoreLastGood
        case openRecovery
    }
}

struct ProviderSwitchResult: Equatable {
    let ok: Bool
    let message: String
    let provider: String
    let model: String
}
