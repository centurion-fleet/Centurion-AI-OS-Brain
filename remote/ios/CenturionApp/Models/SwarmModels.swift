import Foundation

// MARK: - Pulse (drives orb animation)

enum SwarmPulse: String, Codable, CaseIterable {
    case idle
    case active
    case attention
    case waiting
    case blocked
    case complete
    case forming

    var displayLabel: String {
        switch self {
        case .idle: return "Working smoothly"
        case .active: return "In progress"
        case .attention: return "Needs your choice"
        case .waiting: return "Waiting for you"
        case .blocked: return "Paused"
        case .complete: return "Finished for you"
        case .forming: return "Starting up"
        }
    }

    var attentionScore: Int {
        switch self {
        case .waiting: return 100
        case .attention: return 90
        case .blocked: return 70
        case .active: return 50
        case .forming: return 40
        case .idle: return 20
        case .complete: return 5
        }
    }
}

enum SwarmStatus: String, Codable {
    case running
    case paused
    case complete
}

enum SwarmFormationSource: String, Codable {
    case chat
    case meeting
    case manual
}

enum SwarmParticipantKind: String, Codable {
    case centurion
    case human
}

enum SwarmParticipantRole: String, Codable {
    case owner
    case operatorRole = "operator"
    case observer
}

struct SwarmParticipant: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var kind: SwarmParticipantKind
    var role: SwarmParticipantRole
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: SwarmParticipantKind,
        role: SwarmParticipantRole,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.role = role
        self.isActive = isActive
    }
}

enum SwarmSignalType: String, Codable {
    case decision
    case ceremony
    case handoff
}

enum SwarmSignalStatus: String, Codable {
    case open
    case resolved
}

struct SwarmSignal: Identifiable, Codable, Equatable {
    let id: String
    let swarmId: String
    var type: SwarmSignalType
    var message: String
    var status: SwarmSignalStatus
    var createdAt: Date

    var isPending: Bool { status == .open }
}

enum SwarmOutcomeStatus: String, Codable {
    case ready
    case inProgress = "in_progress"
    case complete
}

struct SwarmOutcome: Identifiable, Codable, Equatable {
    let id: String
    let swarmId: String
    var description: String
    var status: SwarmOutcomeStatus
    var ownerName: String
    var createdAt: Date
}

struct SwarmActivity: Identifiable, Codable, Equatable {
    let id: String
    let swarmId: String
    var kind: String
    var summary: String
    var at: Date
}

/// Slim client model — mirrors dashboard `SwarmSummary` and portal project sync.
struct SwarmSummary: Identifiable, Codable, Equatable {
    let id: String
    var missionId: String?
    var displayName: String
    var objective: String
    var status: SwarmStatus
    var pulse: SwarmPulse
    var formationSource: SwarmFormationSource
    var participants: [SwarmParticipant]
    var pendingSignalCount: Int
    var updatedAt: Date
    var completedAt: Date?

    var attentionScore: Int {
        pulse.attentionScore + pendingSignalCount * 5
    }

    var statusLabel: String { pulse.displayLabel }

    var heroVisible: Bool {
        if pulse == .complete, let completedAt {
            return Date().timeIntervalSince(completedAt) < 48 * 3600
        }
        return status != .complete || pulse != .complete
    }
}

// MARK: - Preview data

extension SwarmSummary {
    static func previewSwarms() -> [SwarmSummary] {
        let q3 = UUID().uuidString
        let content = UUID().uuidString
        let research = UUID().uuidString
        return [
            SwarmSummary(
                id: q3,
                missionId: nil,
                displayName: "Q3 Launch Plan",
                objective: "Research positioning and draft go-to-market for Q3",
                status: .running,
                pulse: .waiting,
                formationSource: .chat,
                participants: [
                    SwarmParticipant(name: "You", kind: .human, role: .owner),
                    SwarmParticipant(name: "Scout", kind: .centurion, role: .operatorRole, isActive: true),
                    SwarmParticipant(name: "Strategist", kind: .centurion, role: .operatorRole, isActive: true),
                ],
                pendingSignalCount: 1,
                updatedAt: Date().addingTimeInterval(-600)
            ),
            SwarmSummary(
                id: content,
                missionId: nil,
                displayName: "Content Pipeline",
                objective: "Weekly briefs and draft posts for the blog",
                status: .running,
                pulse: .active,
                formationSource: .manual,
                participants: [
                    SwarmParticipant(name: "You", kind: .human, role: .owner),
                    SwarmParticipant(name: "Writer", kind: .centurion, role: .operatorRole, isActive: true),
                ],
                pendingSignalCount: 0,
                updatedAt: Date().addingTimeInterval(-3600)
            ),
            SwarmSummary(
                id: research,
                missionId: nil,
                displayName: "Customer Insights",
                objective: "Synthesise review sentiment into product priorities",
                status: .running,
                pulse: .idle,
                formationSource: .meeting,
                participants: [
                    SwarmParticipant(name: "You", kind: .human, role: .owner),
                    SwarmParticipant(name: "Analyst", kind: .centurion, role: .operatorRole),
                ],
                pendingSignalCount: 0,
                updatedAt: Date().addingTimeInterval(-7200)
            ),
            SwarmSummary(
                id: UUID().uuidString,
                missionId: nil,
                displayName: "Partner Deck",
                objective: "Refresh partner one-pager from last quarter wins",
                status: .complete,
                pulse: .complete,
                formationSource: .chat,
                participants: [
                    SwarmParticipant(name: "You", kind: .human, role: .owner),
                    SwarmParticipant(name: "Designer", kind: .centurion, role: .operatorRole),
                ],
                pendingSignalCount: 0,
                updatedAt: Date().addingTimeInterval(-86400),
                completedAt: Date().addingTimeInterval(-3600)
            ),
        ]
    }
}

extension SwarmSignal {
    static func preview(for swarms: [SwarmSummary]) -> [SwarmSignal] {
        guard let first = swarms.first else { return [] }
        return [
            SwarmSignal(
                id: UUID().uuidString,
                swarmId: first.id,
                type: .decision,
                message: "Approve the compliance-first positioning angle for Q3?",
                status: .open,
                createdAt: Date().addingTimeInterval(-300)
            ),
        ]
    }
}

extension SwarmOutcome {
    static func preview(for swarms: [SwarmSummary]) -> [SwarmOutcome] {
        swarms.prefix(2).enumerated().map { index, swarm in
            SwarmOutcome(
                id: UUID().uuidString,
                swarmId: swarm.id,
                description: index == 0
                    ? "Positioning white paper ready for your review"
                    : "Three content briefs drafted for next week",
                status: index == 0 ? .ready : .inProgress,
                ownerName: swarm.participants.first(where: { $0.kind == .centurion })?.name ?? "Sovereign",
                createdAt: Date().addingTimeInterval(Double(-1800 * (index + 1)))
            )
        }
    }
}
