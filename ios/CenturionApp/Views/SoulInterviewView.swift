import SwiftUI

/// The Soul Interview — a guided conversation that builds your Soul Document.
/// This is the FIRST experience for new users. They download the Remote app,
/// do the interview while waiting for their Centurion to arrive, and when it
/// does, their Soul is ready to be embodied.
///
/// The interview is designed to feel personal and warm — like a conversation,
/// not a form. Each question reveals the next, building a portrait of who
/// the human is and what they're building.
struct SoulInterviewView: View {
    let existingSoul: SoulDocument?
    let onComplete: (SoulDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var soul: SoulDocument
    @State private var currentQuestionIndex = 0
    @State private var answers: [Int: String] = [:]
    @State private var tagInput: String = ""
    @State private var vitalCurrentInput: String = ""
    @State private var vitalTargetInput: String = ""
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

    private func prefillFromExistingSoul() {
        guard let existing = existingSoul else { return }
        let q = questions
        if q.indices.contains(0), !existing.yourStory.isEmpty { answers[0] = existing.yourStory }
        if q.indices.contains(1), !existing.yourStory.isEmpty { answers[1] = existing.yourStory }
        if q.indices.contains(2), !existing.yourValues.isEmpty { answers[2] = existing.yourValues.joined(separator: ", ") }
        if q.indices.contains(3), !existing.missionStatement.isEmpty { answers[3] = existing.missionStatement }
        if q.indices.contains(4), !existing.whyThisMission.isEmpty { answers[4] = existing.whyThisMission }
        if q.indices.contains(5), !existing.vitalStatName.isEmpty { answers[5] = existing.vitalStatName }
        if q.indices.contains(6) {
            vitalCurrentInput = existing.vitalStatCurrent > 0 ? String(format: "%.0f", existing.vitalStatCurrent) : ""
            vitalTargetInput = existing.vitalStatTarget > 0 ? String(format: "%.0f", existing.vitalStatTarget) : ""
        }
        if q.indices.contains(7), !existing.workStyle.isEmpty { answers[7] = existing.workStyle }
        if q.indices.contains(8), !existing.communicationStyle.isEmpty { answers[8] = existing.communicationStyle }
        if q.indices.contains(9), !existing.timezone.isEmpty { answers[9] = existing.timezone }
        if q.indices.contains(10), !existing.goals.isEmpty { answers[10] = existing.goals.joined(separator: ", ") }
        if q.indices.contains(11), !existing.challenges.isEmpty { answers[11] = existing.challenges.joined(separator: ", ") }
        if q.indices.contains(12), !existing.delegatePreferences.isEmpty { answers[12] = existing.delegatePreferences.joined(separator: ", ") }
        if q.indices.contains(13), !existing.keyRelationships.isEmpty { answers[13] = existing.keyRelationships.joined(separator: ", ") }
        if q.indices.contains(14), !existing.toolsYouUse.isEmpty { answers[14] = existing.toolsYouUse.joined(separator: ", ") }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            // Stage indicator
            HStack {
                Text(currentQuestion.stage.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent())
                Spacer()
                Text("\(currentQuestionIndex + 1) of \(questions.count)")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Progress bar
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
            .padding(.horizontal)
        }
    }

    private var progress: Double {
        Double(currentQuestionIndex + 1) / Double(questions.count)
    }

    // MARK: - Question View

    private var currentQuestion: SoulQuestion {
        questions[currentQuestionIndex]
    }

    private var questionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                // Question
                Text(currentQuestion.question)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal)

                // Hint
                if !currentQuestion.hint.isEmpty {
                    Text(currentQuestion.hint)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.dimAccent())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer().frame(height: 20)

                // Input
                switch currentQuestion.inputType {
                case .text:
                    textInput
                case .multiline:
                    multilineInput
                case .tags:
                    tagInputView
                case .number:
                    numberInput
                }

                Spacer()

                // Next button
                Button(action: nextQuestion) {
                    Text(currentQuestionIndex < questions.count - 1 ? "Next" : "Complete")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ColorTheme.accent())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 428)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Input Types

    private var textInput: some View {
        TextField(currentQuestion.placeholder, text: textBinding)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundColor(ColorTheme.primaryText())
            .padding()
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ColorTheme.border(), lineWidth: 1)
            )
            .padding(.horizontal)
    }

    private var multilineInput: some View {
        TextEditor(text: textBinding)
            .font(.body)
            .foregroundColor(ColorTheme.primaryText())
            .scrollContentBackground(.hidden)
            .padding()
            .frame(minHeight: 150)
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ColorTheme.border(), lineWidth: 1)
            )
            .padding(.horizontal)
    }

    private var tagInputView: some View {
        VStack(spacing: 12) {
            // Current tags
            let tags = currentTags
            if !tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12))
                                .foregroundColor(ColorTheme.primaryText())
                            Button(action: { removeTag(tag) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ColorTheme.accent().opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
            }

            // Add new tag
            HStack {
                TextField("Type and press return...", text: $tagInput)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.primaryText())
                    .onSubmit {
                        addTag()
                    }

                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ColorTheme.border(), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    private var numberInput: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                    TextField("0", text: $vitalCurrentInput)
                        .textFieldStyle(.plain)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.accent())
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                        .padding(12)
                        .background(ColorTheme.surface())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(ColorTheme.border(), lineWidth: 1)
                        )
                }

                Text("→")
                    .font(.title)
                    .foregroundColor(ColorTheme.dimAccent())

                VStack(spacing: 4) {
                    Text("Target")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                    TextField("0", text: $vitalTargetInput)
                        .textFieldStyle(.plain)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.accent())
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                        .padding(12)
                        .background(ColorTheme.surface())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(ColorTheme.border(), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Answer Storage

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

    private func saveCurrentAnswer() {
        if currentQuestion.inputType == .number {
            answers[currentQuestionIndex] = "\(vitalCurrentInput)|\(vitalTargetInput)"
        }
    }

    private func nextQuestion() {
        Haptics.lightTap()
        saveCurrentAnswer()

        if currentQuestionIndex < questions.count - 1 {
            withAnimation {
                currentQuestionIndex += 1
                restoreInputsForCurrentQuestion()
            }
        } else {
            compileSoul()
            withAnimation {
                isComplete = true
            }
        }
    }

    private func restoreInputsForCurrentQuestion() {
        guard currentQuestion.inputType == .number else { return }
        let parts = (answers[currentQuestionIndex] ?? "").split(separator: "|", omittingEmptySubsequences: false)
        vitalCurrentInput = parts.indices.contains(0) ? String(parts[0]) : ""
        vitalTargetInput = parts.indices.contains(1) ? String(parts[1]) : ""
    }

    private func compileSoul() {
        if let story = answers[1]?.trimmingCharacters(in: .whitespacesAndNewlines), !story.isEmpty {
            soul.yourStory = story
        } else if let intro = answers[0]?.trimmingCharacters(in: .whitespacesAndNewlines), !intro.isEmpty {
            soul.yourStory = intro
        }
        if let raw = answers[2] {
            soul.yourValues = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let v = answers[3] { soul.missionStatement = v }
        if let v = answers[4] { soul.whyThisMission = v }
        if let v = answers[5] { soul.vitalStatName = v }
        if let raw = answers[6] {
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
            if parts.indices.contains(0), let current = Double(parts[0]) { soul.vitalStatCurrent = current }
            if parts.indices.contains(1), let target = Double(parts[1]) { soul.vitalStatTarget = target }
        } else {
            if let current = Double(vitalCurrentInput) { soul.vitalStatCurrent = current }
            if let target = Double(vitalTargetInput) { soul.vitalStatTarget = target }
        }
        if let v = answers[7] { soul.workStyle = v }
        if let v = answers[8] { soul.communicationStyle = v }
        if let v = answers[9] { soul.timezone = v }
        if let raw = answers[10] {
            soul.goals = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let raw = answers[11] {
            soul.challenges = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let raw = answers[12] {
            soul.delegatePreferences = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let raw = answers[13] {
            soul.keyRelationships = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let raw = answers[14] {
            soul.toolsYouUse = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        soul.updatedAt = Date()
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundColor(ColorTheme.accent())

            Text("Your Soul is Written")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())

            Text("Your Centurion will know who you are\nfrom day one.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)

            if !soul.missionStatement.isEmpty {
                VStack(spacing: 4) {
                    Text("Your Mission")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                    Text(soul.missionStatement)
                        .font(.headline)
                        .foregroundColor(ColorTheme.accent())
                        .multilineTextAlignment(.center)
                }
                .padding()
                .cardStyle()
            }

            Spacer()

            Button(action: {
                Haptics.success()
                onComplete(soul)
                dismiss()
            }) {
                Text("Done — Show My Soul")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ColorTheme.accent())
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }
}
