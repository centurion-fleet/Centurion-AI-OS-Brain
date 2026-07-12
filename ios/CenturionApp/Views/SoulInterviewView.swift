import SwiftUI

/// Shapes your Centurion's Soul — AI personality, tone, and rules.
struct SoulInterviewView: View {
    let existingSoul: SoulDocument?
    let onComplete: (SoulDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var soul: SoulDocument
    @State private var currentQuestionIndex = 0
    @State private var answers: [Int: String] = [:]
    @State private var tagInput: String = ""
    @State private var isComplete = false

    private let questions = SoulQuestion.allQuestions()

    init(existingSoul: SoulDocument? = nil, onComplete: @escaping (SoulDocument) -> Void) {
        self.existingSoul = existingSoul
        self.onComplete = onComplete
        _soul = State(initialValue: existingSoul ?? SoulDocument())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isComplete {
                    completionView
                } else {
                    progressBar
                    questionView
                }
            }
            .background(secondaryBackground)
            .navigationTitle("Shape Your Centurion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        saveCurrentAnswer()
                        compileSoul()
                        onComplete(soul)
                        dismiss()
                    }
                    .foregroundColor(ColorTheme.mutedText())
                    .font(.caption)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isComplete {
                        Button("Done") {
                            saveCurrentAnswer()
                            compileSoul()
                            onComplete(soul)
                            dismiss()
                        }
                        .foregroundColor(ColorTheme.accent())
                        .font(.caption)
                    }
                }
            }
            .interactiveDismissDisabled()
            .onAppear { prefillFromExistingSoul() }
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()
        }
    }

    private func prefillFromExistingSoul() {
        guard let existing = existingSoul else { return }
        if questions.indices.contains(0), !existing.personalitySummary.isEmpty { answers[0] = existing.personalitySummary }
        if questions.indices.contains(1), !existing.tone.isEmpty { answers[1] = existing.tone }
        if questions.indices.contains(2), !existing.communicationStyle.isEmpty { answers[2] = existing.communicationStyle }
        if questions.indices.contains(3), !existing.responseLength.isEmpty { answers[3] = existing.responseLength }
        if questions.indices.contains(4), !existing.alwaysDo.isEmpty { answers[4] = existing.alwaysDo.joined(separator: ", ") }
        if questions.indices.contains(5), !existing.neverDo.isEmpty { answers[5] = existing.neverDo.joined(separator: ", ") }
        if questions.indices.contains(6), !existing.pushbackStyle.isEmpty { answers[6] = existing.pushbackStyle }
        if questions.indices.contains(7), !existing.uncertaintyStyle.isEmpty { answers[7] = existing.uncertaintyStyle }
    }

    private var progressBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text(currentQuestion.stage.rawValue)
                    .font(Typography.sectionLabel)
                    .foregroundColor(ColorTheme.accent())
                    .textCase(.uppercase)
                    .tracking(1.5)
                Spacer()
                Text("\(currentQuestionIndex + 1) of \(questions.count)")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ColorTheme.border())
                        .frame(height: 2)
                    Rectangle()
                        .fill(ColorTheme.accent())
                        .frame(width: geo.size.width * progress, height: 2)
                        .animation(Motion.heavy, value: currentQuestionIndex)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, Spacing.md)
        }
    }

    private var progress: Double {
        Double(currentQuestionIndex + 1) / Double(questions.count)
    }

    private var currentQuestion: SoulQuestion {
        questions[currentQuestionIndex]
    }

    private var questionView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if currentQuestionIndex == 0 {
                    FullBrandHeader()
                }

                Spacer().frame(height: Spacing.md)

                AtmosphericSurface(elevated: true) {
                    VStack(spacing: Spacing.md) {
                        Text(currentQuestion.question)
                            .font(Typography.editorialTitle)
                            .foregroundColor(ColorTheme.primaryText())
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        if !currentQuestion.hint.isEmpty {
                            Text(currentQuestion.hint)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.dimAccent())
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.md)

                switch currentQuestion.inputType {
                case .text:
                    textInput
                case .multiline:
                    multilineInput
                case .tags:
                    tagInputView
                }

                Spacer()

                Button(action: nextQuestion) {
                    Text(currentQuestionIndex < questions.count - 1 ? "Next" : "Complete")
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .frame(maxWidth: 428)
            .frame(maxWidth: .infinity)
        }
    }

    private var textInput: some View {
        AtmosphericSurface {
            TextField(currentQuestion.placeholder, text: textBinding)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundColor(ColorTheme.primaryText())
        }
        .padding(.horizontal, Spacing.md)
    }

    private var multilineInput: some View {
        AtmosphericSurface {
            TextEditor(text: textBinding)
                .font(.body)
                .foregroundColor(ColorTheme.primaryText())
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
        }
        .padding(.horizontal, Spacing.md)
    }

    private var tagInputView: some View {
        VStack(spacing: Spacing.sm) {
            let tags = currentTags
            if !tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: Spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                                .foregroundColor(ColorTheme.primaryText())
                            Button(action: { removeTag(tag) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(ColorTheme.accent().opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, Spacing.md)
            }

            AtmosphericSurface {
                HStack {
                    TextField("Type and press return...", text: $tagInput)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primaryText())
                        .onSubmit { addTag() }
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(ColorTheme.accent())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { answers[currentQuestionIndex] ?? "" },
            set: { answers[currentQuestionIndex] = $0 }
        )
    }

    private var currentTags: [String] {
        let raw = answers[currentQuestionIndex] ?? ""
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var tags = currentTags
        tags.append(trimmed)
        answers[currentQuestionIndex] = tags.joined(separator: ",")
        tagInput = ""
    }

    private func removeTag(_ tag: String) {
        var tags = currentTags
        tags.removeAll { $0 == tag }
        answers[currentQuestionIndex] = tags.joined(separator: ",")
    }

    private func saveCurrentAnswer() {}

    private func nextQuestion() {
        Haptics.lightTap()
        saveCurrentAnswer()

        if currentQuestionIndex < questions.count - 1 {
            withAnimation { currentQuestionIndex += 1 }
        } else {
            compileSoul()
            withAnimation { isComplete = true }
        }
    }

    private func compileSoul() {
        if let v = answers[0]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            soul.personalitySummary = v
        }
        if let v = answers[1] { soul.tone = v }
        if let v = answers[2] { soul.communicationStyle = v }
        if let v = answers[3] { soul.responseLength = v }
        if let raw = answers[4] {
            soul.alwaysDo = splitTags(raw)
        }
        if let raw = answers[5] {
            soul.neverDo = splitTags(raw)
        }
        if let v = answers[6] { soul.pushbackStyle = v }
        if let v = answers[7] { soul.uncertaintyStyle = v }
        soul.version = 2
        soul.updatedAt = Date()
    }

    private func splitTags(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var completionView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                SuccessMoment(
                    title: "Your Centurion Knows How to Be Your Companion",
                    message: "Personality and rules are set.\nYour Centurion will speak and behave the way you've defined."
                )

                if !soul.personalitySummary.isEmpty {
                    AtmosphericSurface(elevated: true, showRim: true) {
                        Text(soul.personalitySummary)
                            .font(.headline)
                            .foregroundColor(ColorTheme.accent())
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, Spacing.md)
                }

                Button(action: {
                    Haptics.success()
                    onComplete(soul)
                    dismiss()
                }) {
                    Text("Done")
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
        }
    }
}
