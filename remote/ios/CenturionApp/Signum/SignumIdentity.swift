import Foundation
import SwiftUI

/// The customer's own name for their Centurion — the hero of the interface.
///
/// It comes from the Brain (`soul_get` → `name`), because that is the only place
/// it is authoritative: the owner sets it in the Soul, and the same name then
/// appears in the Brain, the emails and here. Cached in UserDefaults so the
/// screen opens with the right name rather than flashing a placeholder while a
/// network call finishes — the name is the identity of the screen, and an
/// identity that arrives late is worse than one that is cached.
///
/// ⚠️ Never render a model or provider name here. `SoulDocument.displayName`
/// already refuses "Hermes"; this mirrors that rule so a badly edited Soul cannot
/// put a vendor's name in the app's most prominent position.
@MainActor
final class SignumIdentity: ObservableObject {
    @Published private(set) var name: String

    private static let nameKey = "signum.centurionName"

    init() {
        let cached = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        name = Self.sanitised(cached) ?? "Your Centurion"
    }

    /// Pull the Soul once the link is up. Silent on failure — the cached name
    /// stays, which is the whole point of caching it.
    func refresh(using connectionManager: ConnectionManager) async {
        guard connectionManager.isCryptoChatReady else { return }
        guard let soul = try? await connectionManager.fetchSoul() else { return }
        guard let raw = soul["name"] as? String, let clean = Self.sanitised(raw) else { return }
        name = clean
        UserDefaults.standard.set(clean, forKey: Self.nameKey)
    }

    private static func sanitised(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for banned in ["hermes", "gpt", "claude", "gemini", "moonshot"] {
            if trimmed.localizedCaseInsensitiveContains(banned) { return nil }
        }
        return trimmed
    }
}
