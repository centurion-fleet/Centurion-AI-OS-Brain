import SwiftUI

/// Dedicated Mission View — the heart of the app.
/// Frank Lloyd Wright inspired: organic, warm, deeply personal.
/// This is where users discover and live their mission with their Centurion.
///
/// Philosophy: One AI. One person. One mission for life.
/// The Centurion helps the human discover their mission, then turns it into
/// living Mission Targets that appear in Pulse.
struct MissionView: View {
    @State private var mission: LifeMission = LifeMission.preview()
    @State private var selectedTargets: Set<UUID> = []
    @State private var isDiscovering = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Brand Header
                    BrandHeader()
                        .padding(.bottom, Spacing.sm)
                    
                    // Emotional Hero
                    missionHero
                    
                    // Mission Discovery
                    missionDiscoverySection
                    
                    // Mission Targets
                    missionTargetsSection
                }
                .padding()
            }
            .navigationTitle("Mission")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Hero
    private var missionHero: some View {
        VStack(spacing: Spacing.md) {
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
                    Image(systemName: "heart.text.square.fill")
                    Text("Begin Mission Discovery")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .padding(.top, Spacing.sm)
        }
        .sheet(isPresented: $isDiscovering) {
            // Future: SoulDocument-style discovery flow
            Text("Mission Discovery Flow\n(Coming in next iteration)")
                .font(.title3)
                .padding()
        }
    }
    
    // MARK: - Mission Targets
    private var missionTargetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Mission Targets", icon: "target")
            
            Text("These are the living commitments your Centurion is helping you fulfill. Select the ones you want to actively work on — they will appear in your Pulse.")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(5)
            
            ForEach(mission.targets) { target in
                MissionTargetRow(
                    target: target,
                    isSelected: selectedTargets.contains(target.id),
                    onToggle: { toggleTarget(target) }
                )
            }
            
            Text("Your Centurion will show progress, wins, and decisions related to these targets in Pulse.")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.accent().opacity(0.7))
                .italic()
                .padding(.top, Spacing.sm)
        }
    }
    
    private func toggleTarget(_ target: MissionTarget) {
        if selectedTargets.contains(target.id) {
            selectedTargets.remove(target.id)
        } else {
            selectedTargets.insert(target.id)
        }
        // In real implementation: sync selected targets to Pulse
    }
}

// MARK: - Mission Target Row
struct MissionTargetRow: View {
    let target: MissionTarget
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

// Supporting models (temporary — move to proper models later)
struct MissionTarget: Identifiable {
    let id = UUID()
    let title: String
    let description: String
}

extension LifeMission {
    var targets: [MissionTarget] {
        [
            MissionTarget(title: "Build Centurion AI", description: "Create the world's most personal AI companion"),
            MissionTarget(title: "Live with Purpose", description: "Every day aligned with my deeper mission"),
            MissionTarget(title: "Help Others Find Their Mission", description: "Enable more people to live meaningful lives")
        ]
    }
}