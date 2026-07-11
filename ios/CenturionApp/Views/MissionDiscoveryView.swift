import SwiftUI

/// Award-level Mission Discovery Experience
/// Designed with the intention of feeling special, human, and emotionally resonant.
/// Every detail is considered — pacing, haptics, typography, warmth, and meaning.

struct MissionDiscoveryView: View {
    @AppStorage("missionAnswers") private var savedAnswersData: Data = Data()
    @State private var answers: [String: String] = [:]
    @State private var currentIndex = 0
    @State private var showSummary = false
    @State private var showIntro = true
    
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
                if showIntro {
                    introScreen
                } else if showSummary {
                    MissionSummaryView(answers: answers, onEdit: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showSummary = false
                        }
                    })
                } else {
                    guidedQuestionFlow
                }
            }
            .navigationTitle(showIntro ? "" : "Discover Your Mission")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadAnswers()
                if !answers.isEmpty {
                    showIntro = false
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
            // Elegant Progress
            HStack {
                ForEach(0..<questions.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentIndex ? ColorTheme.accent() : ColorTheme.border())
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 12)
            
            Spacer()
            
            // Question Content with animation
            if currentIndex < questions.count {
                let question = questions[currentIndex]
                
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
                    
                    TextEditor(text: binding(for: question.id))
                        .frame(minHeight: 160)
                        .padding(20)
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
                .id(currentIndex) // Force animation on change
            }
            
            Spacer()
            
            // Navigation Bar
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
                
                if currentIndex < questions.count - 1 {
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
                        saveAnswers()
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
    
    // MARK: - Persistence & Helpers
    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { answers[id] = $0 }
        )
    }
    
    private func loadAnswers() {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: savedAnswersData) {
            answers = decoded
        }
    }
    
    private func saveAnswers() {
        if let encoded = try? JSONEncoder().encode(answers) {
            savedAnswersData = encoded
        }
    }
}

// MARK: - Summary View (Enriched)
struct MissionSummaryView: View {
    let answers: [String: String]
    let onEdit: () -> Void
    
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
                    
                    Text("This is what you’ve discovered.\nIt is alive and can evolve with you.")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.top, Spacing.xl)
                
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(Array(answers.keys.sorted()), id: \.self) { key in
                        if let answer = answers[key], !answer.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(key.capitalized.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).trimmingCharacters(in: .whitespaces))
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
                    
                    Button {
                        // Future: Send to Centurion / Pulse
                    } label: {
                        Text("Share With My Centurion")
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