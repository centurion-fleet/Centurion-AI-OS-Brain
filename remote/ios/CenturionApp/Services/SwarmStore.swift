import Foundation

/// Ambient Collaboration state for Home constellation and signal-driven attention.
/// Join / invite / start lives in SwarmConnectSheet — Brain is source of truth.
@MainActor
final class SwarmStore: ObservableObject {
    @Published private(set) var swarms: [SwarmSummary] = []
    @Published private(set) var signals: [SwarmSignal] = []
    @Published private(set) var outcomes: [SwarmOutcome] = []
    @Published private(set) var activities: [SwarmActivity] = []
    /// In-app attention preference only — does not schedule OS notifications in this build.
    @Published var digestMode: SwarmDigestMode = .whenNeeded
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isShowingOfflineCache: Bool = false

    private let digestKey = "centurion.swarm.digest.v1"
    private let snapshotCacheKey = "centurion.swarm.snapshot.v2"
    private let snapshotCachedAtKey = "centurion.swarm.snapshot.cached_at.v2"

    enum SwarmDigestMode: String, CaseIterable {
        case whenNeeded = "when_needed"
        case daily = "daily"

        var label: String {
            switch self {
            case .whenNeeded: return "Surface decisions in the app when needed"
            case .daily: return "Keep Pulse quieter until I open it"
            }
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: digestKey),
           let mode = SwarmDigestMode(rawValue: raw) {
            digestMode = mode
        }
        clearLegacyCanonicalCache()
        UserDefaults.standard.removeObject(forKey: "centurion.swarm.formation.dismissed")
        loadOfflineCache()
    }

    var heroSwarms: [SwarmSummary] {
        swarms
            .filter(\.heroVisible)
            .sorted { $0.attentionScore > $1.attentionScore }
    }

    var pendingSignalCount: Int {
        signals.filter(\.isPending).count
    }

    /// Human attention model: only open human-facing signals interrupt the user (in-app).
    var signalsRequiringAttention: [SwarmSignal] {
        let pending = signals.filter { $0.isPending && ($0.type == .decision || $0.type == .ceremony) }
        switch digestMode {
        case .whenNeeded:
            return pending
        case .daily:
            return []
        }
    }

    /// Mission line for constellation / detail — Life Mission when tethered.
    func missionGroundingLine(for swarm: SwarmSummary, lifeMissionStatement: String?) -> String? {
        guard swarm.missionId != nil else { return nil }
        let statement = (lifeMissionStatement ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !statement.isEmpty {
            return statement
        }
        return "Grounded in your Life Mission"
    }

    func swarm(for id: String) -> SwarmSummary? {
        swarms.first { $0.id == id }
    }

    func signals(for swarmId: String) -> [SwarmSignal] {
        signals.filter { $0.swarmId == swarmId && $0.isPending }
    }

    func outcomes(for swarmId: String) -> [SwarmOutcome] {
        outcomes.filter { $0.swarmId == swarmId }
    }

    func activities(for swarmId: String) -> [SwarmActivity] {
        activities.filter { $0.swarmId == swarmId }.sorted { $0.at > $1.at }
    }

    func refresh(from connectionManager: ConnectionManager) async {
        guard connectionManager.connectionState == .connected else {
            // Keep last-known constellation; label as offline.
            isShowingOfflineCache = !swarms.isEmpty
            return
        }
        do {
            let snapshot = try await connectionManager.fetchSwarmSnapshot()
            try apply(snapshot: snapshot, persistCache: true)
            lastSyncError = nil
            isShowingOfflineCache = false
            lastSyncedAt = Date()
        } catch {
            lastSyncError = error.localizedDescription
            isShowingOfflineCache = !swarms.isEmpty
        }
    }

    func setDigestMode(_ mode: SwarmDigestMode) {
        digestMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: digestKey)
    }

    func resolveSignal(_ signalId: String, connectionManager: ConnectionManager? = nil) {
        guard let index = signals.firstIndex(where: { $0.id == signalId }) else { return }
        let previous = signals[index]
        signals[index].status = .resolved
        refreshPendingCounts()

        guard let connectionManager, connectionManager.connectionState == .connected else {
            return
        }
        Task {
            do {
                _ = try await connectionManager.resolveSwarmSignal(signalId: signalId)
                await refresh(from: connectionManager)
            } catch {
                await MainActor.run {
                    if let idx = signals.firstIndex(where: { $0.id == signalId }) {
                        signals[idx] = previous
                        refreshPendingCounts()
                    }
                    lastSyncError = error.localizedDescription
                }
            }
        }
    }

    func primaryActionTitle(for swarm: SwarmSummary) -> String? {
        if let signal = signals(for: swarm.id).first {
            switch signal.type {
            case .decision, .ceremony: return "Make your choice"
            case .handoff: return "See what's needed"
            }
        }
        switch swarm.pulse {
        case .waiting, .attention: return "See what's needed"
        case .blocked: return "See what's needed"
        default: return nil
        }
    }

    // MARK: - Private

    private func refreshPendingCounts() {
        for index in swarms.indices {
            let count = signalsRequiringAttention.filter { $0.swarmId == swarms[index].id }.count
            swarms[index].pendingSignalCount = count
            if count > 0, swarms[index].pulse != .forming, swarms[index].pulse != .complete {
                swarms[index].pulse = .waiting
            }
        }
    }

    private func apply(snapshot: [String: Any], persistCache: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SwarmSnapshot.self, from: data)
        swarms = decoded.swarms
        signals = decoded.signals
        outcomes = decoded.outcomes
        activities = decoded.activities
        refreshPendingCounts()
        if persistCache {
            UserDefaults.standard.set(data, forKey: snapshotCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: snapshotCachedAtKey)
        }
    }

    private func loadOfflineCache() {
        guard let data = UserDefaults.standard.data(forKey: snapshotCacheKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(SwarmSnapshot.self, from: data)
            swarms = decoded.swarms
            signals = decoded.signals
            outcomes = decoded.outcomes
            activities = decoded.activities
            refreshPendingCounts()
            isShowingOfflineCache = true
            if let ts = UserDefaults.standard.object(forKey: snapshotCachedAtKey) as? Double {
                lastSyncedAt = Date(timeIntervalSince1970: ts)
            }
        } catch {
            // Corrupt cache — ignore
        }
    }

    private func clearLegacyCanonicalCache() {
        UserDefaults.standard.removeObject(forKey: "centurion.swarms.v1")
        UserDefaults.standard.removeObject(forKey: "centurion.swarm.signals.v1")
    }
}

private struct SwarmSnapshot: Codable {
    var swarms: [SwarmSummary] = []
    var signals: [SwarmSignal] = []
    var outcomes: [SwarmOutcome] = []
    var activities: [SwarmActivity] = []
}
