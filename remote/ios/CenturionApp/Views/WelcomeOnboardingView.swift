import SwiftUI

/// First-run welcome — the same page as the chat surface, not a different app.
///
/// ⚠️ This file used to wear the five-tab dashboard's forest/ivory skin
/// (`ColorTheme`, `AtmosphericSurface`, `FullBrandHeader`). That meant the first
/// screen a customer ever saw looked like a product they could not reach once
/// they pressed Continue. Signum is the app; onboarding is page one of it.
///
/// Copy is unchanged. Only the skin is.
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
            SignumTheme.cream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                switch step {
                case .welcome:
                    welcomeStep
                case .connect:
                    connectStep
                case .mission:
                    missionStep
                }

                Spacer(minLength: 24)

                primaryButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SignumTheme.Metrics.screenPadding)
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
        .onChange(of: connectionManager.connectionState) { _, _ in
            dismissPairingIfLinked()
        }
        .onChange(of: connectionManager.transportPreference) { _, _ in
            dismissPairingIfLinked()
        }
        .onReceive(connectionManager.relayAway.$isConnected) { _ in
            dismissPairingIfLinked()
        }
    }

    private func dismissPairingIfLinked() {
        if connectionManager.isCryptoChatReady && step == .connect {
            showPairingSheet = false
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            SignumMark(size: 56, starOpacity: 0.16)
                .padding(.bottom, 6)

            Text("Your Centurion,\nin your pocket.")
                .font(SignumTheme.serif(38))
                .foregroundStyle(SignumTheme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("This is Sovereign AI Remote — your private companion for the Centurion at home.\n\nYou stay in charge. Your Centurion works beside you.")
                .font(SignumTheme.ui(16))
                .foregroundStyle(SignumTheme.muted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            eyebrow("STEP 2 · LINK")

            Text("Connect to your Brain")
                .font(SignumTheme.serif(30))
                .foregroundStyle(SignumTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Scan the QR code on your Brain while you’re on home Wi‑Fi — that pairs Crypto Chat. After you enable Chat from anywhere on the Brain, the same app can continue Crypto Chat away from home (no home IP or port-forward). Paste remains a fallback.")
                .font(SignumTheme.ui(15.5))
                .foregroundStyle(SignumTheme.muted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(SignumTheme.goldDeep)
                        Text("Linking turns on Crypto Chat — a private encrypted conversation public AIs do not offer.")
                            .font(SignumTheme.ui(14))
                            .foregroundStyle(SignumTheme.ink.opacity(0.86))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        UIApplication.shared.open(CenturionHelp.localRemoteTelegramPrivacy)
                    } label: {
                        Text("Privacy choices: local, Remote, or Telegram")
                            .font(SignumTheme.ui(13, .medium))
                            .foregroundStyle(SignumTheme.goldDeep)
                    }
                    .buttonStyle(.plain)
                }
            }

            if connectionManager.isCryptoChatReady {
                EncryptionStatusBadge(isEncrypted: connectionManager.isChannelEncrypted)
            }
        }
    }

    private var missionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            eyebrow("STEP 3 · YOU")

            Text("Discover your mission")
                .font(SignumTheme.serif(30))
                .foregroundStyle(SignumTheme.ink)

            Text("A quiet moment to reflect on your life.")
                .font(SignumTheme.ui(15.5))
                .foregroundStyle(SignumTheme.muted)

            card {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(SignumTheme.goldDeep)
                    Text("This is about you, not how your Sovereign behaves. You can return anytime from Home or Settings.")
                        .font(SignumTheme.ui(14))
                        .foregroundStyle(SignumTheme.ink.opacity(0.86))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Pieces

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(SignumTheme.mono(10, .semibold))
            .tracking(1.4)
            .foregroundStyle(SignumTheme.muted)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(SignumTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SignumTheme.hair, lineWidth: 1)
            )
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
                .buttonStyle(SignumPrimaryButtonStyle())
            case .connect:
                VStack(spacing: 10) {
                    if connectionManager.isCryptoChatReady {
                        Button("Continue") {
                            withAnimation(Motion.standard) { step = .mission }
                            Haptics.lightTap()
                        }
                        .buttonStyle(SignumPrimaryButtonStyle())
                    } else {
                        Button("Start pairing") {
                            showPairingSheet = true
                            Haptics.lightTap()
                        }
                        .buttonStyle(SignumPrimaryButtonStyle())

                        Button("Skip for now") {
                            withAnimation(Motion.standard) { step = .mission }
                        }
                        .buttonStyle(SignumGhostButtonStyle())
                    }
                }
            case .mission:
                VStack(spacing: 10) {
                    Button("Begin Mission Discovery") {
                        showMissionDiscovery = true
                        Haptics.mediumTap()
                    }
                    .buttonStyle(SignumPrimaryButtonStyle())

                    Button("Skip — explore the app") {
                        finishOnboarding()
                    }
                    .buttonStyle(SignumGhostButtonStyle())
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        Haptics.success()
        onComplete()
    }
}

// MARK: - Button styles for the page

/// The one primary action on a Signum page: ink capsule, cream label.
struct SignumPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SignumTheme.ui(15, .medium))
            .foregroundStyle(SignumTheme.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(SignumTheme.ink)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SignumGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SignumTheme.ui(14, .medium))
            .foregroundStyle(SignumTheme.goldDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
