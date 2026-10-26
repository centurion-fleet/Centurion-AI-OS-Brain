import Foundation

/// A Mission program — the most senior element in the project hierarchy.
/// Every program can be chatted about. That chat lives in the unified message stream.
struct MissionProgram: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var status: ProgramStatus
    var order: Int
    var targetCount: Int
    var taskCount: Int
    var completedTaskCount: Int
    var createdAt: Date
    var updatedAt: Date
    var isEncrypted: Bool

    enum ProgramStatus: String, Codable, CaseIterable {
        case active = "Active"
        case onHold = "On Hold"
        case completed = "Completed"
        case archived = "Archived"

        var icon: String {
            switch self {
            case .active: return "play.circle.fill"
            case .onHold: return "pause.circle"
            case .completed: return "checkmark.circle.fill"
            case .archived: return "archivebox"
            }
        }

        var iconOpacity: Double {
            switch self {
            case .active, .completed: return 1.0
            case .onHold: return 0.6
            case .archived: return 0.4
            }
        }
    }
}

/// A target within a program.
/// Has its own chat context — messages appear in the unified stream tagged with the program context.
struct MissionTarget: Identifiable, Codable, Equatable {
    let id: UUID
    let programId: UUID
    var title: String
    var description: String
    var status: TargetStatus
    var order: Int
    var tasks: [MissionTask]
    var dueDate: Date?
    var createdAt: Date

    enum TargetStatus: String, Codable, CaseIterable {
        case backlog = "Backlog"
        case active = "Active"
        case review = "In Review"
        case completed = "Completed"
    }
}

/// A task within a target.
/// The most granular chat context — messages tagged with full program > target > task path.
struct MissionTask: Identifiable, Codable, Equatable {
    let id: UUID
    let targetId: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var order: Int
    var assignedTo: String?
    var isBlocked: Bool
    var blockedReason: String?
    var createdAt: Date

    enum TaskStatus: String, Codable, CaseIterable {
        case todo = "To Do"
        case inProgress = "In Progress"
        case done = "Done"
    }
}

// MARK: - Preview Data

extension MissionProgram {
    static func preview() -> [MissionProgram] {
        return [
            MissionProgram(id: UUID(), name: "Q3 Go-to-Market", description: "Launch campaign across all channels", status: .active, order: 0, targetCount: 3, taskCount: 12, completedTaskCount: 5, createdAt: Date(), updatedAt: Date(), isEncrypted: true),
            MissionProgram(id: UUID(), name: "Sales Enablement", description: "Sales materials and training", status: .active, order: 1, targetCount: 4, taskCount: 12, completedTaskCount: 5, createdAt: Date(), updatedAt: Date(), isEncrypted: true),
            MissionProgram(id: UUID(), name: "Infrastructure & Security", description: "Server migration and audit", status: .onHold, order: 2, targetCount: 3, taskCount: 8, completedTaskCount: 3, createdAt: Date(), updatedAt: Date(), isEncrypted: true),
        ]
    }
}
