import SwiftUI

/// Guided editor for human context — story, values, people, and needs.
/// Folded into Mission; separate from Soul (AI personality).
struct HumanContextInterviewView: View {
    let existingProfile: HumanProfile
    let onComplete: (HumanProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var profile: HumanProfile
    @State private var currentQuestionIndex = 0
    @State private var answers: [Int: String] = [:]
    @State private var tagInput: String = ""

    private let questions = HumanContextQuestion.allQuestions()

    init(existingProfile: HumanProfile, onComplete: @escaping (HumanProfile) -> Void) {
        self.existingProfile = existingProfile
        self.onComplete = onComplete
        _profile = State(initialValue: existingProfile)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                questionView
            }
            .background(secondaryBackground)
            .navigationTitle("About You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ColorTheme.mutedText())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCurrentAnswer()
                        compileProfile()
                        onComplete(profile)
                        dismiss()
                    }
                    .foregroundColor(ColorTheme.accent())
                    .fontWeight(.semibold)
                }
            }
            .onAppear { prefillFromExisting() }
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()
        }
    }

    private func prefillFromExisting() {
        let q = questions
        if q.indices.contains(0), !existingProfile.yourStory.isEmpty {
            answers[0] = existingProfile.yourStory
        }
        if q.indices.contains(1), !existingProfile.yourStory.isEmpty {
            answers[1] = existingProfile.yourStory
        }
        if q.indices.contains(2), !existingProfile.yourValues.isEmpty {
            answers[2] = existingProfile.yourValues.joined(separator: ", ")
        }
        if q.indices.contains(3), !existingProfile.keyRelationships.isEmpty {
            answers[3] = existingProfile.keyRelationships.joined(separator: ", ")
        }
        if q.indices.contains(4), !existingProfile.workStyle.isEmpty {
            answers[4] = existingProfile.workStyle
        }
        if q.indices.contains(5) {
            let tz = [existingProfile.timezone, existingProfile.workHours]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !tz.isEmpty { answers[5] = tz }
        }
        if q.indices.contains(6), !existingProfile.challenges.isEmpty {
            answers[6] = existingProfile.challenges.joined(separator: ", ")
        }
        if q.indices.contains(7), !existingProfile.delegatePreferences.isEmpty {
            answers[7] = existingProfile.delegatePreferences.joined(separator: ", ")
        }
        if q.indices.contains(8), !existingProfile.toolsYouUse.isEmpty {
            answers[8] = existingProfile.toolsYouUse.joined(separator: ", ")
        }
    }

    private var progressBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text(currentQuestion.stage)
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

    private var currentQuestion: HumanContextQuestion {
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
                    Text(currentQuestionIndex < questions.count - 1 ? "Next" : "Done")
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
            compileProfile()
            onComplete(profile)
            dismiss()
        }
    }

    private func compileProfile() {
        if let story = answers[1]?.trimmingCharacters(in: .whitespacesAndNewlines), !story.isEmpty {
            profile.yourStory = story
        } else if let intro = answers[0]?.trimmingCharacters(in: .whitespacesAndNewlines), !intro.isEmpty {
            profile.yourStory = intro
        }
        if let raw = answers[2] {
            profile.yourValues = splitTags(raw)
        }
        if let raw = answers[3] {
            profile.keyRelationships = splitTags(raw)
        }
        if let v = answers[4] { profile.workStyle = v }
        if let v = answers[5] { profile.timezone = v }
        if let raw = answers[6] {
            profile.challenges = splitTags(raw)
        }
        if let raw = answers[7] {
            profile.delegatePreferences = splitTags(raw)
        }
        if let raw = answers[8] {
            profile.toolsYouUse = splitTags(raw)
        }
    }

    private func splitTags(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
