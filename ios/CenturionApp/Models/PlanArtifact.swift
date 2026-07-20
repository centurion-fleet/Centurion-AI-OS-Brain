import Foundation

/// A reviewable proposal from your Sovereign — not your life Mission.
/// Cursor-style plan-before-act, in calm Remote language.
struct PlanArtifact: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var goal: String
    var steps: [String]
    var risks: [String]
    var openQuestions: [String]
    var summary: String
    var relatedMission: String?
    /// Swarm signal id when this plan came from a collaboration decision.
    var signalId: String?
    var status: PlanStatus
    var createdAt: Date

    enum PlanStatus: String, Codable {
        case pendingReview = "pending_review"
        case proceeded = "proceeded"
        case held = "held"
        case adjusted = "adjusted"

        var displayLabel: String {
            switch self {
            case .pendingReview: return "Needs your review"
            case .proceeded: return "You said proceed"
            case .held: return "On hold"
            case .adjusted: return "Adjusting"
            }
        }
    }

    var markdownContent: String {
        var lines: [String] = ["# \(title)", ""]
        if !goal.isEmpty {
            lines.append("## Goal")
            lines.append(goal)
            lines.append("")
        }
        if !steps.isEmpty {
            lines.append("## Proposed steps")
            for (index, step) in steps.enumerated() {
                lines.append("\(index + 1). \(step)")
            }
            lines.append("")
        }
        if !risks.isEmpty {
            lines.append("## Risks")
            for risk in risks {
                lines.append("- \(risk)")
            }
            lines.append("")
        }
        if !openQuestions.isEmpty {
            lines.append("## Open questions")
            for question in openQuestions {
                lines.append("- \(question)")
            }
            lines.append("")
        }
        if !summary.isEmpty {
            lines.append("## Summary")
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }

    var wordCount: Int {
        max(markdownContent.split(separator: " ").count, 1)
    }

    func asCenturionOutput() -> CenturionOutput {
        CenturionOutput(
            id: id,
            title: title,
            summary: summary.isEmpty ? goal : summary,
            content: markdownContent,
            type: .plan,
            sourceLoop: "Propose first",
            relatedMission: relatedMission,
            createdAt: createdAt,
            wordCount: wordCount,
            filePath: "plan://\(id.uuidString)"
        )
    }

    func asDecisionItem() -> DecisionItem {
        DecisionItem(
            id: id,
            title: title.isEmpty ? "Review this plan" : title,
            context: decisionContext,
            options: Self.reviewOptions,
            generatedBy: "Your Sovereign",
            relatedMission: relatedMission,
            urgency: .today,
            createdAt: createdAt,
            signalId: signalId,
            planId: id,
            kind: .plan
        )
    }

    private var decisionContext: String {
        var parts: [String] = ["Your Sovereign proposes this plan and is waiting for your choice."]
        if !goal.isEmpty {
            parts.append(goal)
        } else if !summary.isEmpty {
            parts.append(summary)
        }
        if !steps.isEmpty {
            let preview = steps.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            parts.append(preview)
            if steps.count > 3 {
                parts.append("…and \(steps.count - 3) more steps.")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    static let reviewOptions: [DecisionOption] = [
        DecisionOption(label: "Proceed", description: "Tell your Sovereign to continue with this plan"),
        DecisionOption(label: "Adjust", description: "Open Crypto Chat to refine the plan"),
        DecisionOption(label: "Hold", description: "Keep this in Needs your choice for now"),
    ]

    static let proposeFirstStandingRule =
        "For consequential work, propose a plan first and wait for my Proceed."

    static func preview() -> PlanArtifact {
        PlanArtifact(
            id: UUID(),
            title: "Q3 compliance-first positioning",
            goal: "Lead Q3 go-to-market with the compliance-first angle before drafting customer messaging.",
            steps: [
                "Confirm the $2.4M segment sizing against last quarter’s CRM export",
                "Draft three messaging pillars for sales enablement",
                "Share a one-page brief for your review before any external send",
            ],
            risks: [
                "Segment sizing may shift after CRM refresh",
                "Sales may prefer the durability narrative",
            ],
            openQuestions: [
                "Should partner decks wait until you approve this angle?",
            ],
            summary: "Your Sovereign proposes leading with compliance-first positioning and pausing external sends until you Proceed.",
            relatedMission: "Q3 Go-to-Market",
            signalId: nil,
            status: .pendingReview,
            createdAt: Date().addingTimeInterval(-480)
        )
    }
}
