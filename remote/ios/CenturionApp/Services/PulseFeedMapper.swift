import Foundation

/// Maps brain `swarm_snapshot` fields into the Home Pulse pill models.
/// Live / Wins / Outputs / Decisions / Updates are projections of
/// swarms, signals, outcomes, activities — plus local PlanArtifact reviews.
@MainActor
enum PulseFeedMapper {
    struct Feed {
        var liveActivity: LiveActivity?
        var wins: [CompletedLoop]
        var outputs: [CenturionOutput]
        var decisions: [DecisionItem]
        var thoughts: [CenturionThought]
    }

    static func map(from store: SwarmStore, planStore: PlanStore? = nil) -> Feed {
        let liveSwarm = store.heroSwarms
            .filter {
                $0.pulse == .active
                    || $0.pulse == .blocked
                    || $0.pulse == .forming
                    || $0.pulse == .attention
                    || $0.pulse == .waiting
            }
            .sorted { $0.attentionScore > $1.attentionScore }
            .first

        let wins = store.outcomes
            .filter { $0.status == .complete }
            .sorted { $0.createdAt > $1.createdAt }
            .map(completedLoop(from:))

        var outputs = store.outcomes
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map(output(from:))

        if let planStore {
            let planOutputs = planStore.plans.map { $0.asCenturionOutput() }
            outputs = mergeOutputs(planOutputs + Array(outputs))
        }

        var decisions = store.signalsRequiringAttention
            .sorted { $0.createdAt > $1.createdAt }
            .map { decision(from: $0, store: store, planStore: planStore) }

        if let planStore {
            let planDecisions = planStore.pendingReview
                .filter { plan in
                    // Avoid duplicating a swarm-backed decision already mapped.
                    guard let signalId = plan.signalId else { return true }
                    return !decisions.contains { $0.signalId == signalId }
                }
                .map { $0.asDecisionItem() }
            decisions = planDecisions + decisions
        }

        let thoughts = store.activities
            .sorted { $0.at > $1.at }
            .prefix(30)
            .map { thought(from: $0, store: store) }

        return Feed(
            liveActivity: liveSwarm.map { liveActivity(from: $0, store: store) },
            wins: wins,
            outputs: Array(outputs.prefix(24)),
            decisions: decisions,
            thoughts: Array(thoughts)
        )
    }

    static func liveActivity(from swarm: SwarmSummary, store: SwarmStore) -> LiveActivity {
        let recent = store.activities(for: swarm.id).prefix(3)
        let detail: String
        if recent.isEmpty {
            detail = swarm.displayName
        } else {
            detail = recent.map(\.summary).joined(separator: " · ")
        }

        let agents = swarm.participants
            .filter { $0.kind == .centurion }
            .map { participant in
                SubAgentActivity(
                    id: stableUUID("agent:\(swarm.id):\(participant.name)"),
                    name: participant.name,
                    role: participant.role.rawValue,
                    status: participant.isActive ? .active : .waiting,
                    summary: swarm.objective,
                    progress: participant.isActive ? 0.65 : 0.15
                )
            }

        let phase: LoopPhase
        switch swarm.pulse {
        case .forming, .idle:
            phase = .planning
        case .active:
            phase = .executing
        case .blocked, .waiting, .attention:
            phase = .verifying
        case .complete:
            phase = .verifying
        }

        let progress: Double
        switch swarm.pulse {
        case .complete: progress = 1
        case .active: progress = 0.6
        case .attention, .waiting: progress = 0.5
        case .blocked: progress = 0.4
        case .forming: progress = 0.2
        case .idle: progress = 0.1
        }

        let summary: String
        if phase == .planning {
            let objective = swarm.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            summary = objective.isEmpty
                ? "Drafting a plan…"
                : "Drafting a plan: \(objective)"
        } else if swarm.objective.isEmpty {
            summary = swarm.displayName
        } else {
            summary = swarm.objective
        }

        return LiveActivity(
            id: stableUUID("live:\(swarm.id)"),
            phase: phase,
            summary: summary,
            detail: detail,
            progress: progress,
            startedAt: swarm.updatedAt,
            subAgents: agents,
            estimatedCompletion: nil
        )
    }

    private static func completedLoop(from outcome: SwarmOutcome) -> CompletedLoop {
        CompletedLoop(
            id: stableUUID("win:\(outcome.id)"),
            summary: outcome.description,
            detail: "Finished by \(outcome.ownerName)",
            result: outcome.description,
            impact: "Recorded on your Sovereign",
            agentCount: 1,
            duration: 0,
            completedAt: outcome.createdAt,
            subAgentSummary: [outcome.ownerName],
            relatedMission: outcome.ownerName
        )
    }

    private static func output(from outcome: SwarmOutcome) -> CenturionOutput {
        let title = outcome.description
        let type: CenturionOutput.OutputType = looksLikePlan(title) ? .plan : .report
        let body: String
        if type == .plan {
            body = """
            # \(title)

            Your Sovereign proposes this plan.

            Owner: \(outcome.ownerName)
            Status: \(outcome.status.rawValue)
            """
        } else {
            body = "# \(title)\n\nOwner: \(outcome.ownerName)\nStatus: \(outcome.status.rawValue)\n"
        }
        return CenturionOutput(
            id: stableUUID("output:\(outcome.id)"),
            title: String(title.prefix(80)),
            summary: title,
            content: body,
            type: type,
            sourceLoop: outcome.ownerName,
            relatedMission: outcome.ownerName,
            createdAt: outcome.createdAt,
            wordCount: max(title.split(separator: " ").count, 1),
            filePath: "swarm://outcome/\(outcome.id)"
        )
    }

    private static func decision(
        from signal: SwarmSignal,
        store: SwarmStore,
        planStore: PlanStore?
    ) -> DecisionItem {
        let swarmName = store.swarm(for: signal.swarmId)?.displayName
        let isPlan = looksLikePlan(signal.message)
            || (planStore?.plans.contains { $0.signalId == signal.id } ?? false)

        if isPlan {
            if let existing = planStore?.plans.first(where: { $0.signalId == signal.id }) {
                return existing.asDecisionItem()
            }
            let plan = PlanArtifact(
                id: stableUUID("plan-signal:\(signal.id)"),
                title: String(signal.message.prefix(80)),
                goal: signal.message,
                steps: [],
                risks: [],
                openQuestions: [],
                summary: signal.message,
                relatedMission: swarmName,
                signalId: signal.id,
                status: .pendingReview,
                createdAt: signal.createdAt
            )
            return plan.asDecisionItem()
        }

        return DecisionItem(
            id: stableUUID("decision:\(signal.id)"),
            title: signal.message,
            context: swarmName.map { "From collaboration “\($0)”." } ?? "Your Sovereign needs a decision.",
            options: [
                DecisionOption(label: "Proceed", description: "Tell your Sovereign to continue"),
                DecisionOption(label: "Adjust", description: "Open Crypto Chat about this"),
                DecisionOption(label: "Hold", description: "Keep this in Decisions needed for now"),
            ],
            generatedBy: swarmName ?? "Sovereign",
            relatedMission: swarmName,
            urgency: signal.type == .ceremony ? .now : .today,
            createdAt: signal.createdAt,
            signalId: signal.id,
            planId: nil,
            kind: .general
        )
    }

    private static func thought(from activity: SwarmActivity, store: SwarmStore) -> CenturionThought {
        let swarmName = store.swarm(for: activity.swarmId)?.displayName
        let type: CenturionThought.ThoughtType
        switch activity.kind.lowercased() {
        case "win", "complete", "done":
            type = .win
        case "alert", "blocked", "error":
            type = .alert
        case "suggestion":
            type = .suggestion
        case "question":
            type = .question
        default:
            type = .progress
        }
        return CenturionThought(
            id: stableUUID("thought:\(activity.id)"),
            text: activity.summary,
            type: type,
            timestamp: activity.at,
            relatedMission: swarmName
        )
    }

    private static func looksLikePlan(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("plan")
            || lower.contains("propose")
            || lower.contains("before we")
            || lower.contains("approve the")
            || lower.contains("positioning angle")
    }

    private static func mergeOutputs(_ items: [CenturionOutput]) -> [CenturionOutput] {
        var seen = Set<UUID>()
        var result: [CenturionOutput] = []
        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        // Plans first within the recent window
        return result.sorted { lhs, rhs in
            if lhs.type == .plan && rhs.type != .plan { return true }
            if lhs.type != .plan && rhs.type == .plan { return false }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func stableUUID(_ key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in key.utf8.enumerated() {
            bytes[index % 16] ^= byte
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
