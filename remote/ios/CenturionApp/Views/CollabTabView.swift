import SwiftUI

/// Collab tab — constellation of collaboration orbs (not a Kanban board).
struct CollabTabView: View {
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore

    @State private var selectedSwarm: SwarmSummary?
    @State private var showGoalForm = false
    @State private var showAdvanced = false
    @State private var filterNeedsYou = false
    @State private var gatewayRunning: Bool?
    @State private var gatewayBusy = false
    @State private var gatewayMessage: String?

    private var displayed: [SwarmSummary] {
        let sorted = swarmStore.heroSwarms
        if filterNeedsYou {
            let needs = sorted.filter {
                $0.pulse == .waiting || $0.pulse == .attention || $0.pulse == .blocked
            }
            return needs.isEmpty ? sorted : needs
        }
        return sorted
    }

    private var empty: Bool { swarmStore.heroSwarms.isEmpty }

    var body: some View {
        TabPageChrome(screenTitle: nil, navigationBackTitle: "Collab", header: {
            HStack {
                Text("Collab")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.mutedText())
                Spacer(minLength: 0)
                if swarmStore.isShowingOfflineCache {
                    Text("Last known")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)
        }, content: {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if gatewayRunning == false {
                            gatewayBanner
                        }

                        if empty {
                            emptyFirstRun
                        } else {
                            filterChips
                            orbGrid
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 88)
                }

                fab
            }
        })
        .sheet(item: $selectedSwarm) { swarm in
            SwarmDetailSheet(swarm: swarm)
                .environmentObject(swarmStore)
        }
        .sheet(isPresented: $showGoalForm) {
            SwarmConnectSheet(presentation: .goalFirst)
                .environmentObject(connectionManager)
                .environmentObject(swarmStore)
                .environmentObject(missionStore)
        }
        .sheet(isPresented: $showAdvanced) {
            SwarmConnectSheet(presentation: .advanced)
                .environmentObject(connectionManager)
                .environmentObject(swarmStore)
                .environmentObject(missionStore)
        }
        .task(id: connectionManager.isCryptoChatReady) {
            await refreshAll()
        }
        .refreshable {
            await refreshAll()
        }
    }

    private var gatewayBanner: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(gatewayMessage ?? "Gateway is stopped on this Brain. Workers wait until it starts.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.primaryText())
            Button {
                Task { await startGateway() }
            } label: {
                Text("Start gateway")
                    .frame(minHeight: 44)
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .disabled(gatewayBusy || !connectionManager.isCryptoChatReady)
        }
        .padding(Spacing.md)
        .centurionCard(elevated: true)
    }

    private var emptyFirstRun: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Give your Sovereign a goal")
                .font(.title3.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText())
            Text("Workers on this Brain will research, draft, check, then synthesize. Gateway must be running on the desk.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.lightTap()
                showGoalForm = true
            } label: {
                Text("Form swarm")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .disabled(!connectionManager.isCryptoChatReady)
            Button {
                Haptics.lightTap()
                showAdvanced = true
            } label: {
                Text("Join another owner (Mission Control)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            if !connectionManager.isCryptoChatReady {
                Text("Link your Sovereign in You first.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
        .padding(Spacing.md)
        .centurionCard(elevated: true)
    }

    private var filterChips: some View {
        HStack(spacing: Spacing.sm) {
            filterChip("Needs you", active: filterNeedsYou) { filterNeedsYou = true }
            filterChip("All", active: !filterNeedsYou) { filterNeedsYou = false }
            Spacer()
        }
    }

    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.lightTap()
            withAnimation(Motion.standard) { action() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(active ? ColorTheme.onAccent() : ColorTheme.primaryText())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(active ? ColorTheme.accent() : ColorTheme.surface())
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var orbGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.md)], spacing: Spacing.lg) {
            ForEach(displayed) { swarm in
                Button {
                    Haptics.lightTap()
                    selectedSwarm = swarm
                } label: {
                    SwarmOrb(
                        swarm: swarm,
                        size: (swarm.pulse == .waiting || swarm.pulse == .attention) ? 128 : 112,
                        showLabel: true,
                        missionLine: swarmStore.missionGroundingLine(
                            for: swarm,
                            lifeMissionStatement: missionStore.hasCompletedMissionSetup
                                ? missionStore.mission.statement
                                : nil
                        )
                    )
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fab: some View {
        Button {
            Haptics.lightTap()
            showGoalForm = true
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundColor(ColorTheme.onAccent())
                .frame(width: 56, height: 56)
                .background(ColorTheme.accent())
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Spacing.md)
        .padding(.bottom, Spacing.md)
        .accessibilityLabel("Form swarm")
        .disabled(!connectionManager.isCryptoChatReady)
    }

    private func refreshAll() async {
        if connectionManager.isCryptoChatReady {
            await swarmStore.refresh(from: connectionManager)
            await probeGateway()
        }
    }

    private func probeGateway() async {
        guard connectionManager.isCryptoChatReady else { return }
        do {
            let status = try await connectionManager.refreshGatewayStatus()
            gatewayRunning = (status["running"] as? Bool) == true
            gatewayMessage = gatewayRunning == true
                ? nil
                : "Gateway is stopped. Form can still create the board; workers wait until it starts."
        } catch {
            gatewayRunning = false
            gatewayMessage = error.localizedDescription
        }
    }

    private func startGateway() async {
        gatewayBusy = true
        defer { gatewayBusy = false }
        do {
            _ = try await connectionManager.gatewayStart()
            await probeGateway()
        } catch {
            gatewayMessage = error.localizedDescription
        }
    }
}
