import Foundation

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
    static func bundled(
        activeConnectorId: String? = nil,
        routingMode: String = "manual"
    ) -> RemoteModelCatalog {
        let text = bundledTextModels.map { $0.markingActive($0.id == activeConnectorId) }
        let creative = bundledCreativeModels.map { $0.markingActive($0.id == activeConnectorId) }
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
            displayName: "GPT-5.6 Luna",
            provider: "openai",
            model: "gpt-5.6-luna",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Quick answers and lightweight tasks"
        ),
        bundledRow(
            id: "openai-terra",
            displayName: "GPT-5.6 Terra",
            provider: "openai",
            model: "gpt-5.6-terra",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Code, refactoring, and planning"
        ),
        bundledRow(
            id: "openai-sol-pro",
            displayName: "GPT-5.6 Sol Pro",
            provider: "openai",
            model: "gpt-5.6-sol-pro",
            keyEnv: "OPENAI_API_KEY",
            bestFor: "Deep analysis and long documents"
        ),
        bundledRow(
            id: "anthropic-sonnet-5",
            displayName: "Claude Sonnet 5",
            provider: "anthropic",
            model: "claude-sonnet-5",
            keyEnv: "ANTHROPIC_API_KEY",
            bestFor: "Writing, email drafts, and copy"
        ),
        bundledRow(
            id: "anthropic-opus-4-8",
            displayName: "Claude Opus 4.8",
            provider: "anthropic",
            model: "claude-opus-4-8",
            keyEnv: "ANTHROPIC_API_KEY",
            bestFor: "Legal review, research, and complex reasoning"
        ),
        bundledRow(
            id: "google-gemini-3-5-flash",
            displayName: "Gemini 3.5 Flash",
            provider: "google",
            model: "gemini-3.5-flash",
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
            displayName: "Grok 4.5",
            provider: "xai",
            model: "grok-4.5",
            keyEnv: "XAI_API_KEY",
            bestFor: "Real-time knowledge and direct answers"
        ),
    ]

    private static let bundledCreativeModels: [RemoteConnectorRow] = [
        bundledRow(
            id: "openai-dalle-3",
            displayName: "DALL-E 3",
            provider: "openai",
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
        if needsKey { return "Needs key" }
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
}

struct TelegramImportBundle: Decodable, Equatable {
    let ok: Bool
    let conversation: TelegramImportConversation?
    let sessionId: String?
    let messageCount: Int
    let fileCount: Int
    let missingFileCount: Int
    let dateRange: TelegramImportDateRange?
    let messages: [TelegramImportMessage]
    let files: [TelegramImportFile]
    let candidates: [TelegramImportCandidate]
    let message: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case conversation
        case sessionId = "session_id"
        case messageCount = "message_count"
        case fileCount = "file_count"
        case missingFileCount = "missing_file_count"
        case dateRange = "date_range"
        case messages
        case files
        case candidates
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        conversation = try container.decodeIfPresent(TelegramImportConversation.self, forKey: .conversation)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
        missingFileCount = try container.decodeIfPresent(Int.self, forKey: .missingFileCount) ?? 0
        dateRange = try container.decodeIfPresent(TelegramImportDateRange.self, forKey: .dateRange)
        messages = try container.decodeIfPresent([TelegramImportMessage].self, forKey: .messages) ?? []
        files = try container.decodeIfPresent([TelegramImportFile].self, forKey: .files) ?? []
        candidates = try container.decodeIfPresent([TelegramImportCandidate].self, forKey: .candidates) ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

struct TelegramImportConversation: Codable, Equatable {
    let title: String
    let context: String
}

struct TelegramImportDateRange: Codable, Equatable {
    let start: Double?
    let end: Double?
}

struct TelegramImportMessage: Decodable, Equatable {
    let role: String
    let content: String
    let timestamp: Double?
    let attachments: [TelegramImportFile]

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case timestamp
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        attachments = try container.decodeIfPresent([TelegramImportFile].self, forKey: .attachments) ?? []
    }
}

struct TelegramImportFile: Decodable, Equatable, Identifiable {
    let id: String
    let filename: String
    let path: String
    let missing: Bool?
    let contentBase64: String?
    let sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case path
        case missing
        case contentBase64 = "content_base64"
        case sizeBytes = "size_bytes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        missing = try container.decodeIfPresent(Bool.self, forKey: .missing)
        contentBase64 = try container.decodeIfPresent(String.self, forKey: .contentBase64)
        sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes)
    }
}

struct TelegramImportCandidate: Codable, Equatable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let preview: String
    let messageCount: Int
    let lastActive: Double?
    let sessionKey: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case preview
        case messageCount = "message_count"
        case lastActive = "last_active"
        case sessionKey = "session_key"
    }
}
