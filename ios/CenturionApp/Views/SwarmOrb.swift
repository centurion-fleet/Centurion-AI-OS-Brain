import SwiftUI

/// Living orb for one collaboration — movement communicates state more than text.
struct SwarmOrb: View {
    let swarm: SwarmSummary
    var size: CGFloat = 120
    var showLabel: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var beacon: CGFloat = 0
    @State private var throb: CGFloat = 1.0
    @State private var mist: Double = 0.14
    @State private var ripple: CGFloat = 0
    @State private var filamentGlow: Double = 0.35
    @State private var orbitDrift: Double = 0

    private var accent: Color { ColorTheme.accent() }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                atmosphereVeil
                invitationRipple
                decoArcRing
                haloRing
                orbitRing
                activeFilaments
                participantNodes
                core
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            if showLabel {
                VStack(spacing: 2) {
                    Text(swarm.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                        .lineLimit(1)
                    Text(swarm.statusLabel)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(1)
                }
                .frame(maxWidth: size + 40)
            }
        }
        .onAppear { startMotion() }
        .onChange(of: swarm.pulse) { _, _ in startMotion() }
    }

    private var accessibilityText: String {
        "\(swarm.displayName). \(swarm.statusLabel). \(swarm.objective)"
    }

    // MARK: - Layers

    private var atmosphereVeil: some View {
        Circle()
            .fill(OrbDesign.atmosphereGradient(accent: accent))
            .frame(width: size, height: size)
            .scaleEffect(breath * (swarm.pulse == .blocked ? 0.94 : 1.0))
            .opacity(mist * (swarm.pulse == .blocked ? 0.65 : 1.0))
    }

    /// Respectful invitation — warm ripple, never alarm red.
    @ViewBuilder
    private var invitationRipple: some View {
        if swarm.pulse == .waiting || swarm.pulse == .attention {
            Circle()
                .stroke(OrbDesign.humanGold.opacity(0.35 - Double(ripple) * 0.3), lineWidth: 1.5)
                .frame(width: size * (0.78 + ripple * 0.22), height: size * (0.78 + ripple * 0.22))
                .opacity(1 - Double(ripple) * 0.85)
        }
    }

    private var decoArcRing: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.04, to: 0.2)
                    .stroke(
                        OrbDesign.metallicRimGradient(accent: accent),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: size * 0.96, height: size * 0.96)
                    .rotationEffect(.degrees(Double(index) * 120 + orbitDrift))
                    .opacity(swarm.pulse == .complete ? 0.25 : 0.55)
            }
        }
    }

    @ViewBuilder
    private var haloRing: some View {
        let thickness: CGFloat = {
            switch swarm.pulse {
            case .waiting, .attention: return 3
            case .blocked: return 2.5
            case .active: return 2
            default: return 1.5
            }
        }()
        Circle()
            .stroke(
                haloStroke,
                style: StrokeStyle(lineWidth: thickness, lineCap: .round)
            )
            .frame(width: size * 0.92, height: size * 0.92)
            .scaleEffect(1 + beacon * 0.08)
    }

    private var haloStroke: some ShapeStyle {
        if swarm.pulse == .waiting || swarm.pulse == .attention {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [OrbDesign.humanGold.opacity(0.7), accent.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(accent.opacity(haloOpacity))
    }

    private var haloOpacity: Double {
        switch swarm.pulse {
        case .complete: return 0.15
        case .blocked: return 0.25
        case .waiting, .attention: return 0.55
        case .active: return 0.4
        default: return 0.28
        }
    }

    private var orbitRing: some View {
        Circle()
            .stroke(accent.opacity(0.12), lineWidth: 1)
            .frame(width: size * 0.78, height: size * 0.78)
    }

    @ViewBuilder
    private var activeFilaments: some View {
        if swarm.pulse == .active {
            let satellites = swarm.participants.filter { $0.kind == .centurion }.prefix(4)
            let orbit = size * 0.34
            ForEach(Array(satellites.enumerated()), id: \.element.id) { index, participant in
                if participant.isActive {
                    let angle = rotation + Double(index) * (360.0 / Double(max(satellites.count, 1)))
                    let radians = angle * .pi / 180
                    filament(to: CGPoint(x: cos(radians) * orbit, y: sin(radians) * orbit))
                }
            }
        }
    }

    private func filament(to offset: CGPoint) -> some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: offset)
        }
        .stroke(
            LinearGradient(
                colors: [accent.opacity(filamentGlow), accent.opacity(0.05)],
                startPoint: .center,
                endPoint: UnitPoint(x: 0.5 + offset.x / size, y: 0.5 + offset.y / size)
            ),
            style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
        )
    }

    private var core: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.1))
                .frame(width: size * 0.36, height: size * 0.36)
                .scaleEffect(breath * throb)
                .blur(radius: swarm.pulse == .active ? 1 : 0)

            Circle()
                .fill(OrbDesign.coreGradient(accent: accent, intensity: coreIntensity))
                .frame(width: size * 0.22, height: size * 0.22)
                .scaleEffect(breath * throb)
                .shadow(color: accent.opacity(0.45), radius: size * 0.06)

            if swarm.pulse != .complete && swarm.pulse != .blocked {
                Circle()
                    .fill(OrbDesign.pearlHighlight.opacity(0.5))
                    .frame(width: size * 0.06, height: size * 0.06)
                    .offset(x: -size * 0.03, y: -size * 0.04)
            }

            if swarm.pulse == .complete {
                Circle()
                    .stroke(OrbDesign.humanGold.opacity(0.35), lineWidth: 1)
                    .frame(width: size * 0.3, height: size * 0.3)
            }
        }
    }

    private var coreIntensity: Double {
        switch swarm.pulse {
        case .complete: return 0.35
        case .blocked: return 0.55
        case .active: return 1.0
        case .waiting, .attention: return 0.9
        default: return 0.75
        }
    }

    @ViewBuilder
    private var participantNodes: some View {
        let satellites = swarm.participants.filter { $0.kind == .centurion }.prefix(4)
        let orbit = size * 0.34
        ForEach(Array(satellites.enumerated()), id: \.element.id) { index, participant in
            let angle = rotation + Double(index) * (360.0 / Double(max(satellites.count, 1)))
            let radians = angle * .pi / 180
            let x = cos(radians) * orbit
            let y = sin(radians) * orbit
            let nodeColor = OrbDesign.centurionAccent(index: index)
            ZStack {
                if participant.isActive && swarm.pulse == .active {
                    Circle()
                        .fill(nodeColor.opacity(0.25))
                        .frame(width: 18, height: 18)
                        .blur(radius: 2)
                }
                Circle()
                    .fill(nodeColor.opacity(participant.isActive ? 0.9 : 0.35))
                    .frame(width: participant.isActive ? 10 : 7, height: participant.isActive ? 10 : 7)
                    .overlay {
                        if participant.isActive {
                            Circle()
                                .stroke(nodeColor.opacity(0.5), lineWidth: 1)
                                .frame(width: 16, height: 16)
                        }
                    }
            }
            .offset(x: x, y: y)
        }
        if swarm.participants.contains(where: { $0.kind == .human }) {
            let humanScale: CGFloat = 1.0 + beacon * 0.18
            Circle()
                .fill(OrbDesign.humanGold.opacity(0.9))
                .frame(width: 8 * humanScale, height: 8 * humanScale)
                .shadow(color: OrbDesign.humanGold.opacity(0.35), radius: 4)
                .offset(x: -orbit * 0.55, y: orbit * 0.55)
        }
    }

    // MARK: - Motion (states locked — emotional layers only)

    private func startMotion() {
        breath = 1.0
        rotation = 0
        beacon = 0
        throb = 1.0
        mist = 0.14
        ripple = 0
        filamentGlow = 0.35
        orbitDrift = 0
        guard !reduceMotion else { return }

        withAnimation(.easeInOut(duration: OrbDesign.Duration.mistDrift).repeatForever(autoreverses: true)) {
            mist = 0.22
        }
        withAnimation(.linear(duration: 36).repeatForever(autoreverses: false)) {
            orbitDrift = 360
        }

        switch swarm.pulse {
        case .idle, .forming:
            withAnimation(.easeInOut(duration: OrbDesign.Duration.idleBreath).repeatForever(autoreverses: true)) {
                breath = 1.06
            }
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        case .active:
            withAnimation(.easeInOut(duration: OrbDesign.Duration.activeBreath).repeatForever(autoreverses: true)) {
                breath = 1.08
            }
            withAnimation(.linear(duration: OrbDesign.Duration.activeOrbit).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                filamentGlow = 0.75
            }
        case .attention:
            withAnimation(.easeOut(duration: OrbDesign.Duration.attentionBeacon).repeatForever(autoreverses: false)) {
                beacon = 1
            }
            withAnimation(.easeOut(duration: OrbDesign.Duration.invitationRipple).repeatForever(autoreverses: false)) {
                ripple = 1
            }
            withAnimation(.easeInOut(duration: OrbDesign.Duration.idleBreath).repeatForever(autoreverses: true)) {
                breath = 1.04
            }
        case .waiting:
            withAnimation(.easeInOut(duration: OrbDesign.Duration.waitingBeacon).repeatCount(2, autoreverses: true)) {
                beacon = 1
            }
            withAnimation(.easeOut(duration: OrbDesign.Duration.invitationRipple).repeatCount(2, autoreverses: false)) {
                ripple = 1
            }
        case .blocked:
            withAnimation(.easeInOut(duration: OrbDesign.Duration.blockedThrob).repeatForever(autoreverses: true)) {
                throb = 1.12
            }
            withAnimation(.easeInOut(duration: OrbDesign.Duration.blockedThrob).repeatForever(autoreverses: true)) {
                mist = 0.08
            }
        case .complete:
            mist = 0.1
        }
    }
}
