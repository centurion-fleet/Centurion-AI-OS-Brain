import Foundation

/// Shared Home-pill and tab-bar badge counts.
/// Matches `MissionPortfolioView` subsection badges: items newer than last visit.
@MainActor
enum PulseBadgeCounts {
    struct LastSeen {
        var plans: TimeInterval
        var wins: TimeInterval
        var outputs: TimeInterval
        var decisions: TimeInterval
        var thoughts: TimeInterval
    }

    static func feed(
        connectionState: ConnectionManager.ConnectionState,
        showsDemoContent: Bool,
        swarmStore: SwarmStore,
        planStore: PlanStore
    ) -> PulseFeedMapper.Feed {
        if connectionState == .connected {
            return PulseFeedMapper.map(from: swarmStore, planStore: planStore)
        }
        if showsDemoContent {
            planStore.seedPreviewIfNeeded(showsDemoContent: true)
            return PulseFeedMapper.Feed(
                liveActivity: LiveActivity.preview(),
                wins: CompletedLoop.preview(),
                outputs: CenturionOutput.preview(),
                decisions: DecisionItem.preview(),
                thoughts: CenturionThought.preview()
            )
        }
        return PulseFeedMapper.Feed(
            liveActivity: nil,
            wins: [],
            outputs: [],
            decisions: [],
            thoughts: []
        )
    }

    static func counts(
        feed: PulseFeedMapper.Feed,
        swarmStore: SwarmStore,
        planStore: PlanStore,
        lastSeen: LastSeen
    ) -> [PulseCategory: Int] {
        let plansCutoff = Date(timeIntervalSinceReferenceDate: lastSeen.plans)
        let winsCutoff = Date(timeIntervalSinceReferenceDate: lastSeen.wins)
        let outputsCutoff = Date(timeIntervalSinceReferenceDate: lastSeen.outputs)
        let decisionsCutoff = Date(timeIntervalSinceReferenceDate: lastSeen.decisions)
        let thoughtsCutoff = Date(timeIntervalSinceReferenceDate: lastSeen.thoughts)

        let liveActive = swarmStore.heroSwarms.contains {
            $0.pulse == .active
                || $0.pulse == .attention
                || $0.pulse == .waiting
                || $0.pulse == .blocked
        } || feed.liveActivity != nil

        return [
            .live: liveActive ? 1 : 0,
            .plans: planStore.pendingReview.filter { $0.createdAt > plansCutoff }.count,
            .wins: feed.wins.filter { $0.completedAt > winsCutoff }.count,
            .outputs: feed.outputs.filter { $0.createdAt > outputsCutoff }.count,
            .decisions: feed.decisions.filter { $0.createdAt > decisionsCutoff }.count,
            .pulse: feed.thoughts.filter { $0.timestamp > thoughtsCutoff }.count,
        ]
    }

    static func total(
        connectionState: ConnectionManager.ConnectionState,
        showsDemoContent: Bool,
        swarmStore: SwarmStore,
        planStore: PlanStore,
        lastSeen: LastSeen
    ) -> Int {
        let feed = feed(
            connectionState: connectionState,
            showsDemoContent: showsDemoContent,
            swarmStore: swarmStore,
            planStore: planStore
        )
        return counts(
            feed: feed,
            swarmStore: swarmStore,
            planStore: planStore,
            lastSeen: lastSeen
        ).values.reduce(0, +)
    }
}
