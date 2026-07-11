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
                ColorTheme.background().ignoresSafeArea()

                if showIntro {
                    introScreen
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
                        // Returning user — skip intro, land on first unanswered or summary
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
                        message: Text("Pair with your Centurion in the Connect tab first, then share your mission."),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    // MARK: - Intro Screen (Ceremonial)

    private var introScreen: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42))
                    .foregroundColor(ColorTheme.accent().opacity(0.7))

                Text("A Quiet Space")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())

                Text("This is time set aside for you.\nTo listen to what matters most.")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showIntro = false
                }
                Haptics.mediumTap()
            } label: {
                Text("Begin")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(AmberButtonStyle())
            .padding(.horizontal, 40)
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
            .padding(.top, 12)

            Spacer()

            if currentIndex < Self.questions.count {
                let question = Self.questions[currentIndex]

                VStack(spacing: Spacing.xl) {
                    Text(question.section)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(ColorTheme.accent())
                        .tracking(3)
                        .opacity(0.8)

                    Text(question.question)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    ZStack(alignment: .topLeading) {
                        if (answers[question.id] ?? "").isEmpty, !question.placeholder.isEmpty {
                            Text(question.placeholder)
                                .font(.body)
                                .foregroundColor(ColorTheme.mutedText().opacity(0.6))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 28)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: binding(for: question.id))
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .foregroundColor(ColorTheme.primaryText())
                            .frame(minHeight: 160)
                            .padding(20)
                    }
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ColorTheme.border().opacity(0.5), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .onChange(of: answers[question.id]) { _ in
                        Haptics.lightTap()
                    }
                }
                .id(currentIndex)
            }

            Spacer()

            HStack(spacing: 16) {
                if currentIndex > 0 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentIndex -= 1
                        }
                        Haptics.lightTap()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .padding(14)
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
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 36)
                            .padding(.vertical, 14)
                            .background(ColorTheme.accent())
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                } else {
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            showSummary = true
                        }
                        Haptics.success()
                    } label: {
                        Text("Complete My Mission")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 36)
                            .padding(.vertical, 14)
                            .background(ColorTheme.accent())
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.bottom, 40)
            .padding(.horizontal, 24)
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
        onComplete(answers)
        Haptics.success()
        dismiss()
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
                VStack(spacing: Spacing.md) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(ColorTheme.accent().opacity(0.6))

                    Text("Your Mission")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundColor(ColorTheme.primaryText())

                    Text("This is what you've discovered.\nIt is alive and can evolve with you.")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.top, Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(questions) { question in
                        if let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !answer.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(question.section.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ColorTheme.accent())
                                    .tracking(1)

                                Text(answer)
                                    .font(.system(size: 17))
                                    .foregroundColor(ColorTheme.primaryText())
                                    .lineSpacing(6)
                            }
                            .padding(20)
                            .background(ColorTheme.surface())
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }

                VStack(spacing: Spacing.md) {
                    Button(action: onEdit) {
                        Text("Edit My Answers")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ColorTheme.accent())
                    }

                    Button(action: onShare) {
                        HStack {
                            if isSharing {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text("Share With My Centurion")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(AmberButtonStyle())
                    .disabled(isSharing)

                    Button(action: onDone) {
                        Text("Save to Pulse")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(AmberButtonStyle())
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
