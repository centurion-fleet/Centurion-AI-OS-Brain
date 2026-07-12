import SwiftUI

/// Compact Home hero — mission anchor + 1–3 collaboration orbs by attention weight.
struct SwarmConstellationHero: View {
    @EnvironmentObject private var swarmStore: SwarmStore
    var hasMission: Bool = false
    var missionSnippet: String = ""
    var onSelectSwarm: (SwarmSummary) -> Void
    var onShowAll: () -> Void

    private let maxVisible = 3

    private var visible: [SwarmSummary] {
        Array(swarmStore.heroSwarms.prefix(maxVisible))
    }

    private var overflow: Int {
        max(0, swarmStore.heroSwarms.count - maxVisible)
    }

    var body: some View {
        if visible.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Your collaborations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.mutedText())
                    Spacer()
                    if overflow > 0 || swarmStore.heroSwarms.count > 1 {
                        Button("See all") {
                            Haptics.lightTap()
                            onShowAll()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(ColorTheme.accent())
                    }
                }

                VStack(spacing: Spacing.sm) {
                    MissionOrb(
                        size: 52,
                        hasMission: hasMission,
                        missionSnippet: missionSnippet,
                        showLabel: false
                    )
                    .frame(maxWidth: .infinity)

                    missionTether

                    HStack(alignment: .bottom, spacing: Spacing.md) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, swarm in
                            Button {
                                Haptics.lightTap()
                                onSelectSwarm(swarm)
                            } label: {
                                SwarmOrb(
                                    swarm: swarm,
                                    size: orbSize(rank: index, swarm: swarm),
                                    showLabel: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if overflow > 0 {
                            Button {
                                Haptics.lightTap()
                                onShowAll()
                            } label: {
                                Text("+\(overflow)")
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent())
                                    .frame(width: 52, height: 52)
                                    .background(ColorTheme.accent().opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(overflow) more collaborations")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.md)
            .centurionCard(elevated: true)
        }
    }

    private var missionTether: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        ColorTheme.accent().opacity(hasMission ? 0.35 : 0.12),
                        ColorTheme.accent().opacity(0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 18)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func orbSize(rank: Int, swarm: SwarmSummary) -> CGFloat {
        let base: CGFloat = rank == 0 ? 108 : (rank == 1 ? 88 : 76)
        if swarm.pulse == .waiting || swarm.pulse == .attention {
            return base + 8
        }
        return base
    }
}

/// Full-screen constellation for 4+ Swarms.
struct ConstellationView: View {
    @EnvironmentObject private var swarmStore: SwarmStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onSelectSwarm: (SwarmSummary) -> Void

    @State private var filterNeedsYou = true

    private var displayed: [SwarmSummary] {
        let sorted = swarmStore.heroSwarms
        if filterNeedsYou {
            let needs = sorted.filter { $0.pulse == .waiting || $0.pulse == .attention || $0.pulse == .blocked }
            return needs.isEmpty ? sorted : needs
        }
        return sorted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SheetHeader(title: "Your collaborations", subtitle: "Tap a collaboration to see details")
                    filterChips

                    ZStack {
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, swarm in
                            Button {
                                Haptics.lightTap()
                                onSelectSwarm(swarm)
                            } label: {
                                SwarmOrb(swarm: swarm, size: 96, showLabel: true)
                            }
                            .buttonStyle(.plain)
                            .offset(constellationOffset(for: index, total: displayed.count))
                        }
                    }
                    .frame(minHeight: 360)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .background(
                ZStack {
                    ColorTheme.background()
                    ColorTheme.atmosphericVeil().ignoresSafeArea()
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .buttonStyle(CenturionGhostButtonStyle())
                }
            }
        }
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
                .foregroundColor(active ? .white : ColorTheme.primaryText())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if active {
                            LinearGradient(
                                colors: [ColorTheme.accent(), ColorTheme.dimAccent()],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            ColorTheme.surface()
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : ColorTheme.border(), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func constellationOffset(for index: Int, total: Int) -> CGSize {
        if reduceMotion || total <= 1 { return .zero }
        let presets: [CGSize] = [
            CGSize(width: 0, height: -40),
            CGSize(width: -90, height: 50),
            CGSize(width: 90, height: 50),
            CGSize(width: -50, height: -80),
            CGSize(width: 60, height: 90),
        ]
        return presets[index % presets.count]
    }
}
