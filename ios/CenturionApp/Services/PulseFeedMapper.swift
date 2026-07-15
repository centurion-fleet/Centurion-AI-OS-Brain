import Foundation

/// Maps brain `swarm_snapshot` fields into the Home Pulse pill models.
/// Live / Wins / Outputs / Decisions / Updates are projections of
/// swarms, signals, outcomes, and activities — no extra remote action needed.
@MainActor
enum PulseFeedMapper {
    struct Feed {
        var liveActivity: LiveActivity?
        var wins: [CompletedLoop]
        var outputs: [CenturionOutput]
        var decisions: [DecisionItem]
        var thoughts: [CenturionThought]
    }

    static func map(from store: SwarmStore) -> Feed {
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

        let outputs = store.outcomes
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map(output(from:))

        let decisions = store.signalsRequiringAttention
            .sorted { $0.createdAt > $1.createdAt }
            .map { decision(from: $0, store: store) }

        let thoughts = store.activities
            .sorted { $0.at > $1.at }
            .prefix(30)
            .map { thought(from: $0, store: store) }

        return Feed(
            liveActivity: liveSwarm.map { liveActivity(from: $0, store: store) },
            wins: wins,
            outputs: Array(outputs),
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

        return LiveActivity(
            id: stableUUID("live:\(swarm.id)"),
            phase: phase,
            summary: swarm.objective.isEmpty ? swarm.displayName : swarm.objective,
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
            impact: "Recorded on your Centurion",
            agentCount: 1,
            duration: 0,
            completedAt: outcome.createdAt,
            subAgentSummary: [outcome.ownerName],
            relatedMission: outcome.ownerName
        )
    }

    private static func output(from outcome: SwarmOutcome) -> CenturionOutput {
        let title = outcome.description
        return CenturionOutput(
            id: stableUUID("output:\(outcome.id)"),
            title: String(title.prefix(80)),
            summary: title,
            content: "# \(title)\n\nOwner: \(outcome.ownerName)\nStatus: \(outcome.status.rawValue)\n",
            type: .report,
            sourceLoop: outcome.ownerName,
            relatedMission: outcome.ownerName,
            createdAt: outcome.createdAt,
            wordCount: max(title.split(separator: " ").count, 1),
            filePath: "swarm://outcome/\(outcome.id)"
        )
    }

    private static func decision(from signal: SwarmSignal, store: SwarmStore) -> DecisionItem {
        let swarmName = store.swarm(for: signal.swarmId)?.displayName
        return DecisionItem(
            id: stableUUID("decision:\(signal.id)"),
            title: signal.message,
            context: swarmName.map { "From swarm “\($0)”." } ?? "Your Centurion needs a decision.",
            options: [
                DecisionOption(label: "Discuss", description: "Open Crypto Chat about this"),
                DecisionOption(label: "Approve", description: "Tell your Centurion to proceed"),
                DecisionOption(label: "Hold", description: "Pause and ask for more context"),
            ],
            generatedBy: swarmName ?? "Centurion",
            relatedMission: swarmName,
            urgency: signal.type == .ceremony ? .now : .today,
            createdAt: signal.createdAt
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
