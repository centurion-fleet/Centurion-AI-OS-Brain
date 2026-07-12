import SwiftUI

/// The human's Life Mission as a quiet gravitational anchor — calmer than collaboration orbs.
/// Grounds the Home constellation; never competes with Swarm attention states.
struct MissionOrb: View {
    var size: CGFloat = 56
    var hasMission: Bool
    var missionSnippet: String = ""
    var showLabel: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 1.0
    @State private var mist: Double = 0.12
    @State private var highlightAngle: Double = 0

    private var accent: Color { ColorTheme.accent() }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                atmosphere
                compassRose
                decoArcs
                nucleus
                if !hasMission {
                    seedConstellation
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            if showLabel {
                Text(hasMission ? "Your mission" : "Discover your mission")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.mutedText())
                    .lineLimit(1)
            }
        }
        .onAppear { startMotion() }
        .onChange(of: hasMission) { _, _ in startMotion() }
    }

    private var accessibilityText: String {
        if hasMission, !missionSnippet.isEmpty {
            return "Your life mission. \(missionSnippet)"
        }
        if hasMission {
            return "Your life mission is set."
        }
        return "Discover your life mission."
    }

    private var atmosphere: some View {
        Circle()
            .fill(OrbDesign.atmosphereGradient(accent: accent))
            .frame(width: size * 1.15, height: size * 1.15)
            .scaleEffect(breath)
            .opacity(mist)
    }

    /// Subtle Art Deco compass — human north star, not agent topology.
    private var compassRose: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(accent.opacity(hasMission ? 0.14 : 0.07))
                    .frame(width: 1, height: size * 0.72)
                    .rotationEffect(.degrees(Double(index) * 60 + highlightAngle * 0.15))
            }
            Circle()
                .stroke(accent.opacity(0.08), lineWidth: 0.5)
                .frame(width: size * 0.62, height: size * 0.62)
        }
    }

    private var decoArcs: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.02, to: 0.22)
                    .stroke(
                        OrbDesign.metallicRimGradient(accent: accent),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                    .frame(width: size * 0.88, height: size * 0.88)
                    .rotationEffect(.degrees(Double(index) * 120 + highlightAngle))
            }
        }
    }

    private var nucleus: some View {
        ZStack {
            Circle()
                .fill(OrbDesign.coreGradient(accent: accent, intensity: hasMission ? 1.0 : 0.55))
                .frame(width: size * 0.34, height: size * 0.34)
                .scaleEffect(breath)
                .shadow(color: accent.opacity(hasMission ? 0.35 : 0.15), radius: size * 0.08)

            Circle()
                .fill(OrbDesign.pearlHighlight.opacity(hasMission ? 0.55 : 0.25))
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: -size * 0.04, y: -size * 0.05)
                .blur(radius: 0.5)
        }
    }

    /// Dormant state — potential constellations not yet named.
    private var seedConstellation: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let angle = Double(index) * 72 + 18
                let radians = angle * .pi / 180
                let orbit = size * 0.38
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 3, height: 3)
                    .offset(x: cos(radians) * orbit, y: sin(radians) * orbit)
            }
        }
    }

    private func startMotion() {
        breath = 1.0
        mist = hasMission ? 0.18 : 0.1
        highlightAngle = 0
        guard !reduceMotion else { return }

        withAnimation(.easeInOut(duration: OrbDesign.Duration.missionBreath).repeatForever(autoreverses: true)) {
            breath = hasMission ? 1.05 : 1.03
            mist = hasMission ? 0.24 : 0.14
        }
        withAnimation(.linear(duration: 48).repeatForever(autoreverses: false)) {
            highlightAngle = 360
        }
    }
}
