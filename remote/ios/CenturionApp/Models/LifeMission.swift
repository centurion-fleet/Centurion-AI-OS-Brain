import Foundation

/// Personal context about the human — story, values, people, and work habits.
/// Lives under Mission; distinct from Soul (AI personality).
struct HumanProfile: Codable {
    var whyThisMission: String = ""
    var areasOfFocus: [String] = []
    var yourStory: String = ""
    var yourValues: [String] = []
    var yourPersonality: String = ""
    var yourStrengths: [String] = []
    var vitalStatName: String = ""
    var vitalStatCurrent: Double = 0
    var vitalStatTarget: Double = 0
    var workStyle: String = ""
    var decisionStyle: String = ""
    var timezone: String = ""
    var workHours: String = ""
    var challenges: [String] = []
    var keyRelationships: [String] = []
    var toolsYouUse: [String] = []
    var delegatePreferences: [String] = []
    var currentProjects: [String] = []

    var hasContext: Bool {
        !yourStory.isEmpty
            || !yourValues.isEmpty
            || !keyRelationships.isEmpty
            || !toolsYouUse.isEmpty
            || !challenges.isEmpty
            || !delegatePreferences.isEmpty
    }
}

/// The user's life mission — purpose, commitments, and personal context.
struct LifeMission: Identifiable, Codable {
    let id: UUID
    var statement: String
    var targets: [LifeMissionTarget]
    var profile: HumanProfile

    init(id: UUID, statement: String, targets: [LifeMissionTarget], profile: HumanProfile = HumanProfile()) {
        self.id = id
        self.statement = statement
        self.targets = targets
        self.profile = profile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        statement = try container.decode(String.self, forKey: .statement)
        targets = try container.decode([LifeMissionTarget].self, forKey: .targets)
        profile = try container.decodeIfPresent(HumanProfile.self, forKey: .profile) ?? HumanProfile()
    }

    static func preview() -> LifeMission {
        var profile = HumanProfile()
        profile.whyThisMission = "Australian mining and construction deserve world-class equipment built locally."
        profile.yourStory = "Founder building Australia's leading OEM lighting tower manufacturer."
        profile.yourValues = ["Reliability", "Directness", "Craftsmanship"]
        return LifeMission(
            id: UUID(),
            statement: "Build Australia's leading OEM lighting tower provider",
            targets: LifeMissionTarget.previewTargets(),
            profile: profile
        )
    }
}

/// The phases of a Sovereign mission loop — from discovery through to verification.
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

/// What the Sovereign is doing RIGHT NOW — the live loop.
/// This is the primary UI. The human watches this.
struct LiveActivity: Identifiable {
    let id: UUID
    let phase: LoopPhase
    let summary: String
    let detail: String
    let progress: Double
    let startedAt: Date
    let subAgents: [SubAgentActivity]
    let estimatedCompletion: TimeInterval?   // seconds remaining
}

/// A sub-agent working on part of a loop
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

/// A completed loop — the portfolio of wins.
/// This is what humans show other humans to say "look what my Centurion did."
struct CompletedLoop: Identifiable {
    let id: UUID
    let summary: String
    let detail: String
    let result: String
    let impact: String           // What this means for the mission
    let agentCount: Int
    let duration: TimeInterval   // How long the loop took
    let completedAt: Date
    let subAgentSummary: [String] // What each sub-agent contributed
    let relatedMission: String   // Which mission area this serves
    
    static func preview() -> [CompletedLoop] {
        [
            CompletedLoop(
                id: UUID(),
                summary: "Market positioning analysis complete",
                detail: "Analysed 14 competitors across 3 market segments. Identified 3 underserved positioning angles with high purchase intent.",
                result: "Positioning white paper saved to /outputs/positioning",
                impact: "Enables Q3 Go-to-Market to target an underserved $2.4M segment",
                agentCount: 3,
                duration: 420,
                completedAt: Date().addingTimeInterval(-900),
                subAgentSummary: [
                    "Scout found 14 competitors, scored by overlap and share of voice",
                    "Analyst cross-referenced customer pain points with competitor gaps",
                    "Strategist synthesised 3 positioning angles with go-to-market recommendations"
                ],
                relatedMission: "Q3 Go-to-Market"
            ),
            CompletedLoop(
                id: UUID(),
                summary: "Customer sentiment analysis — 127 reviews processed",
                detail: "Scraped and analysed 127 recent customer reviews across G2, Capterra, and Reddit. Extracted 9 feature requests and 4 recurring complaints.",
                result: "Feature priority list with severity scores saved",
                impact: "Product team can prioritise roadmap against real customer pain",
                agentCount: 2,
                duration: 310,
                completedAt: Date().addingTimeInterval(-3600),
                subAgentSummary: [
                    "Collector gathered 127 reviews from 3 platforms",
                    "Analyst categorised by theme, sentiment, and frequency"
                ],
                relatedMission: "Product Development"
            ),
            CompletedLoop(
                id: UUID(),
                summary: "Weekly content brief generated",
                detail: "Researched trending topics in the industry. Cross-referenced against existing content to find gaps. Wrote 3 briefs with keyword targets.",
                result: "3 content briefs ready for the writer",
                impact: "Keeps content calendar full with high-impact topics",
                agentCount: 2,
                duration: 180,
                completedAt: Date().addingTimeInterval(-7200),
                subAgentSummary: [
                    "Scout found 12 trending topics across X, LinkedIn, and industry blogs",
                    "Writer briefed each topic with angle, target keywords, and source links"
                ],
                relatedMission: "Content Strategy"
            ),
        ]
    }
}

/// Something that needs human attention.
/// This is the ONLY thing the human needs to act on.
struct DecisionItem: Identifiable {
    let id: UUID
    let title: String
    let context: String
    let options: [DecisionOption]
    let generatedBy: String     // Which agent generated this
    let relatedMission: String?
    let urgency: Urgency
    let createdAt: Date
    /// Brain swarm signal id when this decision maps to `swarm_resolve_signal`.
    let signalId: String?
    /// Local PlanArtifact id when this is a plan review.
    let planId: UUID?
    let kind: Kind

    enum Kind: String {
        case general
        case plan
    }

    enum Urgency: String {
        case now = "Now"
        case today = "Today"
        case thisWeek = "This Week"
        case whenever = "Whenever"
    }

    init(
        id: UUID,
        title: String,
        context: String,
        options: [DecisionOption],
        generatedBy: String,
        relatedMission: String?,
        urgency: Urgency,
        createdAt: Date,
        signalId: String? = nil,
        planId: UUID? = nil,
        kind: Kind = .general
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.options = options
        self.generatedBy = generatedBy
        self.relatedMission = relatedMission
        self.urgency = urgency
        self.createdAt = createdAt
        self.signalId = signalId
        self.planId = planId
        self.kind = kind
    }

    static func preview() -> [DecisionItem] {
        let plan = PlanArtifact.preview()
        return [plan.asDecisionItem()]
    }
}

struct DecisionOption: Identifiable {
    let id = UUID()
    let label: String
    let description: String
}

/// A Sovereign thought — appears in the Sovereign Remote stream.
struct CenturionThought: Identifiable {
    let id: UUID
    let text: String
    let type: ThoughtType
    let timestamp: Date
    let relatedMission: String?
    
    enum ThoughtType: String {
        case alert = "Alert"
        case insight = "Insight"
        case progress = "Progress"
        case suggestion = "Suggestion"
        case question = "Question"
        case win = "Win"              // Something awesome completed
        
        var icon: String {
            switch self {
            case .alert: return "exclamationmark.triangle.fill"
            case .insight: return "lightbulb.fill"
            case .progress: return "arrow.up.right"
            case .suggestion: return "hand.raised.fill"
            case .question: return "questionmark.circle.fill"
            case .win: return "star.fill"
            }
        }
    }
}

extension CenturionThought {
    static func preview() -> [CenturionThought] {
        [
            CenturionThought(id: UUID(), text: "Market positioning analysis complete — 3 underserved angles identified.", type: .win, timestamp: Date().addingTimeInterval(-900), relatedMission: "Q3 Go-to-Market"),
            CenturionThought(id: UUID(), text: "Customer sentiment analysis shows 4 recurring complaints about onboarding.", type: .alert, timestamp: Date().addingTimeInterval(-1800), relatedMission: "Product Development"),
            CenturionThought(id: UUID(), text: "I suggest we prioritise the compliance angle — it reaches a $2.4M unserved segment.", type: .suggestion, timestamp: Date().addingTimeInterval(-3600), relatedMission: "Q3 Go-to-Market"),
            CenturionThought(id: UUID(), text: "Content brief for next week is ready. Topic: 'The Hidden Cost of Enterprise AI.'", type: .progress, timestamp: Date().addingTimeInterval(-7200), relatedMission: "Content Strategy"),
        ]
    }
}

// MARK: - Live Activity Preview

extension LiveActivity {
    static func preview() -> LiveActivity {
        LiveActivity(
            id: UUID(),
            phase: .executing,
            summary: "Researching Q3 market positioning",
            detail: "Analysing 14 competitors across 3 market segments to find underserved positioning angles with high purchase intent",
            progress: 0.72,
            startedAt: Date().addingTimeInterval(-420),
            subAgents: [
                SubAgentActivity(id: UUID(), name: "Scout", role: "Market Research", status: .active, summary: "Scanning competitor sites, G2 reviews, and industry forums for positioning gaps", progress: 0.85),
                SubAgentActivity(id: UUID(), name: "Analyst", role: "Data Analysis", status: .active, summary: "Cross-referencing customer pain points with competitor feature sets", progress: 0.58),
                SubAgentActivity(id: UUID(), name: "Strategist", role: "Synthesis", status: .waiting, summary: "Awaiting Scout and Analyst outputs before drafting positioning recommendations", progress: 0.0),
            ],
            estimatedCompletion: 180
        )
    }
}

/// A document the Sovereign has created — research, content, analysis, plans.
/// These are surfaced in the Pulse tab's OUTPUTS section and as inline cards in Chat.
struct CenturionOutput: Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let content: String             // The full document body (markdown)
    let type: OutputType
    let sourceLoop: String          // Which loop created this
    let relatedMission: String?
    let createdAt: Date
    let wordCount: Int
    let filePath: String            // Where it lives on the Sovereign

    enum OutputType: String, CaseIterable {
        case research = "Research"
        case analysis = "Analysis"
        case content = "Content"
        case plan = "Plan"
        case report = "Report"
        case code = "Code"

        var icon: String {
            switch self {
            case .research: return "magnifyingglass"
            case .analysis: return "chart.bar.fill"
            case .content: return "doc.text.fill"
            case .plan: return "list.clipboard"
            case .report: return "doc.richtext"
            case .code: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    static func preview() -> [CenturionOutput] {
        [
            PlanArtifact.preview().asCenturionOutput(),
            CenturionOutput(
                id: UUID(),
                title: "Q3 Market Positioning Analysis",
                summary: "Identified 3 underserved positioning angles across 14 competitors. Includes recommended messaging pillars and target segments.",
                content: "# Q3 Market Positioning Analysis\n\n## Executive Summary\n\nAnalysed 14 competitors across 3 market segments. Found 3 underserved positioning angles with high purchase intent.\n\n## Key Findings\n\n1. **The Compliance-First Approach** — $2.4M unserved segment. No competitor owns this.\n2. **The Durability Narrative** — $1.8M segment. Two competitors, but weak messaging.\n3. **The Australian-Made Story** — $1.2M segment. Growing 15% YoY.\n\n## Recommended Positioning\n\n**Lead with Compliance.** It addresses the #1 pain point for mining and construction buyers and has zero competitive overlap.",
                type: .research,
                sourceLoop: "Market Research",
                relatedMission: "Q3 Go-to-Market",
                createdAt: Date().addingTimeInterval(-3600),
                wordCount: 1240,
                filePath: "/outputs/positioning/analysis.md"
            ),
            CenturionOutput(
                id: UUID(),
                title: "Customer Sentiment Report",
                summary: "Processed 127 customer reviews. Extracted 9 feature requests and 4 recurring complaints with severity scoring.",
                content: "# Customer Sentiment Analysis\n\n## Overview\n\nProcessed 127 reviews from G2, Capterra, and Reddit.\n\n## Top Feature Requests\n\n1. **Mobile dashboard** — requested 23 times\n2. **API access** — requested 18 times\n3. **Custom reporting** — requested 14 times\n\n## Top Complaints\n\n1. **Onboarding complexity** — severity: high, frequency: 31%\n2. **Integration limitations** — severity: medium, frequency: 22%",
                type: .analysis,
                sourceLoop: "Sentiment Analysis",
                relatedMission: "Product Development",
                createdAt: Date().addingTimeInterval(-7200),
                wordCount: 890,
                filePath: "/outputs/sentiment/report.md"
            ),
            CenturionOutput(
                id: UUID(),
                title: "Weekly Content Brief — The Hidden Cost of Enterprise AI",
                summary: "Full content brief with keyword targets, outline, and source links for the writer.",
                content: "# Content Brief: The Hidden Cost of Enterprise AI\n\n## Target Keywords\n- enterprise AI cost, AI ROI, private AI vs public AI\n\n## Angle\n\nMost enterprises don't realise that public AI APIs cost 3x more than private deployment at scale.\n\n## Outline\n1. The sticker shock story\n2. Hidden costs: compliance, data egress, retraining\n3. The private AI alternative\n4. Case study: 60% savings with on-premise deployment",
                type: .content,
                sourceLoop: "Content Strategy",
                relatedMission: "Content Strategy",
                createdAt: Date().addingTimeInterval(-14400),
                wordCount: 450,
                filePath: "/outputs/content/weekly-brief-12.md"
            ),
        ]
    }
}


// MARK: - Life Mission Targets (high-level aspirations — distinct from program targets in MissionProject)
struct LifeMissionTarget: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    
    static func previewTargets() -> [LifeMissionTarget] {
        [
            LifeMissionTarget(id: UUID(), title: "Build Sovereign", description: "Create the world's most personal AI companion"),
            LifeMissionTarget(id: UUID(), title: "Live with Purpose", description: "Every day aligned with my deeper mission"),
            LifeMissionTarget(id: UUID(), title: "Help Others Find Their Mission", description: "Enable more people to live meaningful lives")
        ]
    }
}
