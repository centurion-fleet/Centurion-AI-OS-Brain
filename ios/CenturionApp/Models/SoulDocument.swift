import Foundation

/// The Centurion's Soul — AI personality, tone, and rules.
/// Maps to desktop `SOUL.md`; defines how your companion speaks and behaves.
struct SoulDocument: Codable {
    var version: Int = 2
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var personalitySummary: String = ""
    var tone: String = ""
    var communicationStyle: String = ""
    var pushbackStyle: String = ""
    var alwaysDo: [String] = []
    var neverDo: [String] = []
    var uncertaintyStyle: String = ""
    var responseLength: String = ""

    var isValid: Bool {
        !personalitySummary.isEmpty
            || !tone.isEmpty
            || !communicationStyle.isEmpty
            || !alwaysDo.isEmpty
            || !neverDo.isEmpty
    }

    static func preview() -> SoulDocument {
        var soul = SoulDocument()
        soul.personalitySummary = "A direct, warm companion who leads with headlines and respects my time."
        soul.tone = "Direct and warm"
        soul.communicationStyle = "Headlines first, details on request. No filler."
        soul.pushbackStyle = "Push back when I'm rushing past something important."
        soul.alwaysDo = ["Summarise before detail", "Flag risks early"]
        soul.neverDo = ["Soften bad news", "Use jargon without explaining it"]
        soul.uncertaintyStyle = "Say what you know, what you don't, and what you'd check next."
        soul.responseLength = "Brief by default, thorough when I ask"
        return soul
    }
}

/// Legacy human-profile Soul format — used only for one-time migration.
struct LegacySoulDocument: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var yourStory: String = ""
    var yourValues: [String] = []
    var yourPersonality: String = ""
    var yourStrengths: [String] = []
    var communicationStyle: String = ""
    var missionStatement: String = ""
    var whyThisMission: String = ""
    var vitalStatName: String = ""
    var vitalStatCurrent: Double = 0
    var vitalStatTarget: Double = 0
    var workStyle: String = ""
    var decisionStyle: String = ""
    var feedbackPreference: String = ""
    var communicationChannels: [String] = []
    var preferredTone: String = ""
    var timezone: String = ""
    var workHours: String = ""
    var goals: [String] = []
    var challenges: [String] = []
    var areasOfFocus: [String] = []
    var delegatePreferences: [String] = []
    var keyRelationships: [String] = []
    var currentProjects: [String] = []
    var toolsYouUse: [String] = []
}

/// A single Soul Interview question — shapes the Centurion's AI personality.
struct SoulQuestion: Identifiable {
    let id = UUID()
    let stage: SoulStage
    let question: String
    let hint: String
    let placeholder: String
    let inputType: SoulInputType

    enum SoulStage: String, CaseIterable {
        case voice = "Voice"
        case rules = "Rules"
        case boundaries = "Boundaries"
        case complete = "Complete"
    }

    enum SoulInputType {
        case text
        case multiline
        case tags
    }

    static func allQuestions() -> [SoulQuestion] {
        [
            SoulQuestion(
                stage: .voice,
                question: "In one or two sentences, who is your Centurion?",
                hint: "Describe the companion you want — not yourself.",
                placeholder: "e.g. A calm, direct advisor who respects my time",
                inputType: .multiline
            ),
            SoulQuestion(
                stage: .voice,
                question: "What tone should your Centurion use?",
                hint: "Warm, direct, formal, casual — or a mix.",
                placeholder: "e.g. Direct and warm, never stiff",
                inputType: .text
            ),
            SoulQuestion(
                stage: .voice,
                question: "How should your Centurion speak to you?",
                hint: "Headlines first? Detailed? Gentle? Match your preference.",
                placeholder: "e.g. Lead with the answer, then offer detail if I want it",
                inputType: .multiline
            ),
            SoulQuestion(
                stage: .voice,
                question: "How long should responses usually be?",
                hint: "Brief summaries or thorough explanations by default.",
                placeholder: "e.g. Brief by default, thorough when I ask",
                inputType: .text
            ),
            SoulQuestion(
                stage: .rules,
                question: "What should your Centurion always do?",
                hint: "Habits and behaviours you want every time.",
                placeholder: "e.g. Flag risks early, summarise before detail",
                inputType: .tags
            ),
            SoulQuestion(
                stage: .boundaries,
                question: "What should your Centurion never do?",
                hint: "Hard limits — things that would break trust.",
                placeholder: "e.g. Soften bad news, guess when unsure",
                inputType: .tags
            ),
            SoulQuestion(
                stage: .boundaries,
                question: "When should your Centurion push back on you?",
                hint: "Healthy disagreement keeps you on course.",
                placeholder: "e.g. When I'm skipping something important",
                inputType: .multiline
            ),
            SoulQuestion(
                stage: .boundaries,
                question: "How should your Centurion handle uncertainty?",
                hint: "What to do when it doesn't know the answer.",
                placeholder: "e.g. Say what it knows, what it doesn't, and what to check next",
                inputType: .multiline
            ),
        ]
    }
}

/// Human context questions — folded into Mission, not Soul.
struct HumanContextQuestion: Identifiable {
    let id = UUID()
    let stage: String
    let question: String
    let hint: String
    let placeholder: String
    let inputType: SoulQuestion.SoulInputType

    static func allQuestions() -> [HumanContextQuestion] {
        [
            HumanContextQuestion(stage: "Your Story", question: "What's one sentence that describes who you are?", hint: "Not your job title. Who you actually are.", placeholder: "e.g. A founder who builds things that last", inputType: .multiline),
            HumanContextQuestion(stage: "Your Story", question: "Tell me your story — how did you get here?", hint: "What shaped you? What moments defined your path?", placeholder: "I started...", inputType: .multiline),
            HumanContextQuestion(stage: "Your Values", question: "What are the core values that guide you?", hint: "The principles you won't compromise on.", placeholder: "e.g. Reliability, Directness, Craftsmanship", inputType: .tags),
            HumanContextQuestion(stage: "Your World", question: "Who are the key people in your world?", hint: "Partners, team, mentors — the people who matter.", placeholder: "e.g. Debbie (GM), Steve (Sales)", inputType: .tags),
            HumanContextQuestion(stage: "How You Work", question: "How do you work best?", hint: "Solo or team? Fast or methodical? Async or real-time?", placeholder: "e.g. Fast-moving, delegate-heavy", inputType: .multiline),
            HumanContextQuestion(stage: "How You Work", question: "What timezone are you in, and when do you work?", hint: "", placeholder: "e.g. AEST, 6am—6pm", inputType: .text),
            HumanContextQuestion(stage: "What You Need", question: "What are your biggest challenges right now?", hint: "What's in your way?", placeholder: "e.g. Finding reliable talent", inputType: .tags),
            HumanContextQuestion(stage: "What You Need", question: "What do you want your Centurion to handle for you?", hint: "What would free up your time?", placeholder: "e.g. Market research, drafting", inputType: .tags),
            HumanContextQuestion(stage: "Your World", question: "What tools do you use every day?", hint: "Apps, platforms, anything you live in.", placeholder: "e.g. Telegram, Email, X", inputType: .tags),
        ]
    }
}
