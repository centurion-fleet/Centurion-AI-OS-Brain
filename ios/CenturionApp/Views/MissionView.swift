import SwiftUI

/// Where users discover and live their mission with their Centurion.
/// Reachable from Pulse (mission banner) and Settings.
struct MissionView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @State private var isDiscovering = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                missionHero
                missionDiscoverySection
                missionTargetsSection
            }
            .padding()
        }
        .background(ColorTheme.background())
        .navigationTitle("Mission")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isDiscovering) {
            MissionDiscoveryView(initialAnswers: missionStore.discoveryAnswers) { answers in
                missionStore.completeDiscovery(from: answers)
                isDiscovering = false
            }
        }
    }

    // MARK: - Hero

    private var missionHero: some View {
        VStack(spacing: Spacing.md) {
            if missionStore.hasMissionStatement {
                Text("YOUR MISSION")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(4)

                Text(missionStore.mission.statement)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                if !missionStore.soul.whyThisMission.isEmpty {
                    Text(missionStore.soul.whyThisMission)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            } else {
                Text("LIVE YOUR\nPERSONAL MISSION")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                Text("Your Centurion exists to help you discover it,\nthen walk beside you as you live it.")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(ColorTheme.surface())
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(ColorTheme.accent().opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Mission Discovery

    private var missionDiscoverySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Discover Your Mission", icon: "sparkles")

            Text("Your mission isn't assigned. It emerges through reflection, conversation, and living. Your Centurion is here to help you find it.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(5)

            Button {
                isDiscovering = true
            } label: {
                HStack {
                    Image(systemName: missionStore.hasMissionStatement
                          ? "arrow.triangle.2.circlepath"
                          : "heart.text.square.fill")
                    Text(missionStore.hasMissionStatement
                         ? "Refine Mission Discovery"
                         : "Begin Mission Discovery")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Mission Targets

    private var missionTargetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Mission Targets", icon: "target")

            Text("These are the living commitments your Centurion is helping you fulfill. Select the ones you want to actively work on — they will appear in Pulse.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(5)

            if missionStore.mission.targets.isEmpty {
                emptyTargetsPrompt
            } else {
                ForEach(missionStore.mission.targets) { target in
                    LifeMissionTargetRow(
                        target: target,
                        isSelected: missionStore.isTargetActive(target.id),
                        onToggle: { missionStore.toggleActiveTarget(target.id) }
                    )
                }
            }

            if !missionStore.activeTargets.isEmpty {
                Text("\(missionStore.activeTargets.count) target\(missionStore.activeTargets.count == 1 ? "" : "s") active in Pulse")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundColor(ColorTheme.accent().opacity(0.8))
                    .italic()
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private var emptyTargetsPrompt: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "target")
                .font(.system(size: 28))
                .foregroundColor(ColorTheme.mutedText().opacity(0.5))
            Text("Complete Mission Discovery to define your targets.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Mission Target Row

struct LifeMissionTargetRow: View {
    let target: LifeMissionTarget
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? ColorTheme.accent() : ColorTheme.mutedText())

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ColorTheme.primaryText())

                    Text(target.description)
                        .font(.system(size: 13))
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? ColorTheme.accent().opacity(0.06) : ColorTheme.surface())
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? ColorTheme.accent().opacity(0.3) : ColorTheme.border(), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
