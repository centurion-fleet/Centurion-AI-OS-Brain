import SwiftUI

/// Where users discover and live their mission — everything about the human.
/// Reachable from Pulse (mission banner) and Settings.
struct MissionView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @State private var isDiscovering = false
    @State private var showContextEditor = false

    private var profile: HumanProfile { missionStore.mission.profile }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                FullBrandHeader()
                missionHero
                missionDiscoverySection
                missionTargetsSection
                aboutYouSection
            }
            .padding()
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .navigationTitle("Mission")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isDiscovering) {
            MissionDiscoveryView(initialAnswers: missionStore.discoveryAnswers) { answers in
                missionStore.completeDiscovery(from: answers)
                isDiscovering = false
            }
        }
        .sheet(isPresented: $showContextEditor) {
            HumanContextInterviewView(existingProfile: missionStore.mission.profile) { updated in
                missionStore.updateProfile(updated)
            }
        }
    }

    // MARK: - Hero

    private var missionHero: some View {
        AtmosphericSurface(elevated: true, showRim: missionStore.hasMissionStatement) {
            VStack(spacing: Spacing.md) {
                if missionStore.hasMissionStatement {
                    Text("WHAT YOU'RE BUILDING TOWARD")
                        .font(Typography.sectionLabel)
                        .foregroundColor(ColorTheme.accent())
                        .tracking(2)

                    Text(missionStore.mission.statement)
                        .font(Typography.editorialTitle)
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)

                    if !profile.whyThisMission.isEmpty {
                        Text(profile.whyThisMission)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }

                    Text("This is about you — your life, your purpose, your commitments.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xs)
                } else {
                    Text("YOUR LIFE\nMISSION")
                        .font(Typography.editorialTitle)
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)

                    Text("Your Centurion exists to help you discover what matters,\nthen walk beside you as you live it.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Mission Discovery

    private var missionDiscoverySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Discover Your Mission", icon: "sparkles")

            Text("Reflect on your life — what matters and what you're building. This isn't about how your Centurion behaves; it's about you.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(5)

            Button {
                isDiscovering = true
            } label: {
                HStack {
                    Image(systemName: missionStore.hasMissionStatement
                          ? "arrow.triangle.2.circlepath"
                          : "person.crop.circle")
                    Text(missionStore.hasMissionStatement
                         ? "Refine Mission Discovery"
                         : "Begin Mission Discovery")
                }
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Mission Targets

    private var missionTargetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Active Commitments", icon: "target")

            Text("Living commitments your Centurion helps you fulfill. Select the ones to work on — they appear in Pulse.")
                .font(.subheadline)
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
                Text("\(missionStore.activeTargets.count) commitment\(missionStore.activeTargets.count == 1 ? "" : "s") active in Pulse")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent().opacity(0.8))
                    .italic()
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - About You

    private var aboutYouSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "About You", icon: "person.fill")

            Text("Context that helps your Centurion understand your world — story, values, people, and what you need help with.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(5)

            if profile.hasContext {
                aboutYouSummary
            }

            Button {
                showContextEditor = true
            } label: {
                HStack {
                    Image(systemName: profile.hasContext ? "pencil" : "plus.circle")
                    Text(profile.hasContext ? "Edit About You" : "Add context about you")
                }
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
        }
    }

    private var aboutYouSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !profile.yourStory.isEmpty {
                profileRow(title: "Story", value: profile.yourStory)
            }
            if !profile.yourValues.isEmpty {
                profileTags(title: "Values", tags: profile.yourValues)
            }
            if !profile.keyRelationships.isEmpty {
                profileTags(title: "People", tags: profile.keyRelationships)
            }
            if !profile.delegatePreferences.isEmpty {
                profileTags(title: "Help with", tags: profile.delegatePreferences)
            }
        }
        .centurionCard()
    }

    private func profileRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.accent())
            Text(value)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .lineLimit(3)
        }
    }

    private func profileTags(title: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.accent())
            FlowLayout(tags: tags)
        }
    }

    private var emptyTargetsPrompt: some View {
        EmptyState(
            icon: "target",
            title: "No commitments yet",
            message: "Complete Mission Discovery to define your commitments."
        )
        .centurionCard()
    }
}

// MARK: - Simple tag flow layout

private struct FlowLayout: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .foregroundColor(ColorTheme.primaryText())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ColorTheme.accent().opacity(0.08))
                    .clipShape(Capsule())
            }
        }
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
            .background(isSelected ? ColorTheme.accent().opacity(0.06) : Color.clear)
            .centurionCard(elevated: isSelected)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? ColorTheme.accent().opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
