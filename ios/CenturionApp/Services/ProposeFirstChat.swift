import Foundation

/// Framing and parsing for Chat “Propose first” turns on Sovereign Remote.
/// Host is instructed to draft a plan only (no irreversible action) and return
/// a structured `plan-artifact` fence the phone can render on Home.
enum ProposeFirstChat {
    static let artifactFence = "plan-artifact"

    struct ArtifactPayload: Decodable {
        let title: String?
        let goal: String?
        let steps: [String]?
        let risks: [String]?
        let open_questions: [String]?
        let summary: String?
        let related_mission: String?
    }

    static func frameOutbound(userText: String) -> String {
        """
        [Sovereign AI Remote — Propose first]
        The user wants a plan before any consequential action.

        For this turn only:
        - Draft a concrete plan. Do not implement, send, edit project files, run mutating commands, or take external actions.
        - You may inspect read-only context if needed.
        - Reply briefly in plain language, then end with a fenced JSON block exactly like this:

        ```\(artifactFence)
        {"title":"Short plan title","goal":"What success looks like","steps":["Step 1","Step 2"],"risks":["Risk if any"],"open_questions":["Question if any"],"summary":"One or two sentence summary for Home"}
        ```

        Omit empty arrays. Keep steps actionable and short.

        User message:
        \(userText)
        """
    }

    static func parseArtifact(from response: String) -> PlanArtifact? {
        guard let block = extractArtifactBlock(from: response),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ArtifactPayload.self, from: data) else {
            return nil
        }

        let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = (payload.goal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (payload.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = (payload.steps ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let risks = (payload.risks ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let questions = (payload.open_questions ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let related = payload.related_mission?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedTitle: String
        if !title.isEmpty {
            resolvedTitle = title
        } else if !goal.isEmpty {
            resolvedTitle = String(goal.prefix(72))
        } else {
            resolvedTitle = "Proposed plan"
        }

        return PlanArtifact(
            id: UUID(),
            title: resolvedTitle,
            goal: goal,
            steps: steps,
            risks: risks,
            openQuestions: questions,
            summary: summary.isEmpty ? goal : summary,
            relatedMission: (related?.isEmpty == false) ? related : nil,
            signalId: nil,
            status: .pendingReview,
            createdAt: Date()
        )
    }

    /// Fallback when the model replies without a fence — still surface a reviewable plan.
    static func fallbackArtifact(from response: String, userRequest: String) -> PlanArtifact {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line.hasPrefix("#") { return false }
                if line.hasPrefix("```") { return false }
                return true
            }
            .prefix(8)
            .map { line -> String in
                var s = line
                while let first = s.first, first == "-" || first == "*" || first.isNumber || first == "." || first == " " {
                    s = String(s.dropFirst())
                }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        let titleSeed = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanArtifact(
            id: UUID(),
            title: titleSeed.isEmpty ? "Proposed plan" : "Plan: \(String(titleSeed.prefix(60)))",
            goal: String(trimmed.prefix(240)),
            steps: Array(steps),
            risks: [],
            openQuestions: [],
            summary: String(trimmed.prefix(280)),
            relatedMission: nil,
            signalId: nil,
            status: .pendingReview,
            createdAt: Date()
        )
    }

    static func displayText(strippingArtifactFrom response: String) -> String {
        let open = "```\(artifactFence)"
        guard let start = response.range(of: open) else {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = String(response[..<start.lowerBound])
        if let closeStart = response.range(of: "```", range: start.upperBound..<response.endIndex) {
            result += String(response[closeStart.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractArtifactBlock(from response: String) -> String? {
        let open = "```\(artifactFence)"
        guard let start = response.range(of: open) else { return nil }
        let afterOpen = response[start.upperBound...]
        guard let close = afterOpen.range(of: "```") else { return nil }
        return String(afterOpen[..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
