import SwiftUI

/// Where users discover and live their mission — everything about the human.
/// Reachable from Pulse (mission banner) and Settings.
struct MissionView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isDiscovering = false
    @State private var showContextEditor = false
    @State private var chatTarget: ChatSheetTarget?
    @State private var chatError: String?
    @State private var syncMessage: String?
    @State private var isSyncing = false

    private var profile: HumanProfile { missionStore.mission.profile }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                FullBrandHeader()
                missionHero
                missionDiscoverySection
                missionTargetsSection
                aboutYouSection

                Text(missionStore.missionSubtitle)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .frame(maxWidth: .infinity, alignment: .leading)

                if missionStore.hasMissionStatement {
                    Button {
                        Task { await syncMission() }
                    } label: {
                        Text(isSyncing ? "Syncing…" : "Sync Life Mission to Sovereign")
                    }
                    .buttonStyle(CenturionSecondaryButtonStyle())
                    .disabled(isSyncing || !connectionManager.isCryptoChatReady)
                }

                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundColor(ColorTheme.dimAccent())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .task {
            await missionStore.refreshMission(from: connectionManager)
        }
        .fullScreenCover(isPresented: $isDiscovering) {
            MissionDiscoveryView(initialAnswers: missionStore.discoveryAnswers) { answers in
                missionStore.completeDiscovery(from: answers)
                isDiscovering = false
                Task { await syncMission() }
            }
        }
        .sheet(isPresented: $showContextEditor) {
            HumanContextInterviewView(existingProfile: missionStore.mission.profile) { updated in
                missionStore.updateProfile(updated)
                Task { await syncMission() }
            }
        }
        .sheet(item: $chatTarget) { target in
            commitmentChatSheet(for: target.context)
        }
        .alert("Couldn't open chat", isPresented: Binding(
            get: { chatError != nil },
            set: { if !$0 { chatError = nil } }
        )) {
            Button("OK", role: .cancel) { chatError = nil }
        } message: {
            Text(chatError ?? "")
        }
    }

    private func commitmentChatSheet(for context: ConversationContext) -> some View {
        let conversation = messageService.findOrCreateConversation(for: context)
        return NavigationStack {
            ChatView(conversation: conversation, usesPageChrome: false)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { chatTarget = nil }
                    }
                }
        }
        .presentationDetents([.height(380), .large])
        .presentationDragIndicator(.visible)
    }

    private func openCommitmentChat(for target: LifeMissionTarget) {
        guard connectionManager.isCryptoChatReady else {
            chatError = "Pair with your Sovereign in You first, then chat about this commitment."
            return
        }
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(
            context: .commitment(id: target.id, title: target.title)
        )
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

                    Text("Your Sovereign exists to help you discover what matters,\nthen walk beside you as you live it.")
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

            Text("Reflect on your life — what matters and what you're building. This isn't about how your Sovereign behaves; it's about you.")
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

            Text("Living commitments your Sovereign helps you fulfill. Turn on the ones to prioritize on Focus, or tap the chat bubble to discuss and refine them.")
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
                        onToggle: { missionStore.toggleActiveTarget(target.id) },
                        onChat: { openCommitmentChat(for: target) }
                    )
                }
            }

            if !missionStore.activeTargets.isEmpty {
                Text("\(missionStore.activeTargets.count) commitment\(missionStore.activeTargets.count == 1 ? "" : "s") active on Focus")
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

            Text("Context that helps your Sovereign understand your world — story, values, people, and what you need help with.")
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

    private func syncMission() async {
        isSyncing = true
        defer { isSyncing = false }
        syncMessage = await missionStore.syncMissionToSovereign(
            connectionManager: connectionManager
        )
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
    var onChat: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.md) {
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

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onChat {
                Button(action: onChat) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 18))
                        .foregroundColor(ColorTheme.accent())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chat about \(target.title)")
            }
        }
        .padding()
        .background(isSelected ? ColorTheme.accent().opacity(0.06) : Color.clear)
        .centurionCard(elevated: isSelected)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isSelected ? ColorTheme.accent().opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
