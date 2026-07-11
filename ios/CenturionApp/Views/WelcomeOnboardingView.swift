import SwiftUI

/// First-run welcome — calm introduction for non-technical users.
struct WelcomeOnboardingView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @AppStorage("centurion.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var step: OnboardingStep = .welcome
    @State private var showMissionDiscovery = false

    enum OnboardingStep {
        case welcome
        case connect
        case mission
    }

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            ColorTheme.background().ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                switch step {
                case .welcome:
                    welcomeStep
                case .connect:
                    connectStep
                case .mission:
                    missionStep
                }

                Spacer()

                primaryButton
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xxl)
            }
        }
        .fullScreenCover(isPresented: $showMissionDiscovery) {
            MissionDiscoveryView(initialAnswers: missionStore.discoveryAnswers) { answers in
                missionStore.completeDiscovery(from: answers)
                finishOnboarding()
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Spacing.lg) {
            CenturionAppMark(size: 88)
                .shadow(color: ColorTheme.accent().opacity(0.2), radius: 16, y: 6)

            Text("Welcome to\nYour Centurion")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text("This is your private companion — on your network, for your mission.\n\nYou stay in charge. Your Centurion works beside you.")
                .font(.body)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, Spacing.lg)
        }
    }

    private var connectStep: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.system(size: 44))
                .foregroundColor(ColorTheme.accent())

            Text("Link Your Centurion")
                .font(.title2.weight(.bold))
                .foregroundColor(ColorTheme.primaryText())

            Text("Make sure your iPhone and Centurion are on the same Wi‑Fi.\n\nYou'll find the Connect button in the first tab whenever you're ready.")
                .font(.body)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, Spacing.lg)

            if connectionManager.connectionState == .connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.success())
            }
        }
    }

    private var missionStep: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 44))
                .foregroundColor(ColorTheme.accent().opacity(0.8))

            Text("Discover Your Mission")
                .font(.title2.weight(.bold))
                .foregroundColor(ColorTheme.primaryText())

            Text("A quiet moment to reflect on your life — what matters and what you're building.\n\nThis is about you, not how your Centurion behaves. You can return anytime from Home or Settings.")
                .font(.body)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, Spacing.lg)
        }
    }

    // MARK: - Actions

    private var primaryButton: some View {
        Group {
            switch step {
            case .welcome:
                Button("Continue") {
                    withAnimation(Motion.standard) { step = .connect }
                    Haptics.lightTap()
                }
                .buttonStyle(AmberButtonStyle())
            case .connect:
                VStack(spacing: Spacing.md) {
                    Button("Continue") {
                        withAnimation(Motion.standard) { step = .mission }
                        Haptics.lightTap()
                    }
                    .buttonStyle(AmberButtonStyle())

                    Button("Skip for now") {
                        withAnimation(Motion.standard) { step = .mission }
                    }
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                }
            case .mission:
                VStack(spacing: Spacing.md) {
                    Button("Begin Mission Discovery") {
                        showMissionDiscovery = true
                        Haptics.mediumTap()
                    }
                    .buttonStyle(AmberButtonStyle())

                    Button("Skip — explore the app") {
                        finishOnboarding()
                    }
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                }
            }
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        Haptics.success()
        onComplete()
    }
}
