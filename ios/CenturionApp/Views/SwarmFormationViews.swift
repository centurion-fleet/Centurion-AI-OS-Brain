import SwiftUI

/// Soft formation proposal after a conversation — one tap to confirm.
struct SwarmFormationCard: View {
    let proposal: SwarmFormationProposal
    var onStart: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        AtmosphericSurface(elevated: true, showRim: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.title3)
                        .foregroundColor(ColorTheme.accent())
                    Text("Your Centurions could take this further together")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                }

                Text(proposal.objective)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText())
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                VStack(spacing: Spacing.sm) {
                    Button("Start collaboration") {
                        Haptics.lightTap()
                        onStart()
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())

                    Button("Not now") {
                        Haptics.lightTap()
                        onDismiss()
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                }
            }
        }
    }
}

/// One-screen confirmation — editable name, orb preview, no task editor.
struct SwarmFormationSheet: View {
    @EnvironmentObject private var swarmStore: SwarmStore
    @Environment(\.dismiss) private var dismiss

    let proposal: SwarmFormationProposal

    @State private var name: String = ""
    @State private var formingPulse = true

    private var previewSwarm: SwarmSummary {
        SwarmSummary(
            id: UUID().uuidString,
            displayName: name.isEmpty ? proposal.suggestedName : name,
            objective: proposal.objective,
            status: .running,
            pulse: formingPulse ? .forming : .idle,
            formationSource: proposal.source,
            participants: proposal.participantNames.enumerated().map { index, label in
                SwarmParticipant(
                    name: label,
                    kind: .centurion,
                    role: .operatorRole,
                    isActive: index == 0
                )
            } + [SwarmParticipant(name: "You", kind: .human, role: .owner)],
            pendingSignalCount: 0,
            updatedAt: Date()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(CenturionGhostButtonStyle())
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SwarmOrb(swarm: previewSwarm, size: 150, showLabel: false)
                        .padding(.top, Spacing.md)

                    SheetHeader(
                        title: "Start collaboration",
                        subtitle: proposal.objective
                    )

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        CenturionSectionHeader(title: "Name", icon: "pencil")
                        TextField("Six words or fewer", text: $name)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundColor(ColorTheme.primaryText())
                            .padding(Spacing.md)
                            .centurionCard()
                    }
                    .padding(.horizontal, Spacing.md)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        CenturionSectionHeader(title: "Who's involved", icon: "person.2.fill")
                        Text("You, plus \(proposal.participantNames.joined(separator: ", "))")
                            .font(.body)
                            .foregroundColor(ColorTheme.mutedText())
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .centurionCard()
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.bottom, Spacing.xl)
            }

            Button("Start collaboration") {
                Haptics.success()
                swarmStore.confirmFormation(name: name.isEmpty ? proposal.suggestedName : name)
                dismiss()
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .onAppear {
            name = proposal.suggestedName
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                formingPulse.toggle()
            }
        }
    }
}
