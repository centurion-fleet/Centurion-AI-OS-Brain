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

/// A Centurion thought — appears in the mission pulse stream
struct CenturionThought: Identifiable {
    let id: UUID
    let text: String
    let type: ThoughtType
    let timestamp: Date
    let relatedTarget: String?     // What target this relates to
    
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
