import Foundation

/// Local cache + host sync for autonomy and reporting preferences.
@MainActor
final class OversightStore: ObservableObject {
    @Published private(set) var prefs: OversightPrefs
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSavedMessage: String?

    private static let cacheKey = "centurion.oversight.prefs.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode(OversightPrefs.self, from: data) {
            prefs = decoded
        } else {
            prefs = .default
        }
    }

    var autonomySubtitle: String {
        prefs.syncedWithSovereign
            ? prefs.autonomyLevel.label
            : "\(prefs.autonomyLevel.label) · on this phone"
    }

    var oversightSubtitle: String {
        prefs.syncedWithSovereign
            ? prefs.reportCadence.label
            : "\(prefs.reportCadence.label) · on this phone"
    }

    func refresh(from connectionManager: ConnectionManager) async {
        guard connectionManager.isCryptoChatReady else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let payload = try await connectionManager.fetchOversight()
            if let oversight = payload["oversight"] as? [String: Any] {
                prefs = OversightPrefs.fromHostPayload(oversight)
                persist()
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setAutonomyLevel(_ level: AutonomyLevel, connectionManager: ConnectionManager) async {
        var updated = prefs
        updated.autonomyLevel = level
        prefs = updated
        persist()
        await push(updated, applyLevelPreset: true, connectionManager: connectionManager)
    }

    func updatePrefs(_ mutate: (inout OversightPrefs) -> Void, connectionManager: ConnectionManager) async {
        var updated = prefs
        mutate(&updated)
        prefs = updated
        persist()
        await push(updated, applyLevelPreset: false, connectionManager: connectionManager)
    }

    private func push(
        _ prefs: OversightPrefs,
        applyLevelPreset: Bool,
        connectionManager: ConnectionManager
    ) async {
        guard connectionManager.isCryptoChatReady else {
            lastSavedMessage = "Saved on this phone. Link your Sovereign to sync."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let payload = try await connectionManager.putOversight(
                prefs.toHostPayload(),
                applyLevelPreset: applyLevelPreset
            )
            if let oversight = payload["oversight"] as? [String: Any] {
                self.prefs = OversightPrefs.fromHostPayload(oversight)
                persist()
            } else {
                var synced = prefs
                synced.syncedWithSovereign = true
                self.prefs = synced
                persist()
            }
            lastSavedMessage = payload["message"] as? String
                ?? "Saved. Changes apply on the next conversation."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            lastSavedMessage = nil
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}
