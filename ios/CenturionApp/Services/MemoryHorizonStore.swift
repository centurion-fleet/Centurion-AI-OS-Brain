import Foundation

/// Host-backed Memory Horizon snapshot for Settings gauges.
@MainActor
final class MemoryHorizonStore: ObservableObject {
    @Published private(set) var snapshot: MemoryHorizonSnapshot = .empty
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var hasLiveData = false

    private static let cacheKey = "centurion.memoryHorizon.snapshot.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode(MemoryHorizonSnapshot.self, from: data) {
            snapshot = decoded
            hasLiveData = true
        }
    }

    var subtitle: String {
        if !hasLiveData {
            return "How your Centurion remembers"
        }
        let hot = Int((snapshot.hotCache.fillRatio * 100).rounded())
        return "Hot Cache \(hot)% · tap to explore"
    }

    func refresh(from connectionManager: ConnectionManager) async {
        guard connectionManager.connectionState == .connected else {
            lastError = nil
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let payload = try await connectionManager.fetchMemoryHorizon()
            if let raw = payload["snapshot"] as? [String: Any] {
                snapshot = MemoryHorizonSnapshot.fromHostPayload(raw)
                persist()
                hasLiveData = true
                lastError = nil
            } else if payload["ok"] as? Bool == false {
                lastError = payload["message"] as? String ?? "Could not read Memory Horizon."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}
