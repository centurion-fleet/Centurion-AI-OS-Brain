import Foundation
import SwiftUI

struct RemoteModelCatalog: Codable, Equatable {
    let textModels: [RemoteConnectorRow]
    let creativeModels: [RemoteConnectorRow]
    let activeConnectorId: String?
    let routingMode: String

    enum CodingKeys: String, CodingKey {
        case textModels = "text_models"
        case creativeModels = "creative_models"
        case activeConnectorId = "active_connector_id"
        case routingMode = "routing_mode"
    }

    var allConnectors: [RemoteConnectorRow] {
        textModels + creativeModels
    }

    /// Built-in list mirrored from ``centurion_cli/remote_model_catalog.py``.
    /// Used when the live catalog cannot be fetched from the linked Centurion.
    ///
    /// - ``activeConnectorId`` marks the live thinking service from host status.
    /// - ``configuredKeyEnvs`` marks families that already have access on the host
    ///   so fallback does not falsely show “Needs access” for every row.
    static func bundled(
        activeConnectorId: String? = nil,
        routingMode: String = "manual",
        configuredKeyEnvs: Set<String> = []
    ) -> RemoteModelCatalog {
        let text = bundledTextModels.map {
            $0.withFallbackFlags(
                activeId: activeConnectorId,
                configuredKeyEnvs: configuredKeyEnvs
            )
        }
        let creative = bundledCreativeModels.map {
            $0.withFallbackFlags(
                activeId: activeConnectorId,
                configuredKeyEnvs: configuredKeyEnvs
            )
        }
        return RemoteModelCatalog(
            textModels: text,
            creativeModels: creative,
            activeConnectorId: activeConnectorId,
            routingMode: routingMode
        )
    }

    static func connectorID(provider: String, model: String) -> String? {
        let providerKey = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelKey = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bundled(
            activeConnectorId: nil
        ).allConnectors.first {
            $0.provider.lowercased() == providerKey && $0.model.lowercased() == modelKey
        }?.id
    }

    static func displayName(provider: String, model: String) -> String? {
        let providerKey = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelKey = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bundled(
            activeConnectorId: nil
        ).allConnectors.first {
            $0.provider.lowercased() == providerKey && $0.model.lowercased() == modelKey
        }?.displayName
    }

    private static let bundledTextModels: [RemoteConnectorRow] = [
        bundledRow(
            id: "openai-luna",
            displayName: "GPT-5.4 mini",
            provider: "openai-api",
            model: "gpt-5.4-mini",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Quick answers and lightweight tasks"
        ),
        bundledRow(
            id: "openai-terra",
            displayName: "GPT-5.4",
            provider: "openai-api",
            model: "gpt-5.4",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Code, refactoring, and planning"
        ),
        bundledRow(
            id: "openai-sol-pro",
            displayName: "GPT-5.5 Pro",
            provider: "openai-api",
            model: "gpt-5.5-pro",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Deep analysis and long documents"
        ),
        bundledRow(
            id: "anthropic-sonnet-5",
            displayName: "Claude Sonnet 4.6",
            provider: "anthropic",
            model: "claude-sonnet-4-6",
            keyEnv: "ANTHROPIC_API_KEY",
            bestFor: "Writing, email drafts, and copy"
        ),
        bundledRow(
            id: "anthropic-opus-4-8",
            displayName: "Claude Opus 4.7",
            provider: "anthropic",
            model: "claude-opus-4-7",
            keyEnv: "ANTHROPIC_API_KEY",
            bestFor: "Legal review, research, and complex reasoning"
        ),
        bundledRow(
            id: "gemini-3-5-flash",
            displayName: "Gemini 3 Flash",
            provider: "gemini",
            model: "gemini-3-flash-preview",
            keyEnv: "GEMINI_API_KEY",
            bestFor: "Fast multimodal answers"
        ),
        bundledRow(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek v4 Pro",
            provider: "deepseek",
            model: "deepseek-v4-pro",
            keyEnv: "DEEPSEEK_API_KEY",
            bestFor: "Cost-effective coding and analysis"
        ),
        bundledRow(
            id: "xai-grok-4-5",
            displayName: "Grok 4.3",
            provider: "xai",
            model: "grok-4.3",
            keyEnv: "XAI_API_KEY",
            bestFor: "Real-time knowledge and direct answers"
        ),
    ]

    private static let bundledCreativeModels: [RemoteConnectorRow] = [
        bundledRow(
            id: "openai-dalle-3",
            displayName: "DALL-E 3",
            provider: "openai-api",
            model: "dall-e-3",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Images, logos, and thumbnails",
            creativeKind: "image_gen"
        ),
        bundledRow(
            id: "runway-gen-4",
            displayName: "Runway Gen-4",
            provider: "runway",
            model: "gen-4",
            keyEnv: "RUNWAY_API_KEY",
            bestFor: "Video ads and storyboards",
            creativeKind: "video_gen"
        ),
        bundledRow(
            id: "elevenlabs-multilingual",
            displayName: "ElevenLabs",
            provider: "elevenlabs",
            model: "eleven_multilingual_v2",
            keyEnv: "ELEVENLABS_API_KEY",
            bestFor: "Voiceovers and read-aloud",
            creativeKind: "tts"
        ),
        bundledRow(
            id: "fal-kling-v3-4k",
            displayName: "Kling",
            provider: "fal",
            model: "kling-v3-4k",
            keyEnv: "FAL_KEY",
            bestFor: "High-quality video generation",
            creativeKind: "video_gen"
        ),
    ]

    private static func bundledRow(
        id: String,
        displayName: String,
        provider: String,
        model: String,
        keyEnv: String,
        bestFor: String,
        creativeKind: String? = nil
    ) -> RemoteConnectorRow {
        RemoteConnectorRow(
            id: id,
            displayName: displayName,
            provider: provider,
            model: model,
            category: creativeKind == nil ? "text" : "creative",
            keyEnv: keyEnv,
            baseURL: nil,
            bestFor: bestFor,
            creativeKind: creativeKind,
            configured: false,
            needsKey: true,
            active: false,
            healthy: nil
        )
    }
}

struct RemoteConnectorRow: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let provider: String
    let model: String
    let category: String
    let keyEnv: String
    let baseURL: String?
    let bestFor: String
    let creativeKind: String?
    let configured: Bool
    let needsKey: Bool
    let active: Bool
    let healthy: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case provider
        case model
        case category
        case keyEnv = "key_env"
        case baseURL = "base_url"
        case bestFor = "best_for"
        case creativeKind = "creative_kind"
        case configured
        case needsKey = "needs_key"
        case active
        case healthy
    }

    var statusLabel: String {
        if active { return "Active" }
        if needsKey { return "Needs access" }
        if let healthy, !healthy { return "Unreachable" }
        if configured { return "Ready" }
        return "Not set up"
    }

    func markingActive(_ active: Bool) -> RemoteConnectorRow {
        RemoteConnectorRow(
            id: id,
            displayName: displayName,
            provider: provider,
            model: model,
            category: category,
            keyEnv: keyEnv,
            baseURL: baseURL,
            bestFor: bestFor,
            creativeKind: creativeKind,
            configured: configured,
            needsKey: needsKey,
            active: active,
            healthy: healthy
        )
    }

    /// Offline/fallback flags: never invent “Needs access” for a key env we
    /// already know is live on the Sovereign (active thinking service).
    func withFallbackFlags(activeId: String?, configuredKeyEnvs: Set<String>) -> RemoteConnectorRow {
        let isActive = id == activeId
        let knownConfigured = configuredKeyEnvs.contains(keyEnv) || isActive
        return RemoteConnectorRow(
            id: id,
            displayName: displayName,
            provider: provider,
            model: model,
            category: category,
            keyEnv: keyEnv,
            baseURL: baseURL,
            bestFor: bestFor,
            creativeKind: creativeKind,
            configured: knownConfigured,
            needsKey: !knownConfigured,
            active: isActive,
            healthy: nil
        )
    }
}

// MARK: - Provider families (dial)

enum ThinkingFamilyStatus: Equatable {
    case active
    case connecting
    case ready
    case needsAccess
    case unreachable
    case unknown

    var label: String {
        switch self {
        case .active: return "Active"
        case .connecting: return "Connecting"
        case .ready: return "Ready"
        case .needsAccess: return "Needs access"
        case .unreachable: return "Unreachable"
        case .unknown: return "Checking"
        }
    }

    var color: Color {
        switch self {
        case .active: return ColorTheme.accent()
        case .connecting: return ColorTheme.accent()
        case .ready: return ColorTheme.success()
        case .needsAccess: return ColorTheme.mutedText()
        case .unreachable: return ColorTheme.error()
        case .unknown: return ColorTheme.mutedText()
        }
    }
}

struct ThinkingServiceFamily: Identifiable, Equatable {
    let id: String
    let displayName: String
    let provider: String
    let keyEnv: String
    let connectors: [RemoteConnectorRow]
    let category: String

    var needsAccess: Bool {
        connectors.allSatisfy(\.needsKey)
    }

    var isActive: Bool {
        connectors.contains(where: \.active)
    }

    var activeConnector: RemoteConnectorRow? {
        connectors.first(where: \.active)
    }

    var preferredConnector: RemoteConnectorRow {
        activeConnector ?? connectors.first!
    }

    var summary: String {
        if let active = activeConnector {
            return active.bestFor.isEmpty ? active.displayName : active.bestFor
        }
        if let first = connectors.first {
            return first.bestFor.isEmpty
                ? "\(connectors.count) thinking service\(connectors.count == 1 ? "" : "s")"
                : first.bestFor
        }
        return ""
    }

    func status(isConnecting: Bool) -> ThinkingFamilyStatus {
        if isConnecting { return .connecting }
        if isActive { return .active }
        if needsAccess { return .needsAccess }
        if connectors.contains(where: { $0.healthy == false }) { return .unreachable }
        if connectors.contains(where: \.configured) { return .ready }
        return .unknown
    }

    static func families(from catalog: RemoteModelCatalog, category: String = "text") -> [ThinkingServiceFamily] {
        let rows = category == "creative" ? catalog.creativeModels : catalog.textModels
        var order: [String] = []
        var buckets: [String: [RemoteConnectorRow]] = [:]
        for row in rows {
            let key = row.provider.lowercased()
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let connectors = buckets[key], let first = connectors.first else { return nil }
            return ThinkingServiceFamily(
                id: key,
                displayName: familyDisplayName(for: first.provider),
                provider: first.provider,
                keyEnv: first.keyEnv,
                connectors: connectors,
                category: category
            )
        }
    }

    private static func familyDisplayName(for provider: String) -> String {
        switch provider.lowercased() {
        case "openai-api", "openai": return "OpenAI"
        case "anthropic": return "Claude"
        case "gemini", "google": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "xai": return "Grok"
        case "runway": return "Runway"
        case "elevenlabs": return "ElevenLabs"
        case "fal": return "Kling"
        default:
            return provider
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

