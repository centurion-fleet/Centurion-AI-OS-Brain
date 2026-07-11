import SwiftUI

/// Enriched Mission Discovery Experience
/// A calm, guided journey to help the user discover their personal mission.
/// Uses plain language. Saves progress automatically.

struct MissionDiscoveryView: View {
    @AppStorage("missionAnswers") private var savedAnswersData: Data = Data()
    @State private var answers: [String: String] = [:]
    @State private var currentIndex = 0
    @State private var showSummary = false
    @State private var hasCompletedBefore = false
    
    let questions: [MissionQuestion] = [
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                if showSummary {
                    MissionSummaryView(answers: answers, onEdit: {
                        withAnimation { showSummary = false }
                    })
                } else {
                    guidedQuestionFlow
                }
            }
            .navigationTitle("Discover Your Mission")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadAnswers()
            }
        }
    }
    
    // MARK: - Guided Flow
    private var guidedQuestionFlow: some View {
        VStack(spacing: 0) {
            // Progress
            ProgressView(value: Double(currentIndex), total: Double(questions.count))
                .tint(ColorTheme.accent())
                .padding(.horizontal)
                .padding(.top, 8)
            
            Text("\(currentIndex + 1) of \(questions.count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(ColorTheme.mutedText())
                .padding(.top, 6)
            
            Spacer()
            
            // Current Question
            if currentIndex < questions.count {
                let question = questions[currentIndex]
                
                VStack(spacing: Spacing.xl) {
                    Text(question.section)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(ColorTheme.accent())
                        .tracking(2)
                    
                    Text(question.question)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                    
                    TextEditor(text: binding(for: question.id))
                        .frame(minHeight: 140)
                        .padding(16)
                        .background(ColorTheme.surface())
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ColorTheme.border().opacity(0.6), lineWidth: 1)
                        )
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            // Navigation
            HStack {
                if currentIndex > 0 {
                    Button("Back") {
                        withAnimation {
                            currentIndex -= 1
                        }
                    }
                    .foregroundColor(ColorTheme.mutedText())
                }
                
                Spacer()
                
                if currentIndex < questions.count - 1 {
                    Button("Next") {
                        withAnimation {
                            currentIndex += 1
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(ColorTheme.accent())
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                } else {
                    Button("Finish & See My Mission") {
                        saveAnswers()
                        withAnimation {
                            showSummary = true
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(ColorTheme.accent())
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            .padding(.bottom, 30)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Persistence
    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { answers[id] = $0 }
        )
    }
    
    private func loadAnswers() {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: savedAnswersData) {
            answers = decoded
            hasCompletedBefore = !answers.isEmpty
        }
    }
    
    private func saveAnswers() {
        if let encoded = try? JSONEncoder().encode(answers) {
            savedAnswersData = encoded
        }
    }
}

// MARK: - Summary View
struct MissionSummaryView: View {
    let answers: [String: String]
    let onEdit: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    Text("Your Mission")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(ColorTheme.primaryText())
                    
                    Text("This is what you’ve uncovered so far.\nIt can grow and change with you.")
                        .font(.system(size: 15))
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.lg)
                
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(Array(answers.keys.sorted()), id: \.self) { key in
                        if let answer = answers[key], !answer.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(key.capitalized.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).trimmingCharacters(in: .whitespaces))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ColorTheme.accent())
                                
                                Text(answer)
                                    .font(.system(size: 16))
                                    .foregroundColor(ColorTheme.primaryText())
                                    .lineSpacing(5)
                            }
                            .padding()
                            .background(ColorTheme.surface())
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                
                Button(action: onEdit) {
                    Text("Edit My Answers")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ColorTheme.accent())
                }
                .padding(.top, Spacing.md)
                
                Button {
                    // Future: Share or send to Centurion
                } label: {
                    Text("Share With My Centurion")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(AmberButtonStyle())
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