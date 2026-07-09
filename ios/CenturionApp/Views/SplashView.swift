import SwiftUI

/// Award-winning first-moment experience — not a splash screen, but the app's
/// first breath. Matches the system launch screen (deep forest + amber glow)
/// so it feels instant, then animates in the Centurion's presence with weight
/// and warmth before transitioning to the main app.
///
/// Apple Design Award principle: "Make it indistinguishable from the first real
/// screen." The system launch screen (UILaunchScreen in Info.plist) uses the
/// same deep forest background. When this view appears, it feels like the app
/// was already running — then the glow, globe, and type enter with spring physics.
///
/// Remote Control theme: The iPhone is a remote for the Linux brain. The concentric
/// signal rings, the pairing ceremony feel, and the "REMOTE CONTROL" descriptor all
/// reinforce that this app isn't an AI — it's a conduit to one.
/// Controls what shows below the splash — loading spinner while app initialises
enum SplashState {
    case animating          // The 3-second brand animation
    case loading(String)    // Animation done, waiting for app: "Connecting to Centurion…"
    case ready              // Transition to app
}

struct SplashView: View {
    @State private var phase: SplashPhase = .hidden
    @State private var glowPulse = false
    @State private var signalRingScale: CGFloat = 0.0
    @State private var signalRingOpacity: Double = 0.0
    @State private var taglineOpacity = 0.0
    @State private var missionHorizonOpacity = 0.0
    @State private var splashState: SplashState = .animating
    @State private var loadingStep = 0

    let isReady: Bool           // App signals this when initialisation is done
    let onComplete: () -> Void

    private let loadingMessages = [
        "Waking the Fleet…",
        "Establishing secure channel…",
        "Loading your mission…",
        "Readying your Centurion…",
    ]

    enum SplashPhase {
        case hidden     // Initial — matches system launch screen
        case glow       // Amber glow emerges
        case globe      // Centurion globe forms
        case title      // Brand name appears
        case horizon    // Mission Horizon tag appears
        case complete   // Transition to app
    }

    var body: some View {
        ZStack {
            // Deep forest background — matches UILaunchScreen
            ColorTheme.background()
                .ignoresSafeArea()

            // Ambient glow behind the globe
            Circle()
                .fill(ColorTheme.accent().opacity(glowPulse ? 0.15 : 0.05))
                .frame(width: 200, height: 200)
                .blur(radius: 40)
                .scaleEffect(glowPulse ? 1.2 : 0.8)
                .opacity(phase == .hidden ? 0 : 1)

            // Remote control signal rings — concentric circles that pulse outward
            // like a remote control broadcasting its presence
            ZStack {
                // Outer ring
                Circle()
                    .stroke(ColorTheme.accent().opacity(signalRingOpacity * 0.15), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(signalRingScale)

                // Middle ring
                Circle()
                    .stroke(ColorTheme.accent().opacity(signalRingOpacity * 0.25), lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(signalRingScale * 0.85)

                // Inner ring
                Circle()
                    .stroke(ColorTheme.accent().opacity(signalRingOpacity * 0.4), lineWidth: 2)
                    .frame(width: 105, height: 105)
                    .scaleEffect(signalRingScale * 0.7)
            }
            .opacity(phase == .globe || phase == .title || phase == .horizon ? 1 : 0)

            // Centurion glass globe — amber sphere with impressed pattern
            ZStack {
                // Outer glass sphere
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.4), lineWidth: 1.5)
                    .frame(width: 88, height: 88)

                // Inner glow
                Circle()
                    .fill(ColorTheme.accent().opacity(0.2))
                    .frame(width: 76, height: 76)

                // Impressed geometric lines (simplified)
                ForEach(0..<6) { i in
                    let angle = Double(i) * 60.0
                    Rectangle()
                        .fill(ColorTheme.accent().opacity(0.15))
                        .frame(width: 1, height: 60)
                        .rotationEffect(.degrees(angle))
                }

                // Core amber light
                Circle()
                    .fill(ColorTheme.accent())
                    .frame(width: 12, height: 12)
                    .shadow(color: ColorTheme.accent().opacity(0.6), radius: 8)
            }
            .scaleEffect(phase == .globe ? 1.0 : 0.3)
            .opacity(phase == .hidden ? 0 : 1)
            .rotationEffect(.degrees(phase == .complete ? 360 : 0))

            // Brand name + Mission Horizon
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 140)

                Text("CENTURION")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())
                    .tracking(6)
                    .opacity(phase == .title ? 1 : 0)
                    .offset(y: phase == .title ? 0 : 12)

                Text("Live Your Personal Mission")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(3)
                    .opacity(taglineOpacity)
                    .offset(y: phase == .title ? 0 : 8)

                // Thin amber divider
                Rectangle()
                    .fill(ColorTheme.accent().opacity(0.3))
                    .frame(width: 60, height: 1)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                // Mission Horizon — the release codename
                Text("MISSION HORIZON")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(8)
                    .opacity(missionHorizonOpacity)

                // Remote Control descriptor
                Text("REMOTE CONTROL  ·  v3.0.0")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(4)
                    .opacity(missionHorizonOpacity * 0.7)
                    .padding(.top, 6)
            }
            .animation(Motion.appear.delay(0.2), value: phase)

            // Tap to continue hint — shown during animation phase
            if case .animating = splashState, phase == .title || phase == .globe || phase == .horizon {
                VStack {
                    Spacer()
                    Text("Tap anywhere to begin")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundColor(ColorTheme.mutedText())
                        .opacity(glowPulse ? 0.6 : 0.3)
                        .padding(.bottom, Spacing.xxl)
                }
                .transition(.opacity)
            }

            // Loading indicator — shown after animation completes, while waiting for init
            if case let .loading(message) = splashState {
                VStack {
                    Spacer()
                    // Pulsing amber dot
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ColorTheme.accent())
                            .frame(width: 6, height: 6)
                            .opacity(glowPulse ? 1.0 : 0.3)

                        Text(message)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(ColorTheme.mutedText())
                    }
                    .padding(.bottom, Spacing.xxl)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            animateThroughPhases()
        }
        .onTapGesture {
            guard phase == .title || phase == .globe || phase == .horizon else { return }
            skipToLoading()
        }
        .onChange(of: isReady) { ready in
            if ready, case .loading = splashState {
                completeSplash()
            }
        }
    }

    private func animateThroughPhases() {
        // Phase 1: Ambient glow emerges immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(Motion.heavy) { phase = .glow }
            withAnimation(Motion.heavy.repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }

        // Signal rings pulse outward like a remote searching for its console
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.6).repeatForever(autoreverses: true)) {
                signalRingScale = 1.0
                signalRingOpacity = 1.0
            }
        }

        // Phase 2: Globe springs in quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.2)) {
                phase = .globe
            }
        }

        // Phase 3: Title appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(Motion.appear) {
                phase = .title
            }
            withAnimation(Motion.appear.delay(0.3)) {
                taglineOpacity = 1.0
            }
        }

        // Phase 4: Mission Horizon + Remote Control reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.appear) {
                phase = .horizon
                missionHorizonOpacity = 1.0
            }
        }

        // Auto-complete — transition to loading state, wait for app readiness
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            transitionToLoading()
        }
    }

    /// Skip the brand animation and go straight to app readiness wait
    private func skipToLoading() {
        Haptics.lightTap()
        transitionToLoading()
    }

    /// After brand animation completes, show loading indicator while app initialises
    private func transitionToLoading() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            phase = .complete
        }
        // Keep globe + brand visible, add loading indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                splashState = .loading(loadingMessages[0])
            }
            startLoadingMessages()
            // If app is somehow already ready, complete immediately
            if isReady {
                completeSplash()
            }
        }
    }

    /// Cycle through loading messages every 2.5s to feel alive
    private func startLoadingMessages() {
        guard !isReady else { return }
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { timer in
            guard case .loading = splashState, !isReady else {
                timer.invalidate()
                return
            }
            let nextIndex = (loadingStep + 1) % loadingMessages.count
            withAnimation(.easeInOut(duration: 0.3)) {
                loadingStep = nextIndex
                splashState = .loading(loadingMessages[nextIndex])
            }
        }
    }

    private func completeSplash() {
        guard splashState != .ready else { return }
        splashState = .ready
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            phase = .complete
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onComplete()
        }
    }
}
