import Foundation

/// Live Memory Horizon snapshot from the Sovereign brain (Hot Cache / Session Recall / Vault).
struct MemoryHorizonSnapshot: Codable, Equatable {
    var hotCache: HotCacheLayer
    var sessionRecall: SessionRecallLayer
    var vault: VaultLayer

    struct HotCacheLayer: Codable, Equatable {
        var memoryChars: Int
        var memoryLimit: Int
        var userChars: Int
        var userLimit: Int
        var usedChars: Int
        var limitChars: Int
        var fillRatio: Double

        enum CodingKeys: String, CodingKey {
            case memoryChars = "memory_chars"
            case memoryLimit = "memory_limit"
            case userChars = "user_chars"
            case userLimit = "user_limit"
            case usedChars = "used_chars"
            case limitChars = "limit_chars"
            case fillRatio = "fill_ratio"
        }

        static let empty = HotCacheLayer(
            memoryChars: 0, memoryLimit: 2200,
            userChars: 0, userLimit: 1375,
            usedChars: 0, limitChars: 3575, fillRatio: 0
        )
    }

    struct SessionRecallLayer: Codable, Equatable {
        var sessions: Int
        var messages: Int
        var dbBytes: Int
        var freeBytes: Int
        var fillRatio: Double

        enum CodingKeys: String, CodingKey {
            case sessions, messages
            case dbBytes = "db_bytes"
            case freeBytes = "free_bytes"
            case fillRatio = "fill_ratio"
        }

        static let empty = SessionRecallLayer(
            sessions: 0, messages: 0, dbBytes: 0, freeBytes: 0, fillRatio: 0
        )
    }

    struct VaultLayer: Codable, Equatable {
        var enabled: Bool
        var initialized: Bool
        var unlocked: Bool
        var totalEntries: Int
        var pendingProposals: Int
        var counts: [String: Int]
        var dbBytes: Int
        var freeBytes: Int
        var fillRatio: Double

        enum CodingKeys: String, CodingKey {
            case enabled, initialized, unlocked
            case totalEntries = "total_entries"
            case pendingProposals = "pending_proposals"
            case counts
            case dbBytes = "db_bytes"
            case freeBytes = "free_bytes"
            case fillRatio = "fill_ratio"
        }

        static let empty = VaultLayer(
            enabled: false, initialized: false, unlocked: false,
            totalEntries: 0, pendingProposals: 0,
            counts: ["core": 0, "experiential": 0, "pattern": 0],
            dbBytes: 0, freeBytes: 0, fillRatio: 0
        )
    }

    static let empty = MemoryHorizonSnapshot(
        hotCache: .empty,
        sessionRecall: .empty,
        vault: .empty
    )

    enum CodingKeys: String, CodingKey {
        case hotCache = "hot_cache"
        case sessionRecall = "session_recall"
        case vault
    }

    static func fromHostPayload(_ dict: [String: Any]) -> MemoryHorizonSnapshot {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(MemoryHorizonSnapshot.self, from: data) else {
            return .empty
        }
        return decoded
    }
}

enum MemoryHorizonLayer: String, CaseIterable, Identifiable {
    case hotCache
    case sessionRecall
    case vault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotCache: return "Hot Cache"
        case .sessionRecall: return "Session Recall"
        case .vault: return "Vault"
        }
    }

    var horizonLabel: String {
        switch self {
        case .hotCache: return "Near"
        case .sessionRecall: return "Mid"
        case .vault: return "Far"
        }
    }

    var icon: String {
        switch self {
        case .hotCache: return "flame.fill"
        case .sessionRecall: return "bubble.left.and.bubble.right.fill"
        case .vault: return "lock.square.stack.fill"
        }
    }

    var blurb: String {
        switch self {
        case .hotCache:
            return "Essentials your Centurion keeps in every conversation — a curated wallet card."
        case .sessionRecall:
            return "Full conversation history on your Sovereign, reached when past chats matter."
        case .vault:
            return "Sealed long-term notes on your Sovereign — opt-in, passphrase protected."
        }
    }
}
