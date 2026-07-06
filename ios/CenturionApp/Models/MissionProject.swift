import Foundation

/// A Mission Control project — portfolio of targets and tasks
struct MissionProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var status: ProjectStatus
    var targetCount: Int
    var taskCount: Int
    var completedTaskCount: Int
    var createdAt: Date
    var updatedAt: Date
    var isEncrypted: Bool
    
    enum ProjectStatus: String, Codable, CaseIterable {
        case active = "Active"
        case onHold = "On Hold"
        case completed = "Completed"
        case archived = "Archived"
        
        var icon: String {
            switch self {
            case .active: return "play.circle.fill"
            case .onHold: return "pause.circle.fill"
            case .completed: return "checkmark.circle.fill"
            case .archived: return "archivebox.fill"
            }
        }
        
        var color: String {
            switch self {
            case .active: return "green"
            case .onHold: return "orange"
            case .completed: return "blue"
            case .archived: return "gray"
            }
        }
    }
}

/// A target within a mission project
struct MissionTarget: Identifiable, Codable, Equatable {
    let id: UUID
    let projectId: UUID
    var title: String
    var description: String
    var status: TargetStatus
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

/// A task within a target
struct MissionTask: Identifiable, Codable, Equatable {
    let id: UUID
    let targetId: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var assignedTo: String?
    var createdAt: Date
    
    enum TaskStatus: String, Codable, CaseIterable {
        case todo = "To Do"
        case inProgress = "In Progress"
        case done = "Done"
    }
}

/// Preview data for development
extension MissionProject {
    static func preview() -> [MissionProject] {
        let tasks = [
            MissionTask(id: UUID(), targetId: UUID(), title: "Research market positioning", description: "Analyse competitive landscape", status: .done, createdAt: Date()),
            MissionTask(id: UUID(), targetId: UUID(), title: "Draft messaging framework", description: "Core narrative and key messages", status: .inProgress, createdAt: Date()),
            MissionTask(id: UUID(), targetId: UUID(), title: "Design visual assets", description: "Brand deck and one-pager", status: .todo, createdAt: Date()),
        ]
        
        let targets = [
            MissionTarget(id: UUID(), projectId: UUID(), title: "Q3 Go-to-Market", description: "Launch campaign for new product line", status: .active, tasks: tasks, createdAt: Date()),
            MissionTarget(id: UUID(), projectId: UUID(), title: "Partner Onboarding", description: "Onboard first 5 integration partners", status: .backlog, tasks: [], createdAt: Date()),
        ]
        
        return [
            MissionProject(id: UUID(), name: "Product Launch", description: "Q3 2026 product launch across all channels", status: .active, targetCount: 2, taskCount: 3, completedTaskCount: 1, createdAt: Date(), updatedAt: Date(), isEncrypted: true),
            MissionProject(id: UUID(), name: "Sales Enablement", description: "Sales materials, playbooks, and training", status: .active, targetCount: 4, taskCount: 12, completedTaskCount: 5, createdAt: Date(), updatedAt: Date(), isEncrypted: true),
            MissionProject(id: UUID(), name: "Infrastructure", description: "Server migration and security audit", status: .onHold, targetCount: 3, taskCount: 8, completedTaskCount: 3, createdAt: Date(), updatedAt: Date(), isEncrypted: true),
        ]
    }
}
