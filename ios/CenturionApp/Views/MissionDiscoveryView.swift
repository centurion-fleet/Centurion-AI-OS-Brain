import SwiftUI

/// Award-level Mission Discovery Experience
/// Designed with the intention of feeling special, human, and emotionally resonant.
struct MissionDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectionManager: ConnectionManager

    let initialAnswers: [String: String]
    let onComplete: ([String: String]) -> Void

    @State private var answers: [String: String]
    @State private var currentIndex = 0
    @State private var showSummary = false
    @State private var showIntro = true
    @State private var showSynthesis = false
    @State private var synthesizedStatement = ""
    @State private var synthesizedWhy = ""
    @State private var shareStatus: ShareStatus?
    @State private var isSharing = false

    private enum ShareStatus: Identifiable {
        case sent
        case notConnected

        var id: Self { self }
    }

    static let questions: [MissionQuestion] = [
        MissionQuestion(id: "areas", section: "What Matters Most", question: "When you look at the world, what areas of life feel most important to you right now?", placeholder: "Family, creativity, helping others, learning, building something..."),
        MissionQuestion(id: "topAreas", section: "What Matters Most", question: "If you had to choose 2–3 areas that you care about more than anything else, what would they be?", placeholder: "Write the ones that feel most alive to you..."),
        MissionQuestion(id: "responsibility", section: "Responsibility & Ownership", question: "What are you willing to take real responsibility for in your life or in the world?", placeholder: "This can be big or small..."),
        MissionQuestion(id: "problems", section: "Responsibility & Ownership", question: "What problems or situations do you naturally feel drawn to help solve or improve?", placeholder: "Even if no one asked you to..."),
        MissionQuestion(id: "shouldDo", section: "Responsibility & Ownership", question: "What do you feel you should be doing, even if it sometimes feels difficult or scary?", placeholder: ""),
        MissionQuestion(id: "alive", section: "Natural Energy & Aliveness", question: "When do you feel most alive, engaged, or “in flow”?", placeholder: "What are you usually doing in those moments?"),
        MissionQuestion(id: "timeless", section: "Natural Energy & Aliveness", question: "What activities or contributions make time disappear for you?", placeholder: ""),
        MissionQuestion(id: "noLimits", section: "Long-term Vision", question: "If you knew you couldn’t fail and had no limitations, what would you want to create or contribute to over the next 10–20 years?", placeholder: ""),
        MissionQuestion(id: "endOfLife", section: "Long-term Vision", question: "Looking back from the end of your life, what would make you feel your time here was well spent?", placeholder: "")
    ]

    init(
        initialAnswers: [String: String] = [:],
        onComplete: @escaping ([String: String]) -> Void
    ) {
        self.initialAnswers = initialAnswers
        self.onComplete = onComplete
        _answers = State(initialValue: initialAnswers)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                secondaryBackground.ignoresSafeArea()

                if showIntro {
                    introScreen
                } else if showSynthesis {
                    MissionSynthesisReviewView(
                        statement: $synthesizedStatement,
                        why: $synthesizedWhy,
                        onBack: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showSynthesis = false
                            }
                        },
                        onApprove: {
                            answers["_missionStatement"] = synthesizedStatement
                            answers["_whyThisMission"] = synthesizedWhy
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                showSynthesis = false
                                showSummary = true
                            }
                            Haptics.success()
                        }
                    )
                } else if showSummary {
                    MissionSummaryView(
                        questions: Self.questions,
                        answers: answers,
                        isSharing: isSharing,
                        onEdit: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showSummary = false
                            }
                        },
                        onShare: shareWithCenturion,
                        onDone: finishDiscovery
                    )
                } else {
                    guidedQuestionFlow
                }
            }
            .navigationTitle(showIntro ? "" : "Discover Your Mission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .onAppear {
                if !initialAnswers.isEmpty {
                    showIntro = false
                    if initialAnswers.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        if Self.questions.allSatisfy({ !(initialAnswers[$0.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }) {
                            showSummary = true
                        }
                    }
                }
            }
            .alert(item: $shareStatus) { status in
                switch status {
                case .sent:
                    Alert(
                        title: Text("Shared With Your Centurion"),
                        message: Text("Your mission discovery has been sent securely."),
                        dismissButton: .default(Text("OK"))
                    )
                case .notConnected:
                    Alert(
                        title: Text("Not Connected"),
                        message: Text("Pair with your Centurion in You first, then share your mission."),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
        }
    }

    // MARK: - Intro Screen (Ceremonial)

    private var introScreen: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            AtmosphericSurface(elevated: true, showRim: true) {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 42))
                        .foregroundColor(ColorTheme.accent().opacity(0.7))

                    Text("A Quiet Space")
                        .font(Typography.editorialTitle)
                        .foregroundColor(ColorTheme.primaryText())

                    Text("This is time set aside for you.\nTo listen to what matters most.")
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showIntro = false
                }
                Haptics.mediumTap()
            } label: {
                Text("Begin")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, 50)
        }
    }

    // MARK: - Guided Question Flow

    private var guidedQuestionFlow: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<Self.questions.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentIndex ? ColorTheme.accent() : ColorTheme.border())
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, Spacing.sm)

            Spacer()

            if currentIndex < Self.questions.count {
                let question = Self.questions[currentIndex]

                VStack(spacing: Spacing.xl) {
                    CenturionSectionHeader(
                        title: question.section,
                        icon: sectionIcon(for: question.section)
                    )
                    .padding(.horizontal, Spacing.lg)

                    Text(question.question)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, Spacing.lg)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    AtmosphericSurface {
                        ZStack(alignment: .topLeading) {
                            if (answers[question.id] ?? "").isEmpty, !question.placeholder.isEmpty {
                                Text(question.placeholder)
                                    .font(.body)
                                    .foregroundColor(ColorTheme.mutedText().opacity(0.6))
                                    .padding(.vertical, Spacing.xs)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: binding(for: question.id))
                                .scrollContentBackground(.hidden)
                                .font(.body)
                                .foregroundColor(ColorTheme.primaryText())
                                .frame(minHeight: 160)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .id(currentIndex)
            }

            Spacer()

            HStack(spacing: Spacing.md) {
                if currentIndex > 0 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentIndex -= 1
                        }
                        Haptics.lightTap()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .padding(Spacing.sm + 2)
                            .background(ColorTheme.surface())
                            .clipShape(Circle())
                    }
                    .foregroundColor(ColorTheme.mutedText())
                }

                Spacer()

                if currentIndex < Self.questions.count - 1 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentIndex += 1
                        }
                        Haptics.mediumTap()
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .frame(maxWidth: 200)
                } else {
                    Button {
                        prepareSynthesis()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            showSynthesis = true
                        }
                        Haptics.success()
                    } label: {
                        Text("Complete My Mission")
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                }
            }
            .padding(.bottom, Spacing.xl)
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func sectionIcon(for section: String) -> String {
        switch section {
        case "What Matters Most": return "heart"
        case "Responsibility & Ownership": return "hand.raised"
        case "Natural Energy & Aliveness": return "bolt"
        case "Long-term Vision": return "binoculars"
        default: return "sparkles"
        }
    }

    // MARK: - Actions

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { answers[id] = $0 }
        )
    }

    private func finishDiscovery() {
        if !synthesizedStatement.isEmpty {
            answers["_missionStatement"] = synthesizedStatement
        }
        if !synthesizedWhy.isEmpty {
            answers["_whyThisMission"] = synthesizedWhy
        }
        onComplete(answers)
        Haptics.success()
        dismiss()
    }

    private func prepareSynthesis() {
        synthesizedStatement = MissionStore.synthesizedMissionStatement(from: answers) ?? ""
        synthesizedWhy = MissionStore.synthesizedWhy(from: answers) ?? ""
        if synthesizedStatement.isEmpty {
            synthesizedStatement = "I am discovering what matters most to me."
        }
    }

    private func shareWithCenturion() {
        guard connectionManager.connectionState == .connected else {
            shareStatus = .notConnected
            return
        }

        isSharing = true
        let message = MissionStore.discoveryShareMessage(answers: answers, questions: Self.questions)

        Task {
            do {
                try await connectionManager.sendMessage(message)
                await MainActor.run {
                    isSharing = false
                    shareStatus = .sent
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    shareStatus = .notConnected
                }
            }
        }
    }
}

// MARK: - Synthesis Review

struct MissionSynthesisReviewView: View {
    @Binding var statement: String
    @Binding var why: String
    let onBack: () -> Void
    let onApprove: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                FullBrandHeader()

                AtmosphericSurface(elevated: true) {
                    VStack(spacing: Spacing.md) {
                        Text("Your life mission")
                            .font(Typography.editorialTitle)
                            .foregroundColor(ColorTheme.primaryText())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("We've distilled your reflections into words that describe what you're living toward. Edit until it feels true.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .lineSpacing(4)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    CenturionSectionHeader(title: "Your Life Mission", icon: "target")
                    AtmosphericSurface {
                        TextEditor(text: $statement)
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .frame(minHeight: 100)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    CenturionSectionHeader(title: "Why It Matters", icon: "heart")
                    AtmosphericSurface {
                        TextEditor(text: $why)
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .frame(minHeight: 80)
                    }
                }

                VStack(spacing: Spacing.md) {
                    Button(action: onApprove) {
                        Text("This feels right")
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())

                    Button(action: onBack) {
                        Text("Review my answers")
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                }
            }
            .padding()
        }
    }
}

// MARK: - Summary View

struct MissionSummaryView: View {
    let questions: [MissionQuestion]
    let answers: [String: String]
    let isSharing: Bool
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                FullBrandHeader()

                SuccessMoment(
                    title: "What you've discovered",
                    message: "This is about your life — what matters and what you're building.\nIt can evolve with you."
                )

                VStack(alignment: .leading, spacing: Spacing.lg) {
                    CenturionSectionHeader(title: "Your Reflections", icon: "text.quote")

                    ForEach(questions) { question in
                        if let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !answer.isEmpty {
                            AtmosphericSurface {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    CenturionSectionHeader(
                                        title: question.section,
                                        icon: "sparkles"
                                    )
                                    Text(answer)
                                        .font(.body)
                                        .foregroundColor(ColorTheme.primaryText())
                                        .lineSpacing(6)
                                }
                            }
                        }
                    }
                }

                VStack(spacing: Spacing.md) {
                    Button(action: onEdit) {
                        Text("Edit My Answers")
                    }
                    .buttonStyle(CenturionGhostButtonStyle())

                    Button(action: onShare) {
                        HStack {
                            if isSharing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Share With My Centurion")
                        }
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .disabled(isSharing)

                    Button(action: onDone) {
                        Text("Save to Pulse")
                    }
                    .buttonStyle(CenturionSecondaryButtonStyle())
                }
                .padding(.top, Spacing.lg)
            }
            .padding()
        }
    }
}

// MARK: - Model

struct MissionQuestion: Identifiable {
    let id: String
    let section: String
    let question: String
    let placeholder: String
}
