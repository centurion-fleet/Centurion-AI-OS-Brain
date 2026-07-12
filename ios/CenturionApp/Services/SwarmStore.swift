import Foundation

/// Ambient Swarm state for Home constellation, formation, and signal-driven attention.
@MainActor
final class SwarmStore: ObservableObject {
    @Published private(set) var swarms: [SwarmSummary] = []
    @Published private(set) var signals: [SwarmSignal] = []
    @Published private(set) var outcomes: [SwarmOutcome] = []
    @Published private(set) var activities: [SwarmActivity] = []
    @Published var formationProposal: SwarmFormationProposal?
    @Published var digestMode: SwarmDigestMode = .whenNeeded
    @Published private(set) var lastSyncError: String?

    private let digestKey = "centurion.swarm.digest.v1"
    private let formationDismissedKey = "centurion.swarm.formation.dismissed"

    enum SwarmDigestMode: String, CaseIterable {
        case whenNeeded = "when_needed"
        case daily = "daily"

        var label: String {
            switch self {
            case .whenNeeded: return "Tell me when needed"
            case .daily: return "Daily summary"
            }
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: digestKey),
           let mode = SwarmDigestMode(rawValue: raw) {
            digestMode = mode
        }
        clearLegacyCanonicalCache()
    }

    var heroSwarms: [SwarmSummary] {
        swarms
            .filter(\.heroVisible)
            .sorted { $0.attentionScore > $1.attentionScore }
    }

    var pendingSignalCount: Int {
        signals.filter(\.isPending).count
    }

    /// Human attention model: only open human-facing signals interrupt the user.
    var signalsRequiringAttention: [SwarmSignal] {
        signals.filter { $0.isPending && ($0.type == .decision || $0.type == .ceremony) }
    }

    /// Whether a new signal should surface a push notification (digest mode aware).
    func shouldNotify(for signal: SwarmSignal) -> Bool {
        guard signal.isPending, signal.type == .decision || signal.type == .ceremony else {
            return false
        }
        switch digestMode {
        case .whenNeeded:
            return true
        case .daily:
            return false
        }
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
        guard connectionManager.connectionState == .connected else { return }
        do {
            let snapshot = try await connectionManager.fetchSwarmSnapshot()
            try apply(snapshot: snapshot)
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func setDigestMode(_ mode: SwarmDigestMode) {
        digestMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: digestKey)
    }

    func dismissFormationProposal() {
        formationProposal = nil
        UserDefaults.standard.set(true, forKey: formationDismissedKey)
    }

    func confirmFormation(name: String) {
        guard let proposal = formationProposal else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? proposal.suggestedName : trimmed
        var participants: [SwarmParticipant] = [
            SwarmParticipant(name: "You", kind: .human, role: .owner),
        ]
        for (index, name) in proposal.participantNames.enumerated() {
            participants.append(
                SwarmParticipant(
                    name: name,
                    kind: .centurion,
                    role: .operatorRole,
                    isActive: index == 0
                )
            )
        }
        let swarm = SwarmSummary(
            id: UUID().uuidString,
            missionId: nil,
            displayName: displayName,
            objective: proposal.objective,
            status: .running,
            pulse: .forming,
            formationSource: proposal.source,
            participants: participants,
            pendingSignalCount: 0,
            updatedAt: Date()
        )
        swarms.insert(swarm, at: 0)
        formationProposal = nil
        UserDefaults.standard.set(true, forKey: formationDismissedKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if let index = self.swarms.firstIndex(where: { $0.id == swarm.id }) {
                self.swarms[index].pulse = .active
            }
        }
    }

    func resolveSignal(_ signalId: String) {
        guard let index = signals.firstIndex(where: { $0.id == signalId }) else { return }
        signals[index].status = .resolved
        refreshPendingCounts()
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

    private func seedFormationProposalIfNeeded() {
        guard formationProposal == nil else { return }
        if UserDefaults.standard.bool(forKey: formationDismissedKey) { return }
        formationProposal = SwarmFormationProposal(
            objective: "Research Q3 positioning and draft a go-to-market plan with your Centurions working together.",
            suggestedName: "Q3 Launch Collaboration"
        )
    }

    private func refreshPendingCounts() {
        for index in swarms.indices {
            let count = signalsRequiringAttention.filter { $0.swarmId == swarms[index].id }.count
            swarms[index].pendingSignalCount = count
            if count > 0, swarms[index].pulse != .forming, swarms[index].pulse != .complete {
                swarms[index].pulse = .waiting
            }
        }
    }

    private func apply(snapshot: [String: Any]) throws {
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
