import SwiftUI

/// First-moment experience — matches the system launch screen so the handoff feels instant.
/// Main app loads underneath during the ~1s splash so the transition feels immediate.
struct SplashView: View {
    @State private var contentOpacity: Double = 1
    @State private var taglineOpacity = 0.0
    @State private var missionHorizonOpacity = 0.0
    @State private var didComplete = false

    let onComplete: () -> Void

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if short.isEmpty { return "" }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            ColorTheme.background()
                .ignoresSafeArea()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("CENTURION")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ColorTheme.mutedText())
                    .tracking(4)
                    .opacity(0.85)

                Text("Sovereign AI Remote")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                    .padding(.top, Spacing.sm)
                    .opacity(taglineOpacity)

                Text("1 Human 1 AI")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(1.5)
                    .opacity(taglineOpacity)
                    .padding(.top, Spacing.sm)

                if !appVersionLabel.isEmpty {
                    Text(appVersionLabel)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .opacity(taglineOpacity * 0.9)
                        .padding(.top, Spacing.sm)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, ColorTheme.accent().opacity(0.35), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 80, height: 1)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)
                    .opacity(taglineOpacity)

                Text("MISSION HORIZON")
                    .font(Typography.sectionLabel)
                    .foregroundColor(ColorTheme.accent())
                    .tracking(6)
                    .opacity(missionHorizonOpacity)

                Text("Your lifelong companion")
                    .font(.caption)
                    .foregroundColor(ColorTheme.dimAccent())
                    .opacity(missionHorizonOpacity * 0.9)
                    .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
        }
        .opacity(contentOpacity)
        .onAppear {
            animateThroughPhases()
        }
        .onTapGesture {
            completeToApp()
        }
    }

    private func animateThroughPhases() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.25)) {
                taglineOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.25)) {
                missionHorizonOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            completeToApp()
        }
    }

    private func completeToApp() {
        guard !didComplete else { return }
        didComplete = true

        withAnimation(.easeOut(duration: 0.2)) {
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onComplete()
        }
    }
}
