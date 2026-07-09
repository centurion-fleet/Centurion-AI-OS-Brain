import Foundation

/// The user's life mission — the highest level of focus.
/// This is what "living your mission" means.
struct LifeMission: Identifiable, Codable {
    let id: UUID
    var statement: String           // "Live your personal mission"
    var vitalStatName: String       // What's the one number?
    var vitalStatCurrent: Double
    var vitalStatTarget: Double
    var vitalStatUnit: String       // "%", "$", "tasks"
    
    var vitalProgress: Double {
        guard vitalStatTarget > 0 else { return 0 }
        return min(vitalStatCurrent / vitalStatTarget, 1.0)
    }
    
    static func preview() -> LifeMission {
        LifeMission(
            id: UUID(),
            statement: "Build Australia's leading OEM lighting tower provider",
            vitalStatName: "Revenue Target",
            vitalStatCurrent: 1_870_000,
            vitalStatTarget: 2_500_000,
            vitalStatUnit: "$"
        )
    }
}

/// AI-speed activity — what the Centurion is doing right now.
/// This updates at the speed of thought, not the speed of human work.
struct CenturionActivity: Identifiable {
    let id: UUID
    let phase: LoopPhase
    let summary: String
    let detail: String
    let progress: Double          // 0.0 to 1.0
    let startedAt: Date
    let agentCount: Int           // How many sub-agents are involved
    let subAgents: [SubAgentActivity]
    
    enum LoopPhase: String, CaseIterable {
        case discovering = "Discovering"
        case planning = "Planning"
        case executing = "Executing"
        case verifying = "Verifying"
        case idle = "Idle"
        
        var icon: String {
            switch self {
            case .discovering: return "magnifyingglass"
            case .planning: return "map"
            case .executing: return "bolt.fill"
            case .verifying: return "checkmark.shield.fill"
            case .idle: return "pause.circle"
            }
        }
    }
}

/// A sub-agent working on part of a mission loop
struct SubAgentActivity: Identifiable {
    let id: UUID
    let name: String
    let role: String
    let status: SubAgentStatus
    let summary: String
    let progress: Double
    
    enum SubAgentStatus: String {
        case active = "Active"
        case completed = "Completed"
        case waiting = "Waiting"
        case error = "Error"
        
        var icon: String {
            switch self {
            case .active: return "arrow.triangle.2.circlepath"
            case .completed: return "checkmark.circle.fill"
            case .waiting: return "hourglass"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
    }
}

/// A Centurion thought — insights, alerts, and suggestions from the AI.
struct CenturionThought: Identifiable {
    let id: UUID
    let text: String
    let type: ThoughtType
    let timestamp: Date
    let relatedTarget: String?
    let phase: LoopPhase?        // Which loop phase generated this thought
    
    enum ThoughtType: String {
        case alert = "Alert"
        case insight = "Insight"
        case progress = "Progress"
        case suggestion = "Suggestion"
        case question = "Question"
        
        var icon: String {
            switch self {
            case .alert: return "exclamationmark.triangle.fill"
            case .insight: return "lightbulb.fill"
            case .progress: return "arrow.up.right"
            case .suggestion: return "hand.raised.fill"
            case .question: return "questionmark.circle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .alert: return "orange"
            case .insight: return "amber"
            case .progress: return "green"
            case .suggestion: return "blue"
            case .question: return "secondary"
            }
        }
    }
}

/// A focus action — the few things the human should do today
struct FocusAction: Identifiable {
    let id: UUID
    var title: String
    var isDone: Bool
    var targetName: String
    
    static func preview() -> [FocusAction] {
        [
            FocusAction(id: UUID(), title: "Review Q3 budget allocation", isDone: false, targetName: "Q3 Go-to-Market"),
            FocusAction(id: UUID(), title: "Approve partner onboarding terms", isDone: false, targetName: "Partner Onboarding"),
            FocusAction(id: UUID(), title: "Sign off on messaging framework", isDone: true, targetName: "Content Strategy"),
        ]
    }
}

// MARK: - Preview Data for AI-Speed Activity

extension CenturionActivity {
    static func preview() -> CenturionActivity {
        CenturionActivity(
            id: UUID(),
            phase: .executing,
            summary: "Researching market opportunities",
            detail: "Analysing competitor pricing, customer forums, and search trends to identify content gaps for Q3 Go-to-Market",
            progress: 0.65,
            startedAt: Date().addingTimeInterval(-180),
            agentCount: 2,
            subAgents: [
                SubAgentActivity(
                    id: UUID(),
                    name: "Scout",
                    role: "Market Research",
                    status: .active,
                    summary: "Scanning Reddit, competitor sites, and search trends for Q3 positioning opportunities",
                    progress: 0.72
                ),
                SubAgentActivity(
                    id: UUID(),
                    name: "Analyst",
                    role: "Data Analysis",
                    status: .active,
                    summary: "Cross-referencing customer feedback with competitor moves to find gaps",
                    progress: 0.48
                ),
            ]
        )
    }
}
