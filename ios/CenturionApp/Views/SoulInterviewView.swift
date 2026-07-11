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
        VStack(spacing: 8) {
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

    private var currentQuestion: SoulQuestion {
        questions[currentQuestionIndex]
    }

    private var questionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 32)

                Text(currentQuestion.question)
                    .font(.title2.weight(.bold))
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal)

                if !currentQuestion.hint.isEmpty {
                    Text(currentQuestion.hint)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.dimAccent())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer().frame(height: 12)

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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundColor(ColorTheme.accent())

            Text("Your Centurion Knows How to Be Your Companion")
                .font(.title2.weight(.bold))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Personality and rules are set.\nYour Centurion will speak and behave the way you've defined.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)

            if !soul.personalitySummary.isEmpty {
                Text(soul.personalitySummary)
                    .font(.headline)
                    .foregroundColor(ColorTheme.accent())
                    .multilineTextAlignment(.center)
                    .padding()
                    .cardStyle()
            }

            Spacer()

            Button(action: {
                Haptics.success()
                onComplete(soul)
                dismiss()
            }) {
                Text("Done")
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
