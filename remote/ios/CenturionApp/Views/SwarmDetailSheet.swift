import SwiftUI

/// Layer 2 — one Swarm expanded with a single human action when needed.
struct SwarmDetailSheet: View {
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @Environment(\.dismiss) private var dismiss

    let swarm: SwarmSummary
    var onDiscuss: ((SwarmSummary) -> Void)?

    @State private var showOrbital = false

    private var current: SwarmSummary {
        swarmStore.swarm(for: swarm.id) ?? swarm
    }

    private var missionLine: String? {
        swarmStore.missionGroundingLine(
            for: current,
            lifeMissionStatement: missionStore.mission.statement
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetChrome

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SwarmOrb(swarm: current, size: 180, showLabel: false)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.sm)

                    SheetHeader(
                        title: current.displayName,
                        subtitle: current.statusLabel
                    )

                    if let missionLine {
                        Text(missionLine)
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.md)
                    }

                    Text(current.objective)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, Spacing.md)

                    if let action = swarmStore.primaryActionTitle(for: current) {
                        Button(action) {
                            Haptics.lightTap()
                            handlePrimaryAction()
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())
                        .padding(.horizontal, Spacing.md)
                    }

                    if !swarmStore.signals(for: current.id).isEmpty {
                        signalsSection
                    }

                    if !swarmStore.outcomes(for: current.id).isEmpty {
                        outcomesSection
                    }

                    Button(showOrbital ? "Hide how it's working" : "Show how it's working") {
                        Haptics.lightTap()
                        withAnimation(Motion.standard) {
                            showOrbital.toggle()
                        }
                    }
                    .buttonStyle(CenturionGhostButtonStyle())

                    if showOrbital {
                        LoopVisualizationView(activity: liveActivity(from: current))
                            .centurionCard()
                            .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.bottom, Spacing.lg)
            }
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
    }

    private var sheetChrome: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(CenturionGhostButtonStyle())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Needs your choice", icon: "lightbulb.fill")
            ForEach(swarmStore.signals(for: current.id)) { signal in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(signal.message)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText())
                        .lineSpacing(3)
                    Button("I've decided") {
                        Haptics.lightTap()
                        swarmStore.resolveSignal(signal.id, connectionManager: connectionManager)
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .centurionCard()
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Ready for you", icon: "doc.richtext.fill")
            ForEach(swarmStore.outcomes(for: current.id)) { outcome in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.body)
                        .foregroundColor(ColorTheme.accent())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.description)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.primaryText())
                        Text("From \(outcome.ownerName)")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .centurionCard()
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func handlePrimaryAction() {
        if let signal = swarmStore.signals(for: current.id).first {
            swarmStore.resolveSignal(signal.id, connectionManager: connectionManager)
        }
        onDiscuss?(current)
    }

    private func liveActivity(from swarm: SwarmSummary) -> LiveActivity {
        let agents = swarm.participants
            .filter { $0.kind == .centurion }
            .map { participant in
                SubAgentActivity(
                    id: UUID(),
                    name: participant.name,
                    role: participant.role.rawValue,
                    status: participant.isActive ? .active : .waiting,
                    summary: swarm.objective,
                    progress: participant.isActive ? 0.6 : 0
                )
            }
        return LiveActivity(
            id: UUID(uuidString: swarm.id) ?? UUID(),
            phase: swarm.pulse == .active ? .executing : .planning,
            summary: swarm.objective,
            detail: swarm.displayName,
            progress: swarm.pulse == .complete ? 1 : 0.55,
            startedAt: swarm.updatedAt,
            subAgents: agents,
            estimatedCompletion: nil
        )
    }
}
