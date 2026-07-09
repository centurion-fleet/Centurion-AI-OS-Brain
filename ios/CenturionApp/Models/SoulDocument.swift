import Foundation

/// The Soul Document — who you are, what you're building, how you want to work.
/// This is what makes a Centurion *yours*. Completed during the Soul Interview
/// before the hardware even arrives, and editable anytime.
///
/// The Soul is shareable — humans show it to other humans to demonstrate
/// how deeply their Centurion knows them.
struct SoulDocument: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Who You Are
    var yourStory: String = ""
    var yourValues: [String] = []
    var yourPersonality: String = ""       // How you'd describe yourself
    var yourStrengths: [String] = []
    var communicationStyle: String = ""

    // MARK: - Your Mission
    var missionStatement: String = ""      // "Live your personal mission"
    var whyThisMission: String = ""        // Why this matters to you
    var vitalStatName: String = ""         // The one number
    var vitalStatCurrent: Double = 0
    var vitalStatTarget: Double = 0

    // MARK: - How You Work
    var workStyle: String = ""             // Solo, team, async, synchronous
    var decisionStyle: String = ""         // Data-driven, intuitive, consensus
    var feedbackPreference: String = ""    // Direct, gentle, frequent, summary
    var communicationChannels: [String] = []
    var preferredTone: String = ""         // Direct, warm, formal, casual
    var timezone: String = ""
    var workHours: String = ""

    // MARK: - What You Want Help With
    var goals: [String] = []
    var challenges: [String] = []
    var areasOfFocus: [String] = []
    var delegatePreferences: [String] = [] // What you want the AI to handle

    // MARK: - Your World
    var keyRelationships: [String] = []    // Partners, team, mentors
    var currentProjects: [String] = []
    var toolsYouUse: [String] = []

    var isValid: Bool {
        !missionStatement.isEmpty && !yourStory.isEmpty
    }

    static func preview() -> SoulDocument {
        var soul = SoulDocument()
        soul.yourStory = "I'm a founder building Australia's leading OEM lighting tower manufacturer. Started from nothing, now supplying mining and construction across the country. I believe in rugged reliability — in hardware and in people."
        soul.yourValues = ["Reliability", "Directness", "Craftsmanship", "Loyalty", "Progress"]
        soul.yourPersonality = "Direct, pragmatic, impatient with bullshit. I trust people who deliver. I value straight talk over polished conversation."
        soul.yourStrengths = ["Strategic thinking", "Building relationships", "Seeing the market", "Making decisions"]
        soul.communicationStyle = "Direct and concise. Say what you mean. Don't waste words."
        soul.missionStatement = "Build Australia's leading OEM lighting tower provider"
        soul.whyThisMission = "Australian mining and construction deserve world-class equipment built by Australians, not imported from halfway around the world."
        soul.vitalStatName = "Revenue Target"
        soul.vitalStatCurrent = 1870000
        soul.vitalStatTarget = 2500000
        soul.workStyle = "Fast-moving, delegate-heavy. I want to know the headline, not the details."
        soul.decisionStyle = "Data-informed but gut-led. Show me the numbers, then tell me what you recommend."
        soul.feedbackPreference = "Direct. Don't soften it. I'd rather hear bad news fast than good news late."
        soul.preferredTone = "Direct and warm. Professional but not formal. We're building something."
        soul.timezone = "AEST (UTC+10)"
        soul.workHours = "6am — 6pm, but I check in evenings"
        soul.goals = ["Hit $2.5M revenue", "Expand into Queensland mining", "Build a team I can trust"]
        soul.challenges = ["Finding reliable talent", "Managing cashflow through growth", "Balancing founder time"]
        soul.areasOfFocus = ["Sales & partnerships", "Product quality", "Team culture"]
        soul.delegatePreferences = ["Market research", "Competitor analysis", "Content creation", "Data analysis", "Drafting communications"]
        soul.keyRelationships = ["Debbie (GM) — runs operations", "Steve — head of sales", "Miki — product development"]
        soul.currentProjects = ["Q3 Go-to-Market", "Sales Enablement", "Infrastructure & Security"]
        soul.toolsYouUse = ["Telegram", "Email", "X", "LinkedIn"]
        return soul
    }
}

/// A single interview question — the Soul Interview is a guided conversation
/// that builds the Soul Document step by step.
struct SoulQuestion: Identifiable {
    let id = UUID()
    let stage: SoulStage
    let question: String
    let hint: String
    let placeholder: String
    let inputType: SoulInputType

    enum SoulStage: String, CaseIterable {
        case welcome = "Welcome"
        case yourStory = "Your Story"
        case yourValues = "Your Values"
        case yourMission = "Your Mission"
        case howYouWork = "How You Work"
        case whatYouNeed = "What You Need"
        case yourWorld = "Your World"
        case complete = "Complete"
    }

    enum SoulInputType {
        case text            // Free text
        case multiline       // Long text
        case tags            // List of tags
        case number          // Numeric input
    }

    static func allQuestions() -> [SoulQuestion] {
        [
            SoulQuestion(stage: .welcome, question: "What's one sentence that describes who you are?", hint: "Not your job title. Who you actually are.", placeholder: "e.g. A founder who builds things that last", inputType: .multiline),
            SoulQuestion(stage: .yourStory, question: "Tell me your story — how did you get here?", hint: "What shaped you? What moments defined your path?", placeholder: "I started...", inputType: .multiline),
            SoulQuestion(stage: .yourValues, question: "What are the core values that guide you?", hint: "The principles you won't compromise on.", placeholder: "e.g. Reliability, Directness, Craftsmanship", inputType: .tags),
            SoulQuestion(stage: .yourMission, question: "What is your mission? The one thing you're building.", hint: "This becomes your life mission statement.", placeholder: "e.g. Build Australia's leading...", inputType: .multiline),
            SoulQuestion(stage: .yourMission, question: "Why does this mission matter to you?", hint: "Not the business case. The personal why.", placeholder: "Because...", inputType: .multiline),
            SoulQuestion(stage: .yourMission, question: "What's the one number that tells you if you're winning?", hint: "Revenue? Users? Impact? Pick one.", placeholder: "e.g. Revenue, Customers, Projects", inputType: .text),
            SoulQuestion(stage: .yourMission, question: "What's your current number, and what's your target?", hint: "", placeholder: "", inputType: .number),
            SoulQuestion(stage: .howYouWork, question: "How do you work best?", hint: "Solo or team? Fast or methodical? Async or real-time?", placeholder: "e.g. Fast-moving, delegate-heavy", inputType: .multiline),
            SoulQuestion(stage: .howYouWork, question: "How should the Centurion communicate with you?", hint: "Direct or gentle? Detailed or summarised? Formal or casual?", placeholder: "e.g. Direct and concise, headlines first", inputType: .multiline),
            SoulQuestion(stage: .howYouWork, question: "What timezone are you in, and when do you work?", hint: "", placeholder: "e.g. AEST, 6am—6pm", inputType: .text),
            SoulQuestion(stage: .whatYouNeed, question: "What are your biggest goals right now?", hint: "The things that would change everything if you achieved them.", placeholder: "e.g. Hit $2.5M revenue", inputType: .tags),
            SoulQuestion(stage: .whatYouNeed, question: "What are your biggest challenges?", hint: "What's in your way?", placeholder: "e.g. Finding reliable talent", inputType: .tags),
            SoulQuestion(stage: .whatYouNeed, question: "What do you want the Centurion to handle for you?", hint: "What would free up your time?", placeholder: "e.g. Market research, drafting", inputType: .tags),
            SoulQuestion(stage: .yourWorld, question: "Who are the key people in your world?", hint: "Partners, team, mentors — the people who matter.", placeholder: "e.g. Debbie (GM), Steve (Sales)", inputType: .tags),
            SoulQuestion(stage: .yourWorld, question: "What tools do you use every day?", hint: "Apps, platforms, anything you live in.", placeholder: "e.g. Telegram, Email, X", inputType: .tags),
        ]
    }
}
