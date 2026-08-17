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
    /// Host Low / Medium / High classification (optional for older local plans).
    var risk: PlanRisk?
    var requirements: [String]
    var share: PlanShare
    var templateId: String?
    var outcomeSummary: String?

    enum PlanStatus: String, Codable {
        case pendingReview = "pending_review"
        case proceeded = "proceeded"
        case held = "held"
        case adjusted = "adjusted"
        case completed = "completed"
        case rejected = "rejected"

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
            switch raw {
            case "pending_review", "proposed", "pending":
                self = .pendingReview
            case "proceeded", "in_progress", "active":
                self = .proceeded
            case "held", "paused":
                self = .held
            case "adjusted":
                self = .adjusted
            case "completed":
                self = .completed
            case "rejected":
                self = .rejected
            default:
                self = .pendingReview
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(rawValue)
        }

        var displayLabel: String {
            switch self {
            case .pendingReview: return "Decisions needed"
            case .proceeded: return "In progress"
            case .held: return "On hold"
            case .adjusted: return "Adjusting"
            case .completed: return "Completed"
            case .rejected: return "Rejected"
            }
        }
    }

    enum PlanRisk: String, Codable {
        case low, medium, high

        var displayLabel: String {
            switch self {
            case .low: return "Low risk"
            case .medium: return "Medium risk"
            case .high: return "High risk"
            }
        }
    }

    struct PlanShare: Codable, Equatable {
        var boardId: String?
        var reviewers: [PlanReviewer]
        var comments: [PlanComment]

        init(boardId: String? = nil, reviewers: [PlanReviewer] = [], comments: [PlanComment] = []) {
            self.boardId = boardId
            self.reviewers = reviewers
            self.comments = comments
        }

        enum CodingKeys: String, CodingKey {
            case boardId = "board_id"
            case reviewers, comments
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            boardId = try c.decodeIfPresent(String.self, forKey: .boardId)
            reviewers = try c.decodeIfPresent([PlanReviewer].self, forKey: .reviewers) ?? []
            comments = try c.decodeIfPresent([PlanComment].self, forKey: .comments) ?? []
        }
    }

    struct PlanReviewer: Codable, Equatable, Identifiable {
        var id: String { customerId }
        var customerId: String
        var role: String
        var status: String

        enum CodingKeys: String, CodingKey {
            case customerId = "customer_id"
            case role, status
        }
    }

    struct PlanComment: Codable, Equatable, Identifiable {
        var id: String
        var author: String
        var body: String
        var at: String
    }

    enum CodingKeys: String, CodingKey {
        case id, title, goal, steps, risks, summary, status, risk, requirements, share
        case openQuestions
        case open_questions
        case relatedMission
        case related_mission
        case signalId
        case signal_id
        case createdAt
        case created_at
        case templateId
        case template_id
        case outcomeSummary
        case outcome_summary
    }

    init(
        id: UUID,
        title: String,
        goal: String,
        steps: [String],
        risks: [String],
        openQuestions: [String],
        summary: String,
        relatedMission: String? = nil,
        signalId: String? = nil,
        status: PlanStatus,
        createdAt: Date,
        risk: PlanRisk? = nil,
        requirements: [String] = [],
        share: PlanShare = PlanShare(),
        templateId: String? = nil,
        outcomeSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.steps = steps
        self.risks = risks
        self.openQuestions = openQuestions
        self.summary = summary
        self.relatedMission = relatedMission
        self.signalId = signalId
        self.status = status
        self.createdAt = createdAt
        self.risk = risk
        self.requirements = requirements
        self.share = share
        self.templateId = templateId
        self.outcomeSummary = outcomeSummary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            id = uuid
        } else {
            let raw = try c.decode(String.self, forKey: .id)
            id = UUID(uuidString: raw) ?? UUID()
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled plan"
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        risks = try c.decodeIfPresent([String].self, forKey: .risks) ?? []
        openQuestions = try Self.decodeStringList(c, camel: .openQuestions, snake: .open_questions)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        relatedMission = try Self.decodeOptionalString(c, camel: .relatedMission, snake: .related_mission)
        signalId = try Self.decodeOptionalString(c, camel: .signalId, snake: .signal_id)
        status = try c.decodeIfPresent(PlanStatus.self, forKey: .status) ?? .pendingReview
        if let date = try c.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = date
        } else if let raw = try Self.decodeOptionalString(c, camel: .createdAt, snake: .created_at) {
            createdAt = ISO8601DateFormatter().date(from: raw) ?? Date()
        } else {
            createdAt = Date()
        }
        risk = try c.decodeIfPresent(PlanRisk.self, forKey: .risk)
        requirements = try c.decodeIfPresent([String].self, forKey: .requirements) ?? []
        share = try c.decodeIfPresent(PlanShare.self, forKey: .share) ?? PlanShare()
        templateId = try Self.decodeOptionalString(c, camel: .templateId, snake: .template_id)
        outcomeSummary = try Self.decodeOptionalString(c, camel: .outcomeSummary, snake: .outcome_summary)
    }

    /// Prefer camelCase (iOS) then snake_case (host) without `try` inside `??`.
    private static func decodeStringList(
        _ c: KeyedDecodingContainer<CodingKeys>,
        camel: CodingKeys,
        snake: CodingKeys
    ) throws -> [String] {
        if let value = try c.decodeIfPresent([String].self, forKey: camel) {
            return value
        }
        return try c.decodeIfPresent([String].self, forKey: snake) ?? []
    }

    private static func decodeOptionalString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        camel: CodingKeys,
        snake: CodingKeys
    ) throws -> String? {
        if let value = try c.decodeIfPresent(String.self, forKey: camel) {
            return value
        }
        return try c.decodeIfPresent(String.self, forKey: snake)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(goal, forKey: .goal)
        try c.encode(steps, forKey: .steps)
        try c.encode(risks, forKey: .risks)
        try c.encode(openQuestions, forKey: .openQuestions)
        try c.encode(summary, forKey: .summary)
        try c.encodeIfPresent(relatedMission, forKey: .relatedMission)
        try c.encodeIfPresent(signalId, forKey: .signalId)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(risk, forKey: .risk)
        try c.encode(requirements, forKey: .requirements)
        try c.encode(share, forKey: .share)
        try c.encodeIfPresent(templateId, forKey: .templateId)
        try c.encodeIfPresent(outcomeSummary, forKey: .outcomeSummary)
    }

    /// Payload suitable for host ``plan_put``.
    var hostPayload: [String: Any] {
        var body: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "title": title,
            "goal": goal,
            "steps": steps,
            "risks": risks,
            "open_questions": openQuestions,
            "summary": summary,
            "status": status.rawValue,
            "requirements": requirements,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
        ]
        if let relatedMission { body["related_mission"] = relatedMission }
        if let signalId { body["signal_id"] = signalId }
        if let risk { body["risk"] = risk.rawValue }
        if let templateId { body["template_id"] = templateId }
        if let outcomeSummary { body["outcome_summary"] = outcomeSummary }
        return body
    }

    var markdownContent: String {
        var lines: [String] = ["# \(title)", ""]
        if let risk {
            lines.append("**\(risk.displayLabel)**")
            lines.append("")
        }
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
        if !requirements.isEmpty {
            lines.append("## Requirements")
            for item in requirements {
                lines.append("- \(item)")
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
            title: title.isEmpty ? "Review this mission" : title,
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
        if let risk {
            parts.append(risk.displayLabel)
        }
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
        DecisionOption(label: "Hold", description: "Keep this in Decisions needed for now"),
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
            createdAt: Date().addingTimeInterval(-480),
            risk: .medium
        )
    }

    static func decode(from dictionary: [String: Any]) -> PlanArtifact? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlanArtifact.self, from: data)
    }
}

struct PlanTemplate: Identifiable, Equatable {
    let id: String
    var title: String
    var summary: String
    var goal: String
    var steps: [String]
    var risks: [String]

    static func decode(from dictionary: [String: Any]) -> PlanTemplate? {
        guard let id = dictionary["id"] as? String else { return nil }
        return PlanTemplate(
            id: id,
            title: dictionary["title"] as? String ?? id,
            summary: dictionary["summary"] as? String ?? "",
            goal: dictionary["goal"] as? String ?? "",
            steps: dictionary["steps"] as? [String] ?? [],
            risks: dictionary["risks"] as? [String] ?? []
        )
    }
}
