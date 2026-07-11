import SwiftUI

/// First-moment experience — matches the system launch screen so the handoff feels instant.
/// Main app loads underneath during the ~1s splash so the transition feels immediate.
struct SplashView: View {
    @State private var phase: SplashPhase = .glow
    @State private var contentOpacity: Double = 1
    @State private var taglineOpacity = 0.0
    @State private var missionHorizonOpacity = 0.0
    @State private var didComplete = false

    let onComplete: () -> Void

    enum SplashPhase {
        case glow
        case globe
        case title
        case horizon
    }

    var body: some View {
        ZStack {
            ColorTheme.background()
                .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ColorTheme.accent().opacity(0.22),
                            ColorTheme.accent().opacity(0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)

            ZStack {
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.2), lineWidth: 1)
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.3), lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.45), lineWidth: 2)
                    .frame(width: 105, height: 105)
            }
            .opacity(phase == .glow ? 0.6 : 1)

            ZStack {
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.4), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(ColorTheme.accent().opacity(0.2))
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(ColorTheme.accent())
                    .frame(width: 12, height: 12)
            }
            .scaleEffect(phase == .glow ? 0.8 : 1.0)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 140)

                Text("CENTURION")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())
                    .tracking(6)
                    .opacity(phase == .glow ? 0.4 : 1)

                Text("Live Your Personal Mission")
                    .font(.system(size: 12))
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(3)
                    .opacity(taglineOpacity)

                Rectangle()
                    .fill(ColorTheme.accent().opacity(0.3))
                    .frame(width: 60, height: 1)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Text("MISSION HORIZON")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(8)
                    .opacity(missionHorizonOpacity)

                Text("REMOTE CONTROL  ·  v3.0.0")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(4)
                    .opacity(missionHorizonOpacity * 0.7)
                    .padding(.top, 6)
            }
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
        withAnimation(.easeOut(duration: 0.2)) { phase = .globe }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .title
                taglineOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .horizon
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
