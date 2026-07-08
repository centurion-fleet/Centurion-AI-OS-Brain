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
struct SplashView: View {
    @State private var phase: SplashPhase = .hidden
    @State private var glowPulse = false
    @State private var taglineOpacity = 0.0

    let onComplete: () -> Void

    enum SplashPhase {
        case hidden     // Initial — matches system launch screen
        case glow       // Amber glow emerges
        case globe      // Centurion globe forms
        case title      // Brand name appears
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

            // Brand name
            VStack(spacing: 4) {
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
            }
            .animation(Motion.appear.delay(0.2), value: phase)

            // Tap to continue hint
            if phase == .title || phase == .globe {
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
        }
        .onAppear {
            animateThroughPhases()
        }
        .onTapGesture {
            guard phase == .title || phase == .globe else { return }
            completeSplash()
        }
    }

    private func animateThroughPhases() {
        // Phase 1: Ambient glow emerges (matches launch screen → feels instant)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(Motion.heavy) { phase = .glow }
            withAnimation(Motion.heavy.repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }

        // Phase 2: Globe springs in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6, blendDuration: 0.3)) {
                phase = .globe
            }
        }

        // Phase 3: Title appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.appear) {
                phase = .title
            }
            withAnimation(Motion.appear.delay(0.4)) {
                taglineOpacity = 1.0
            }
        }

        // Auto-complete after enough time
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            completeSplash()
        }
    }

    private func completeSplash() {
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            phase = .complete
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onComplete()
        }
    }
}
