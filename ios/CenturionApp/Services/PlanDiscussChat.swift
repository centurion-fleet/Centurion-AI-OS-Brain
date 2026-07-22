import Foundation

/// Framing and parsing for Plan Discuss chats on Sovereign Remote.
/// Keeps a stable conversation tied to a plan id so the user can reopen anytime.
enum PlanDiscussChat {
    static let updateFence = "plan-update"

    struct UpdatePayload: Decodable {
        let plan_id: String
        let title: String?
        let goal: String?
        let steps: [String]?
        let risks: [String]?
        let open_questions: [String]?
        let summary: String?
        let status: String?
    }

    static func frameOutbound(userText: String, plan: PlanArtifact) -> String {
        let stepsBlock = plan.steps.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let risksBlock = plan.risks.isEmpty
            ? "(none listed)"
            : plan.risks.map { "- \($0)" }.joined(separator: "\n")
        let questionsBlock = plan.openQuestions.isEmpty
            ? "(none listed)"
            : plan.openQuestions.map { "- \($0)" }.joined(separator: "\n")

        return """
        [Sovereign Remote — Plan discuss]
        The user is continuing Crypto Chat about this reviewable Plan (not their life Mission).

        Plan ID: \(plan.id.uuidString)
        Title: \(plan.title)
        Status: \(plan.status.rawValue)
        Goal: \(plan.goal.isEmpty ? "(not set)" : plan.goal)
        Steps:
        \(stepsBlock.isEmpty ? "(none yet)" : stepsBlock)
        Risks:
        \(risksBlock)
        Open questions:
        \(questionsBlock)
        Summary: \(plan.summary.isEmpty ? "(none)" : plan.summary)

        Help them refine, proceed guidance, or revise the plan. Do not take irreversible \
        external actions unless they clearly ask you to execute after Proceed.

        If you and the user agree on plan edits, end your reply with a fenced JSON block \
        exactly like this (omit fields you are not changing):

        ```\(updateFence)
        {"plan_id":"\(plan.id.uuidString)","title":"Updated title","goal":"Updated goal","steps":["Step 1"],"risks":[],"open_questions":[],"summary":"Short summary","status":"pending_review"}
        ```

        Allowed status values: pending_review, proceeded, held, adjusted, completed, rejected.

        User message:
        \(userText)
        """
    }

    static func parseUpdate(from response: String) -> UpdatePayload? {
        guard let block = extractUpdateBlock(from: response),
              let data = block.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UpdatePayload.self, from: data)
    }

    static func displayText(strippingUpdateBlockFrom response: String) -> String {
        let open = "```\(updateFence)"
        guard let start = response.range(of: open) else {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = String(response[..<start.lowerBound])
        if let closeStart = response.range(of: "```", range: start.upperBound..<response.endIndex) {
            result += String(response[closeStart.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractUpdateBlock(from response: String) -> String? {
        let open = "```\(updateFence)"
        guard let start = response.range(of: open) else { return nil }
        let afterOpen = response[start.upperBound...]
        guard let close = afterOpen.range(of: "```") else { return nil }
        return String(afterOpen[..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
