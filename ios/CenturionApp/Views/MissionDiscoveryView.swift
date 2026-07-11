import SwiftUI

/// Mission Discovery – A reflective space to help the user uncover their personal mission.
/// Written in plain, everyday language. No jargon.
/// Designed to feel supportive, calm, and meaningful.

struct MissionDiscoveryView: View {
    @State private var answers: [String: String] = [:]
    @State private var currentStep = 0
    @State private var showSummary = false
    
    let questions: [MissionQuestion] = [
        MissionQuestion(
            id: "areas",
            section: "What Matters Most",
            question: "When you look at the world, what areas of life feel most important to you right now?",
            placeholder: "Family, creativity, helping others, learning, building something..."
        ),
        MissionQuestion(
            id: "topAreas",
            section: "What Matters Most",
            question: "If you had to choose 2–3 areas that you care about more than anything else, what would they be?",
            placeholder: "Write the ones that feel most alive to you..."
        ),
        MissionQuestion(
            id: "responsibility",
            section: "Responsibility & Ownership",
            question: "What are you willing to take real responsibility for in your life or in the world?",
            placeholder: "This can be big or small..."
        ),
        MissionQuestion(
            id: "problems",
            section: "Responsibility & Ownership",
            question: "What problems or situations do you naturally feel drawn to help solve or improve?",
            placeholder: "Even if no one asked you to..."
        ),
        MissionQuestion(
            id: "shouldDo",
            section: "Responsibility & Ownership",
            question: "What do you feel you should be doing, even if it sometimes feels difficult or scary?",
            placeholder: ""
        ),
        MissionQuestion(
            id: "alive",
            section: "Natural Energy & Aliveness",
            question: "When do you feel most alive, engaged, or “in flow”?",
            placeholder: "What are you usually doing in those moments?"
        ),
        MissionQuestion(
            id: "timeless",
            section: "Natural Energy & Aliveness",
            question: "What activities or contributions make time disappear for you?",
            placeholder: ""
        ),
        MissionQuestion(
            id: "noLimits",
            section: "Long-term Vision",
            question: "If you knew you couldn’t fail and had no limitations, what would you want to create or contribute to over the next 10–20 years?",
            placeholder: ""
        ),
        MissionQuestion(
            id: "endOfLife",
            section: "Long-term Vision",
            question: "Looking back from the end of your life, what would make you feel your time here was well spent?",
            placeholder: ""
        )
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    BrandHeader()
                    
                    if showSummary {
                        MissionSummaryView(answers: answers)
                    } else {
                        discoveryContent
                    }
                }
                .padding()
            }
            .navigationTitle("Discover Your Mission")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var discoveryContent: some View {
        VStack(spacing: Spacing.xl) {
            // Intro
            VStack(spacing: Spacing.md) {
                Text("This is a quiet space to explore what matters most to you.")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)
                
                Text("There are no right answers. Just be honest with yourself.")
                    .font(.system(size: 14))
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, Spacing.lg)
            
            // Questions
            ForEach(questions) { question in
                QuestionCard(question: question, answer: binding(for: question.id))
            }
            
            // Finish button
            Button {
                withAnimation {
                    showSummary = true
                }
            } label: {
                Text("See My Mission Summary")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(AmberButtonStyle())
            .padding(.top, Spacing.lg)
        }
    }
    
    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { answers[id] = $0 }
        )
    }
}

// MARK: - Question Card
struct QuestionCard: View {
    let question: MissionQuestion
    @Binding var answer: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(question.section)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(ColorTheme.accent())
                .tracking(1)
            
            Text(question.question)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ColorTheme.primaryText())
                .lineSpacing(4)
            
            TextEditor(text: $answer)
                .frame(minHeight: 80)
                .padding(12)
                .background(ColorTheme.surface())
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(ColorTheme.border(), lineWidth: 0.5)
                )
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Summary View
struct MissionSummaryView: View {
    let answers: [String: String]
    
    var body: some View {
        VStack(spacing: Spacing.xl) {
            Text("Your Mission")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
            
            Text("This is what you’ve discovered so far. It can evolve.")
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Array(answers.keys.sorted()), id: \.self) { key in
                    if let answer = answers[key], !answer.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(key.capitalized)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(ColorTheme.accent())
                            
                            Text(answer)
                                .font(.system(size: 15))
                                .foregroundColor(ColorTheme.primaryText())
                                .lineSpacing(4)
                        }
                    }
                }
            }
            .padding()
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Button {
                // Future: Save to persistent storage or send to Centurion
            } label: {
                Text("Save This as My Mission")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(AmberButtonStyle())
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