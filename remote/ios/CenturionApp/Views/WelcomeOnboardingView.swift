import SwiftUI

/// First-run welcome — calm introduction for non-technical users.
struct WelcomeOnboardingView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @AppStorage("centurion.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var step: OnboardingStep = .welcome
    @State private var showMissionDiscovery = false
    @State private var showPairingSheet = false

    enum OnboardingStep {
        case welcome
        case connect
        case mission
    }

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            ColorTheme.background().ignoresSafeArea()
            ColorTheme.atmosphericVeil().ignoresSafeArea()

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
        .sheet(isPresented: $showPairingSheet) {
            ConnectionPairingSheet()
                .environmentObject(connectionManager)
        }
        .onChange(of: connectionManager.connectionState) { _, state in
            if state == .connected && step == .connect {
                showPairingSheet = false
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Spacing.lg) {
            FullBrandHeader()

            Text("This is Sovereign AI Remote — your private companion for the Centurion at home.\n\nYou stay in charge. Your Centurion works beside you.")
                .font(.body)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, Spacing.lg)
        }
    }

    private var connectStep: some View {
        VStack(spacing: Spacing.lg) {
            SheetHeader(
                title: "Link your Centurion",
                subtitle: "Scan the QR code on your Centurion's screen. It works from anywhere once TCP 9119 is reachable. Paste remains available as a fallback. Same Wi‑Fi is optional when you’re nearby."
            )

            AtmosphericSurface {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "app.connected.to.app.below.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(ColorTheme.accent())
                    Text("Linking turns on Crypto Chat — a private encrypted conversation public AIs do not offer.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Button {
                        UIApplication.shared.open(CenturionHelp.localRemoteTelegramPrivacy)
                    } label: {
                        Text("Privacy choices: local, Remote, or Telegram")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.accent())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Spacing.xs)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.lg)

            if connectionManager.connectionState == .connected {
                EncryptionStatusBadge(isEncrypted: connectionManager.isChannelEncrypted)
            }
        }
    }

    private var missionStep: some View {
        VStack(spacing: Spacing.lg) {
            SheetHeader(
                title: "Discover Your Mission",
                subtitle: "A quiet moment to reflect on your life."
            )

            AtmosphericSurface(showRim: true) {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(ColorTheme.accent().opacity(0.8))
                    Text("This is about you, not how your Sovereign behaves. You can return anytime from Home or Settings.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
            }
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
                .buttonStyle(CenturionPrimaryButtonStyle())
            case .connect:
                VStack(spacing: Spacing.md) {
                    if connectionManager.connectionState == .connected {
                        Button("Continue") {
                            withAnimation(Motion.standard) { step = .mission }
                            Haptics.lightTap()
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())
                    } else {
                        Button("Paste pairing code") {
                            showPairingSheet = true
                            Haptics.lightTap()
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())

                        Button("Skip for now") {
                            withAnimation(Motion.standard) { step = .mission }
                        }
                        .buttonStyle(CenturionGhostButtonStyle())
                    }
                }
            case .mission:
                VStack(spacing: Spacing.md) {
                    Button("Begin Mission Discovery") {
                        showMissionDiscovery = true
                        Haptics.mediumTap()
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())

                    Button("Skip — explore the app") {
                        finishOnboarding()
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
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
