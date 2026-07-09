import SwiftUI

/// A living orbital visualization of the Centurion's agents at work.
/// Each agent orbits the center, connection lines pulse with data flow,
/// and the phase indicator shows where we are in the loop.
///
/// This is the "watch the magic happen" experience — mesmerizing enough
/// that users open the app just to see what their Centurion is doing.
struct LoopVisualizationView: View {
    let activity: LiveActivity
    @State private var rotation: Double = 0
    @State private var centerPulse: CGFloat = 1.0
    @State private var lineGlow: [Bool]

    private let agentColors: [Color] = [
        ColorTheme.accent(),
        Color(red: 0.3, green: 0.85, blue: 0.6),
        Color(red: 0.6, green: 0.4, blue: 1.0),
        Color(red: 1.0, green: 0.6, blue: 0.2),
    ]

    init(activity: LiveActivity) {
        self.activity = activity
        _lineGlow = State(initialValue: Array(repeating: false, count: max(activity.subAgents.count, 4)))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Orbital visualization
            ZStack {
                // Outer orbit ring
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.08), lineWidth: 1)
                    .frame(width: 200, height: 200)

                // Inner orbit ring
                Circle()
                    .stroke(ColorTheme.accent().opacity(0.12), lineWidth: 1.5)
                    .frame(width: 150, height: 150)

                // Connection lines from center to agents
                ForEach(0..<min(activity.subAgents.count, 4), id: \.self) { i in
                    let angle = angleForAgent(i)
                    ConnectionLine(
                        angle: angle,
                        length: 75,
                        isGlowing: lineGlow.indices.contains(i) ? lineGlow[i] : false
                    )
                }

                // Agent nodes on the orbit
                ForEach(0..<min(activity.subAgents.count, 4), id: \.self) { i in
                    AgentNode(
                        name: activity.subAgents[i].name,
                        status: activity.subAgents[i].status,
                        color: agentColors[i % agentColors.count],
                        angle: angleForAgent(i),
                        distance: 75
                    )
                }

                // Center — Centurion brain
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(ColorTheme.accent().opacity(0.1))
                        .frame(width: 56, height: 56)
                        .scaleEffect(centerPulse)

                    // Inner glow
                    Circle()
                        .fill(ColorTheme.accent().opacity(0.2))
                        .frame(width: 40, height: 40)

                    // Core
                    Circle()
                        .fill(ColorTheme.accent())
                        .frame(width: 20, height: 20)
                        .shadow(color: ColorTheme.accent().opacity(0.6), radius: 10)
                }
            }
            .frame(height: 220)

            // Phase + progress below the visualization
            VStack(spacing: 4) {
                Text(activity.phase.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(phaseColor)
                    .tracking(3)

                Text(activity.summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ColorTheme.border())
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(phaseColor)
                            .frame(width: geo.size.width * activity.progress, height: 3)
                            .animation(.easeInOut(duration: 1), value: activity.progress)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private var phaseColor: Color {
        switch activity.phase {
        case .discovering: return ColorTheme.accent()
        case .planning: return Color(red: 0.6, green: 0.4, blue: 1.0)
        case .executing: return ColorTheme.accent()
        case .verifying: return .green
        case .idle: return ColorTheme.mutedText()
        }
    }

    private func angleForAgent(_ index: Int) -> Double {
        let baseAngle = Double(index) * (360.0 / Double(min(activity.subAgents.count, 4)))
        return baseAngle + rotation
    }

    private func startAnimations() {
        // Continuous rotation
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            rotation = 360
        }

        // Center pulsing
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            centerPulse = 1.15
        }

        // Connection line glow — stagger each agent
        for i in 0..<min(activity.subAgents.count, 4) {
            let delay = Double(i) * 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                startLineGlow(for: i)
            }
        }
    }

    private func startLineGlow(for index: Int) {
        guard lineGlow.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            lineGlow[index] = true
        }
    }
}

// MARK: - Agent Node

private struct AgentNode: View {
    let name: String
    let status: SubAgentActivity.SubAgentStatus
    let color: Color
    let angle: Double
    let distance: CGFloat
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radians = angle * .pi / 180
            let x = center.x + distance * cos(radians)
            let y = center.y + distance * sin(radians)

            ZStack {
                // Outer ring
                Circle()
                    .stroke(color.opacity(status == .active ? 0.6 : 0.2), lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                    .scaleEffect(pulse)

                // Inner fill
                Circle()
                    .fill(color.opacity(status == .active ? 0.2 : 0.05))
                    .frame(width: 26, height: 26)

                // Status dot
                Circle()
                    .fill(status == .active ? color : (status == .completed ? .green : color.opacity(0.3)))
                    .frame(width: 8, height: 8)

                // Name label
                Text(name)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundColor(status == .active ? color : color.opacity(0.4))
                    .offset(y: 22)
            }
            .position(x: x, y: y)
        }
        .onAppear {
            if status == .active {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = 1.2
                }
            }
        }
    }
}

// MARK: - Connection Line

private struct ConnectionLine: View {
    let angle: Double
    let length: CGFloat
    let isGlowing: Bool

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radians = angle * .pi / 180
            let endX = center.x + length * cos(radians)
            let endY = center.y + length * sin(radians)

            Path { path in
                path.move(to: center)
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(
                ColorTheme.accent().opacity(isGlowing ? 0.25 : 0.06),
                style: StrokeStyle(lineWidth: isGlowing ? 1.5 : 0.5, dash: [3, 4])
            )
        }
    }
}
