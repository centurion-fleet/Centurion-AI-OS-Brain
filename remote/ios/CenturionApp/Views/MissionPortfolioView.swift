import SwiftUI

/// Sovereign Remote — the AI's dashboard. The human's window into what their
/// Centurion is doing, has done, and needs.
///
/// This is NOT a human project management tool. There are no tasks to check off,
/// no milestones to track, no human-speed progress bars. This is the Sovereign's
/// cockpit — showing live loops, completed wins, and decisions that need the human.
///
/// Notification system: each category has a badge count for items newer than
/// the user's last visit to that category. Badges clear when you tap the pill.
enum PulseCategory: String, CaseIterable {
    case live = "LIVE"
    case plans = "PLANS"
    case wins = "WINS"
    case outputs = "OUTPUTS"
    case decisions = "DECISIONS"
    case pulse = "PULSE"

    var displayTitle: String {
        switch self {
        case .live: return "Working on now"
        case .plans: return "Missions"
        case .wins: return "Finished"
        case .outputs: return "Documents"
        case .decisions: return "Decisions needed"
        case .pulse: return "Updates"
        }
    }

    var icon: String {
        switch self {
        case .live:      return "bolt.circle.fill"
        case .plans:     return "list.clipboard.fill"
        case .wins:      return "trophy.fill"
        case .outputs:   return "doc.richtext.fill"
        case .decisions: return "lightbulb.fill"
        case .pulse:     return "waveform.path.ecg"
        }
    }
}

struct MissionPortfolioView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var dataMode: AppDataMode
    @State private var liveActivity: LiveActivity?
    @State private var completedLoops: [CompletedLoop] = []
    @State private var decisions: [DecisionItem] = []
    @State private var outputs: [CenturionOutput] = []
    @State private var thoughts: [CenturionThought] = []
    @State private var isDataLoaded = false
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var isAppeared = false
    @State private var liveExpanded = false
    @State private var showActivityDetails = false
    @State private var selectedCategory: PulseCategory = .live
    @State private var syncSpinning = false

    /// Unified chat sheet state
    @State private var chatTarget: ChatSheetTarget?
    /// Output document viewer state
    @State private var selectedOutput: CenturionOutput?
    /// Plan review sheet
    @State private var selectedPlan: PlanArtifact?

    // MARK: - Notification tracking
    // Stores the last time each category was viewed. Items newer than this date
    // show a "new" indicator and contribute to the pill badge count.
    @AppStorage("pulse_note_live")     private var lastSeenLive: TimeInterval = 0
    @AppStorage("pulse_note_plans")    private var lastSeenPlans: TimeInterval = 0
    @AppStorage("pulse_note_wins")     private var lastSeenWins: TimeInterval = 0
    @AppStorage("pulse_note_outputs")  private var lastSeenOutputs: TimeInterval = 0
    @AppStorage("pulse_note_decisions") private var lastSeenDecisions: TimeInterval = 0
    @AppStorage("pulse_note_pulse")    private var lastSeenThoughts: TimeInterval = 0

    /// Count of unseen items per category
    private var badgeCounts: [PulseCategory: Int] {
        PulseBadgeCounts.counts(
            feed: PulseFeedMapper.Feed(
                liveActivity: liveActivity,
                wins: completedLoops,
                outputs: outputs,
                decisions: decisions,
                thoughts: thoughts
            ),
            swarmStore: swarmStore,
            planStore: planStore,
            lastSeen: .init(
                plans: lastSeenPlans,
                wins: lastSeenWins,
                outputs: lastSeenOutputs,
                decisions: lastSeenDecisions,
                thoughts: lastSeenThoughts
            )
        )
    }

    private var showsWorkingSync: Bool {
        connectionManager.isHydratingAfterLink || liveActivity != nil
    }

    private func openWorkingOnNow() {
        Haptics.lightTap()
        withAnimation(Motion.standard) {
            selectedCategory = .live
            if liveActivity != nil {
                liveExpanded = true
            }
        }
        markSeen(.live)
    }

    /// Mark a category as seen — clear its badge
    private func markSeen(_ category: PulseCategory) {
        let now = Date.timeIntervalSinceReferenceDate
        switch category {
        case .live:     lastSeenLive = now
        case .plans:    lastSeenPlans = now
        case .wins:     lastSeenWins = now
        case .outputs:  lastSeenOutputs = now
        case .decisions: lastSeenDecisions = now
        case .pulse:    lastSeenThoughts = now
        }
    }

    /// Whether an item with the given date is new (unseen) in its category
    private func isNew(_ date: Date, category: PulseCategory) -> Bool {
        let threshold: Date
        switch category {
        case .live:     threshold = Date(timeIntervalSinceReferenceDate: lastSeenLive)
        case .plans:    threshold = Date(timeIntervalSinceReferenceDate: lastSeenPlans)
        case .wins:     threshold = Date(timeIntervalSinceReferenceDate: lastSeenWins)
        case .outputs:  threshold = Date(timeIntervalSinceReferenceDate: lastSeenOutputs)
        case .decisions: threshold = Date(timeIntervalSinceReferenceDate: lastSeenDecisions)
        case .pulse:    threshold = Date(timeIntervalSinceReferenceDate: lastSeenThoughts)
        }
        return date > threshold
    }

    var body: some View {
        TabPageChrome(screenTitle: nil, navigationBackTitle: "Focus", header: {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("Focus")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.mutedText())
                Spacer(minLength: 0)
                if showsWorkingSync {
                    Button(action: openWorkingOnNow) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body.weight(.semibold))
                            .foregroundColor(ColorTheme.accent())
                            .rotationEffect(.degrees(syncSpinning ? 360 : 0))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mission working. Opens Working on now.")
                    .accessibilityHint("Shows what your Sovereign is doing right now")
                    .onAppear {
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                            syncSpinning = true
                        }
                    }
                    .onDisappear {
                        syncSpinning = false
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)

            CenturionPillNav(
                items: PulseCategory.allCases,
                selection: $selectedCategory,
                title: { $0.displayTitle },
                icon: { $0.icon },
                badge: { badgeCounts[$0] ?? 0 }
            )
            .padding(.bottom, Spacing.xs)
            .onChange(of: selectedCategory) { _, category in
                markSeen(category)
            }
        }, content: {
            Group {
                if isDataLoaded {
                    pulseScrollContent
                } else {
                    LoadingState(message: "Loading your dashboard…")
                }
            }
        })
        .task(id: connectionManager.isHydratingAfterLink) {
            isDataLoaded = true
            guard connectionManager.isCryptoChatReady,
                  !connectionManager.isHydratingAfterLink else { return }
            applyPulseFromSwarmStore()
            if swarmStore.lastSyncedAt == nil {
                await reloadPulseFeed(forceRefresh: true)
            }
        }
        .refreshable {
            await syncFocusFromBrain(forceRefresh: true)
        }
        .onChange(of: connectionManager.connectionState) { _, _ in
            Task { await reloadPulseFeed(forceRefresh: false) }
        }
        .onChange(of: swarmStore.activities.count) { _, _ in
            if connectionManager.isCryptoChatReady {
                applyPulseFromSwarmStore()
            }
        }
        .onChange(of: swarmStore.outcomes.count) { _, _ in
            if connectionManager.isCryptoChatReady {
                applyPulseFromSwarmStore()
            }
        }
        .onChange(of: swarmStore.signals.count) { _, _ in
            if connectionManager.isCryptoChatReady {
                applyPulseFromSwarmStore()
            }
        }
        .onChange(of: planStore.plans.count) { _, _ in
            applyPulseFromSwarmStore()
        }
        .onAppear {
            withAnimation(Motion.appear.delay(0.1)) {
                isAppeared = true
            }
        }
        .sheet(item: $chatTarget) { target in
            chatSheet(for: target.context)
        }
        .sheet(item: $selectedPlan) { plan in
            NavigationStack {
                PlanReviewView(
                    plan: plan,
                    onProceed: { handlePlanProceed(plan) },
                    onAdjust: { handlePlanAdjust(plan) },
                    onHold: { handlePlanHold(plan) },
                    onDiscuss: { openPlanDiscuss(plan) },
                    onShare: { reviewerId in
                        Task {
                            _ = await planStore.share(
                                plan.id,
                                reviewerCustomerId: reviewerId,
                                connectionManager: connectionManager
                            )
                        }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { selectedPlan = nil }
                    }
                }
            }
        }
    }

    private var pulseScrollContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if dataMode.showsDemoContent {
                    DemoDataBanner()
                }

                brainSyncBanner

                missionBanner

                supportingMissionsStrip

                if !missionStore.activeTargets.isEmpty {
                    activeTargetsStrip
                }

                switch selectedCategory {
                case .live:
                    if liveActivity != nil {
                        liveActivitySection
                    } else {
                        EmptyState(
                            icon: "bolt.circle",
                            title: connectionManager.isCryptoChatReady
                                ? "Nothing running right now"
                                : "Working on now",
                            message: connectionManager.isCryptoChatReady
                                ? "When your Sovereign is mid-loop, it shows up here."
                                : "Link your Sovereign in You to see live work."
                        )
                    }
                case .plans:
                    plansSection
                case .wins:
                    if completedLoops.isEmpty {
                        EmptyState(
                            icon: "trophy",
                            title: "No finished work yet",
                            message: connectionManager.isCryptoChatReady
                                ? "Completed outcomes from your Sovereign will appear here."
                                : "Link your Sovereign to see finished wins."
                        )
                    } else {
                        completedLoopsSection
                    }
                case .outputs:
                    if !outputs.isEmpty {
                        outputsSection
                    } else {
                        EmptyState(
                            icon: "doc.richtext",
                            title: "No outputs yet",
                            message: connectionManager.isCryptoChatReady
                                ? "Documents and results your Sovereign creates will appear here."
                                : "Link your Sovereign to see documents it creates."
                        )
                    }
                case .decisions:
                    if !decisions.isEmpty {
                        decisionsSection
                    } else {
                        EmptyState(
                            icon: "checkmark.circle",
                            title: "All clear",
                            message: connectionManager.isCryptoChatReady
                                ? "Nothing needs a decision right now."
                                : "Link your Sovereign to see decisions that need you."
                        )
                    }
                case .pulse:
                    if thoughts.isEmpty {
                        EmptyState(
                            icon: "waveform.path.ecg",
                            title: "No updates yet",
                            message: connectionManager.isCryptoChatReady
                                ? "Activity from your Sovereign streams in here."
                                : "Link your Sovereign to see its update stream."
                        )
                    } else {
                        thoughtsSection
                    }
                }
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Chat Sheet

    private func chatSheet(for context: ConversationContext) -> some View {
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

    private func openChat(context: ConversationContext) {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: context)
    }

    /// Opens Crypto Chat about a Pulse item and seeds a one-time context note.
    private func openDiscuss(title: String, detail: String, topicKind: String = "decision") {
        Haptics.lightTap()
        let conversation = messageService.seedDiscussContext(
            title: title,
            detail: detail,
            topicKind: topicKind,
            topicRef: ["title": title, "source": "pulse"]
        )
        chatTarget = ChatSheetTarget(context: conversation.context)
    }

    /// Opens (or resumes) the stable plan-scoped Discuss thread.
    private func openPlanDiscuss(_ plan: PlanArtifact, kickoffNote: String? = nil) {
        Haptics.lightTap()
        planStore.upsert(plan)
        let conversation = messageService.seedPlanDiscuss(plan: plan, kickoffNote: kickoffNote)
        chatTarget = ChatSheetTarget(context: conversation.context)
    }

    private func syncFocusFromBrain(forceRefresh: Bool = false) async {
        if connectionManager.isCryptoChatReady, connectionManager.isHydratingAfterLink {
            isDataLoaded = true
            return
        }
        if connectionManager.isCryptoChatReady, connectionManager.isRemoteTurnInFlight {
            isDataLoaded = true
            return
        }
        await reloadPulseFeed(forceRefresh: forceRefresh)
        await missionStore.refreshLifeStack(from: connectionManager)
        await planStore.refreshFromHost(connectionManager: connectionManager)
    }

    @ViewBuilder
    private var brainSyncBanner: some View {
        if !connectionManager.isCryptoChatReady {
            EmptyView()
        } else if connectionManager.isHydratingAfterLink {
            Text("Loading mission data from your Centurion. Please wait — Chat opens when that’s done.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if connectionManager.isCryptoChatReady,
                  swarmStore.lastSyncedAt == nil,
                  swarmStore.lastSyncError == nil {
            Text("Missions are here. Finished, Documents, Decisions needed, and Updates load next.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if connectionManager.isRemoteTurnInFlight {
            Text("Linked — Chat is using the line. Stop or wait, then pull to refresh Focus.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = missionStore.lifeSyncError {
            Button {
                Task { await syncFocusFromBrain(forceRefresh: true) }
            } label: {
                Text("Linked, but your Centurion didn’t send missions in time. The phone is still linked — tap to retry. Chat may be using the line.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.warning())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading Focus from your Centurion")
            .accessibilityHint(error)
        } else if missionStore.lifeSyncedWithSovereign,
                  missionStore.stack.primary == nil,
                  missionStore.stack.supporting.isEmpty,
                  missionStore.stack.dreams.isEmpty,
                  planStore.plans.isEmpty {
            Text("Linked to your Centurion. Focus is empty because the Brain has no missions yet — not because the link failed.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if connectionManager.isCryptoChatReady, !missionStore.lifeSyncedWithSovereign {
            Text("Linked. Pull down to load missions from your Centurion.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reloadPulseFeed(forceRefresh: Bool = false) async {
        if connectionManager.isCryptoChatReady {
            if forceRefresh {
                await swarmStore.refresh(from: connectionManager)
            }
            applyPulseFromSwarmStore()
        } else if dataMode.showsDemoContent {
            #if DEBUG
            planStore.seedPreviewIfNeeded(showsDemoContent: true)
            liveActivity = LiveActivity.preview()
            completedLoops = CompletedLoop.preview()
            decisions = DecisionItem.preview()
            outputs = CenturionOutput.preview()
            thoughts = CenturionThought.preview()
            #else
            liveActivity = nil
            completedLoops = []
            decisions = []
            outputs = []
            thoughts = []
            #endif
        } else {
            liveActivity = nil
            completedLoops = []
            decisions = []
            outputs = []
            thoughts = []
        }
        isDataLoaded = true
    }

    private func applyPulseFromSwarmStore() {
        let feed = PulseFeedMapper.map(from: swarmStore, planStore: planStore)
        liveActivity = feed.liveActivity
        completedLoops = feed.wins
        outputs = feed.outputs
        decisions = feed.decisions
        thoughts = feed.thoughts
    }

    private func handleDecisionOption(_ option: DecisionOption, for decision: DecisionItem) {
        Haptics.mediumTap()
        let label = option.label.lowercased()

        if decision.kind == .plan || decision.planId != nil {
            let plan = decision.planId.flatMap { planStore.plan(id: $0) }
                ?? PlanArtifact(
                    id: decision.planId ?? decision.id,
                    title: decision.title,
                    goal: decision.context,
                    steps: [],
                    risks: [],
                    openQuestions: [],
                    summary: decision.context,
                    relatedMission: decision.relatedMission,
                    signalId: decision.signalId,
                    status: .pendingReview,
                    createdAt: decision.createdAt
                )
            if label.contains("proceed") {
                handlePlanProceed(plan)
            } else if label.contains("adjust") || label.contains("discuss") || label.contains("modify") {
                handlePlanAdjust(plan)
            } else if label.contains("hold") {
                handlePlanHold(plan)
            } else {
                selectedPlan = plan
            }
            return
        }

        if label.contains("proceed") || label.contains("approve") {
            if let signalId = decision.signalId {
                swarmStore.resolveSignal(signalId, connectionManager: connectionManager)
                applyPulseFromSwarmStore()
            } else {
                openDiscuss(
                    title: "Proceed: \(decision.title)",
                    detail: "\(decision.title)\n\n\(decision.context)\n\nPlease proceed."
                )
            }
        } else if label.contains("adjust") || label.contains("discuss") || label.contains("modify") {
            openDiscuss(
                title: "Adjust: \(decision.title)",
                detail: "\(decision.title)\n\n\(decision.context)\n\nI’d like to adjust this before you continue."
            )
        } else if label.contains("hold") {
            // Keep in Decisions needed — leave swarm signal pending (no resolve).
            Haptics.lightTap()
        } else {
            openDiscuss(
                title: "Decision: \(decision.title) — \(option.label)",
                detail: "\(decision.title)\n\n\(decision.context)\n\nChosen option: \(option.label) — \(option.description)"
            )
        }
    }

    private func handlePlanProceed(_ plan: PlanArtifact) {
        Task {
            await planStore.decide(plan.id, choice: "approve", connectionManager: connectionManager)
            if let signalId = plan.signalId {
                swarmStore.resolveSignal(
                    signalId,
                    choiceNote: "Proceed",
                    connectionManager: connectionManager
                )
            }
            applyPulseFromSwarmStore()
            await MainActor.run { selectedPlan = nil }
            guard connectionManager.isCryptoChatReady else { return }
            do {
                _ = try await messageService.sendMessage(
                    "Please proceed with this plan now. Continue the work.",
                    in: .plan(id: plan.id, title: plan.title),
                    planStore: planStore
                )
            } catch {
                // Status is already recorded; Chat can retry from Discuss.
            }
        }
    }

    private func handlePlanAdjust(_ plan: PlanArtifact) {
        Task {
            await planStore.decide(plan.id, choice: "request_changes", connectionManager: connectionManager)
            openPlanDiscuss(
                plan,
                kickoffNote: "Please help me adjust this plan before proceeding."
            )
            applyPulseFromSwarmStore()
        }
    }

    private func handlePlanHold(_ plan: PlanArtifact) {
        Task {
            await planStore.decide(plan.id, choice: "hold", connectionManager: connectionManager)
            applyPulseFromSwarmStore()
        }
    }

    private func openPlan(from output: CenturionOutput) {
        if let existing = planStore.plan(id: output.id) {
            selectedPlan = existing
            return
        }
        selectedPlan = PlanArtifact(
            id: output.id,
            title: output.title,
            goal: output.summary,
            steps: [],
            risks: [],
            openQuestions: [],
            summary: output.summary,
            relatedMission: output.relatedMission,
            signalId: nil,
            status: .pendingReview,
            createdAt: output.createdAt
        )
    }

    // MARK: - Mission Banner

    private var missionBanner: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if connectionManager.isCryptoChatReady, missionStore.lifeSyncError != nil {
                Button {
                    Task { await syncFocusFromBrain(forceRefresh: true) }
                } label: {
                    missionStatement
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading missions from your Centurion")
            } else if missionStore.hasCompletedMissionSetup {
                NavigationLink {
                    MissionStackView()
                } label: {
                    missionStatement
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    MissionView()
                } label: {
                    missionStatement
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var supportingMissionsStrip: some View {
        let supporting = missionStore.stack.supporting
        return Group {
            if !supporting.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Supporting missions")
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text("\(supporting.count)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.onAccent())
                            .frame(minWidth: 22, minHeight: 22)
                            .background(ColorTheme.accent())
                            .clipShape(Circle())
                    }
                    ForEach(supporting.prefix(4)) { mission in
                        NavigationLink {
                            MissionStackView()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(mission.title.isEmpty ? mission.statement : mission.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(ColorTheme.primaryText())
                                    .multilineTextAlignment(.leading)
                                if !mission.statement.isEmpty, !mission.title.isEmpty {
                                    Text(mission.statement)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.mutedText())
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(ColorTheme.surface())
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(ColorTheme.border(), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        MissionStackView()
                    } label: {
                        Text(supporting.count > 4
                             ? "See all \(supporting.count) supporting missions"
                             : "See all missions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.onAccent())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(ColorTheme.accent())
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeTargetsStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("ACTIVE COMMITMENTS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(ColorTheme.mutedText())
                .tracking(2)

            Text("Priorities you turned on in Mission. Working on now below is what your Sovereign is executing.")
                .font(.caption2)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(missionStore.activeTargets) { target in
                        Button {
                            openChat(context: .commitment(id: target.id, title: target.title))
                        } label: {
                            HStack(spacing: 6) {
                                Text(target.title)
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ColorTheme.primaryText())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(ColorTheme.accent().opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(ColorTheme.accent().opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Chat about \(target.title)")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Mission Statement

    private var missionHeadline: String {
        if !missionStore.mission.statement.isEmpty {
            return missionStore.mission.statement
        }
        if let first = missionStore.mission.targets.first {
            return first.title
        }
        if connectionManager.isHydratingAfterLink {
            return "Loading missions from your Centurion…"
        }
        if connectionManager.isCryptoChatReady, missionStore.lifeSyncError != nil {
            return "Couldn't load missions from your Centurion"
        }
        if connectionManager.isCryptoChatReady, !missionStore.lifeSyncedWithSovereign {
            return "Loading missions from your Centurion…"
        }
        return "Discover what matters in your life"
    }

    private var missionSubtitle: String {
        if missionStore.hasCompletedMissionSetup {
            return ""
        }
        if connectionManager.isHydratingAfterLink {
            return "Please wait — Chat opens when mission data is on this phone."
        }
        if connectionManager.isCryptoChatReady, missionStore.lifeSyncError != nil {
            return "The phone is linked. Your Centurion didn’t answer in time — Chat may be using the line. Tap this card to retry."
        }
        if connectionManager.isCryptoChatReady, !missionStore.lifeSyncedWithSovereign {
            return "Waiting on your Centurion"
        }
        return "A short wizard in You — then Focus stays on the work."
    }

    private var missionStatement: some View {
        VStack(spacing: 6) {
            HStack {
                Text("WHAT YOU'RE BUILDING TOWARD")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(2)
                    .textCase(.uppercase)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ColorTheme.mutedText())
            }

            Text(missionHeadline)
                .font(Typography.editorialTitle)
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [ColorTheme.accent().opacity(0.6), ColorTheme.accent()],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 48, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.xs)

            if !missionSubtitle.isEmpty {
                Text(missionSubtitle)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .centurionCard(elevated: true)
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 10)
    }

    // MARK: - 1. LIVE — What the Sovereign Is Doing Right Now

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            Button(action: {
                withAnimation(Motion.heavy) { liveExpanded.toggle() }
            }) {
                HStack(spacing: Spacing.xs) {
                    PulseDot()
                        .frame(width: 10, height: 10)

                    Text("Working on now")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())

                    if let activity = liveActivity {
                        Text(activity.summary)
                            .font(.caption2)
                            .foregroundColor(ColorTheme.dimAccent())
                            .lineLimit(1)
                    }

                    Spacer()

                    if let activity = liveActivity {
                        Text("\(Int(activity.progress * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.accent())
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .rotationEffect(.degrees(liveExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if liveExpanded, let activity = liveActivity {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(activity.summary)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())

                    if activity.phase == .planning {
                        Text("Drafting a plan… You’ll be able to review it under Decisions needed or Documents.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.accent())
                            .lineSpacing(3)
                    }

                    Text(activity.detail)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(4)

                    ProgressView(value: activity.progress)
                        .tint(ColorTheme.accent())

                    if let est = activity.estimatedCompletion {
                        Label("About \(Int(est / 60)) minutes remaining", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(ColorTheme.dimAccent())
                    }

                    Button {
                        withAnimation(Motion.standard) { showActivityDetails.toggle() }
                    } label: {
                        Text(showActivityDetails ? "Hide details" : "Show how it's working")
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.accent())
                    }
                    .buttonStyle(.plain)

                    if showActivityDetails {
                        LoopVisualizationView(activity: activity)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(ColorTheme.surface())
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(ColorTheme.border(), lineWidth: 0.5)
                            )
                    }

                    HStack {
                        Spacer()
                        Button(action: {
                            openDiscuss(
                                title: activity.summary,
                                detail: "\(activity.summary)\n\n\(activity.detail)"
                            )
                        }) {
                            Label("Ask about this", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(ColorTheme.accent())
                    }
                }
                .padding(Spacing.md)
                .background(ColorTheme.surface())
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if !liveExpanded, let activity = liveActivity {
                Text(activity.summary)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineLimit(2)
                    .padding(.horizontal, Spacing.xs)
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 12)
    }

    // MARK: - Loop Phase Bar

    private func loopPhaseBar(currentPhase: LoopPhase) -> some View {
        HStack(spacing: 0) {
            ForEach(LoopPhase.allCases.filter { $0 != .idle }, id: \.self) { phase in
                let isActive = phase == currentPhase
                let isPast = phaseIndex(phase) < phaseIndex(currentPhase)

                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isPast ? ColorTheme.accent() : (isActive ? ColorTheme.accent().opacity(0.15) : Color.clear))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(isActive ? ColorTheme.accent() : ColorTheme.border(), lineWidth: 1.5)
                            )

                        if isPast {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(ColorTheme.onAccent())
                        } else {
                            Image(systemName: phase.icon)
                                .font(.system(size: 10))
                                .foregroundColor(isActive ? ColorTheme.accent() : ColorTheme.mutedText())
                        }
                    }

                    Text(phase.rawValue)
                        .font(.system(size: 6, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? ColorTheme.accent() : ColorTheme.mutedText())
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)

                if phase != .verifying {
                    Rectangle()
                        .fill(isPast ? ColorTheme.accent() : ColorTheme.border())
                        .frame(height: 1)
                        .frame(maxWidth: 12)
                }
            }
        }
    }

    private func phaseIndex(_ phase: LoopPhase) -> Int {
        LoopPhase.allCases.firstIndex(of: phase) ?? 0
    }

    // MARK: - Sub-Agent Row

    private func subAgentRow(_ agent: SubAgentActivity) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: agent.status.icon)
                .font(.caption)
                .foregroundColor(agent.status == .active ? ColorTheme.accent()
                               : agent.status == .completed ? ColorTheme.success()
                               : agent.status == .error ? ColorTheme.error()
                               : ColorTheme.mutedText())

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(agent.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText())
                    Text(agent.role)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ColorTheme.dimAccent())
                }
                Text(agent.summary)
                    .font(.system(size: 9))
                    .foregroundColor(ColorTheme.mutedText())
                    .lineLimit(1)
            }

            Spacer()

            Text("\(Int(agent.progress * 100))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(ColorTheme.accent())
        }
    }

    // MARK: - 2. WINS — Portfolio of Completed Loops

    private var completedLoopsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Completed")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("\(completedLoops.count) cycles")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ColorTheme.mutedText())
            }

            ForEach(completedLoops) { loop in
                completedLoopCard(loop)
                    .cardStyle()
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 16)
    }

    private func completedLoopCard(_ loop: CompletedLoop) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Result header — golden, celebratory
            HStack(spacing: Spacing.xs) {
                // New indicator dot
                if isNew(loop.completedAt, category: .wins) {
                    Circle()
                        .fill(ColorTheme.accent())
                        .frame(width: 6, height: 6)
                }

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ColorTheme.success())

                VStack(alignment: .leading, spacing: 1) {
                    Text(loop.summary)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText())

                    Text(loop.relatedMission)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ColorTheme.accent())
                }

                Spacer()

                Text(formatDuration(loop.duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ColorTheme.mutedText())
            }

            // Discuss button
            HStack {
                Spacer()
                Button(action: {
                    openDiscuss(
                        title: "Win: \(loop.summary)",
                        detail: "\(loop.summary)\n\n\(loop.detail)\n\nResult: \(loop.result)\nImpact: \(loop.impact)"
                    )
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 10))
                        Text("Discuss this win")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
            }

            // Detail
            Text(loop.detail)
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineLimit(3)

            // Result — what was produced
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                Text(loop.result)
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(ColorTheme.dimAccent())

            // Impact — why this matters
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                Text(loop.impact)
                    .font(.system(size: 9))
            }
            .foregroundColor(ColorTheme.success())

            // Sub-agent contributions
            if !loop.subAgentSummary.isEmpty {
                VStack(spacing: 2) {
                    ForEach(loop.subAgentSummary, id: \.self) { summary in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ColorTheme.dimAccent())
                                .frame(width: 3, height: 3)
                            Text(summary)
                                .font(.system(size: 8))
                                .foregroundColor(ColorTheme.mutedText())
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding()
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.success().opacity(0.15), lineWidth: 0.5)
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - 3. OUTPUTS — Documents the Sovereign Created

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Documents")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("\(outputs.count) ready for you")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ColorTheme.mutedText())
            }

            ForEach(outputs) { output in
                outputCard(output)
                    .cardStyle()
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 30)
    }

    private func outputCard(_ output: CenturionOutput) -> some View {
        VStack(spacing: 0) {
            // Tappable content area — plans open PlanReview; others DocumentViewer
            Button(action: {
                if output.type == .plan {
                    openPlan(from: output)
                } else {
                    selectedOutput = output
                }
            }) {
                HStack(spacing: Spacing.sm) {
                    // New indicator dot
                    if isNew(output.createdAt, category: .outputs) {
                        Circle()
                            .fill(ColorTheme.accent())
                            .frame(width: 6, height: 6)
                    }

                    // Type icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorTheme.accent().opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: output.type.icon)
                            .font(.system(size: 14))
                            .foregroundColor(ColorTheme.accent())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(output.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(ColorTheme.primaryText())
                            .lineLimit(1)

                        Text(output.type == .plan
                             ? "Your Sovereign proposes — tap to review"
                             : output.summary)
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Text(output.type.rawValue)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(ColorTheme.accent())
                            Text("\(output.wordCount) words")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(ColorTheme.mutedText())
                            if let mission = output.relatedMission {
                                Text(mission)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Discuss this output
            Divider()
                .padding(.horizontal)
            HStack {
                Spacer()
                Button(action: {
                    openDiscuss(
                        title: "Output: \(output.title)",
                        detail: "\(output.title)\n\n\(output.summary)"
                    )
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 10))
                        Text("Discuss this output")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, Spacing.xs)
        }
        .cardStyle()
        .sheet(item: $selectedOutput) { output in
            NavigationStack {
                DocumentViewer(output: output)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedOutput = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Missions — Reviewable proposals

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if planStore.pendingReview.isEmpty
                && planStore.inProgress.isEmpty
                && planStore.completed.isEmpty
                && planStore.templates.isEmpty {
                EmptyState(
                    icon: "list.clipboard",
                    title: "No missions yet",
                    message: connectionManager.isCryptoChatReady
                        ? "Use Propose first in Chat, or start from a template below when available."
                        : "Link your Sovereign to review missions here."
                )
            }

            if !planStore.pendingReview.isEmpty {
                planGroup(title: "Decisions needed", plans: planStore.pendingReview, showDecideActions: true)
            }
            if !planStore.inProgress.isEmpty {
                planGroup(title: "In progress", plans: planStore.inProgress)
            }
            if !planStore.completed.isEmpty {
                planGroup(title: "Done", plans: Array(planStore.completed.prefix(12)))
            }
            if !planStore.templates.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Templates")
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())
                    ForEach(planStore.templates) { template in
                        Button {
                            Haptics.mediumTap()
                            Task {
                                if let plan = await planStore.instantiateTemplate(
                                    template.id,
                                    connectionManager: connectionManager
                                ) {
                                    selectedPlan = plan
                                    applyPulseFromSwarmStore()
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.primaryText())
                                if !template.summary.isEmpty {
                                    Text(template.summary)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.mutedText())
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                        }
                        .buttonStyle(.plain)
                        .cardStyle()
                    }
                }
            }
        }
        .opacity(isAppeared ? 1 : 0)
    }

    private func planGroup(title: String, plans: [PlanArtifact], showDecideActions: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())
            ForEach(plans) { plan in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Button {
                            Haptics.mediumTap()
                            selectedPlan = plan
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(plan.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.primaryText())
                                        .lineLimit(2)
                                    Spacer()
                                    if let risk = plan.risk {
                                        Text(risk.displayLabel)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(ColorTheme.accent())
                                    }
                                }
                                Text(plan.status.displayLabel)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                                if !plan.goal.isEmpty {
                                    Text(plan.goal)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.mutedText())
                                        .lineLimit(2)
                                }
                                Text("\(plan.steps.count) steps")
                                    .font(.caption2)
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                        }
                        .buttonStyle(.plain)

                        Button {
                            openPlanDiscuss(plan)
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.body.weight(.semibold))
                                .foregroundColor(ColorTheme.accent())
                                .frame(width: 44, height: 44)
                                .background(ColorTheme.accent().opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Discuss \(plan.title)")
                        .padding(.trailing, Spacing.sm)
                        .padding(.top, Spacing.sm)
                    }

                    if showDecideActions {
                        HStack(spacing: 8) {
                            Button {
                                Haptics.success()
                                handlePlanProceed(plan)
                            } label: {
                                Text("Proceed")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(CenturionPrimaryButtonStyle())
                            .accessibilityLabel("Proceed with \(plan.title)")

                            Button {
                                Haptics.mediumTap()
                                handlePlanAdjust(plan)
                            } label: {
                                Text("Adjust")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(CenturionSecondaryButtonStyle())
                            .accessibilityLabel("Adjust \(plan.title)")

                            Button {
                                Haptics.lightTap()
                                handlePlanHold(plan)
                            } label: {
                                Text("Hold")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(CenturionGhostButtonStyle())
                            .accessibilityLabel("Hold \(plan.title)")
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.sm)
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - 4. DECISIONS — Only When Human Input Is Needed

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                    .foregroundColor(ColorTheme.warning())
                Text("Decisions needed")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("\(decisions.count)")
                    .font(.caption)
                    .foregroundColor(ColorTheme.warning())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ColorTheme.warning().opacity(0.1))
                    .clipShape(Capsule())
            }

            ForEach(decisions) { decision in
                decisionCard(decision)
                    .cardStyle()
            }
        }
        .opacity(isAppeared ? 1 : 0)
    }

    private func decisionCard(_ decision: DecisionItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Urgency badge
            HStack(spacing: 6) {
                // New indicator dot
                if isNew(decision.createdAt, category: .decisions) {
                    Circle()
                        .fill(ColorTheme.accent())
                        .frame(width: 6, height: 6)
                }

                urgencyBadge(decision.urgency)
                if let mission = decision.relatedMission {
                    Text(mission)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ColorTheme.accent())
                }
                Spacer()
                Button(action: {
                    openDiscuss(
                        title: "Decision: \(decision.title)",
                        detail: "\(decision.title)\n\n\(decision.context)"
                    )
                }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 11))
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
                Text(decision.generatedBy)
                    .font(.system(size: 8))
                    .foregroundColor(ColorTheme.mutedText())
            }

            Text(decision.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText())

            if decision.kind == .plan {
                Text("Your Sovereign proposes…")
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
            }

            Text(decision.context)
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineLimit(4)

            if decision.kind == .plan || decision.planId != nil {
                Button {
                    Haptics.lightTap()
                    if let planId = decision.planId, let plan = planStore.plan(id: planId) {
                        selectedPlan = plan
                    } else {
                        selectedPlan = PlanArtifact(
                            id: decision.planId ?? decision.id,
                            title: decision.title,
                            goal: decision.context,
                            steps: [],
                            risks: [],
                            openQuestions: [],
                            summary: decision.context,
                            relatedMission: decision.relatedMission,
                            signalId: decision.signalId,
                            status: .pendingReview,
                            createdAt: decision.createdAt
                        )
                    }
                } label: {
                    Text("Review this mission")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }

            // Options
            VStack(spacing: Spacing.xxs) {
                ForEach(decision.options) { option in
                    Button(action: {
                        handleDecisionOption(option, for: decision)
                    }) {
                        HStack {
                            Text(option.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(ColorTheme.primaryText())
                        .padding(Spacing.sm)
                        .background(ColorTheme.surface())
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ColorTheme.border(), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.warning().opacity(0.15), lineWidth: 0.5)
        )
    }

    private func urgencyBadge(_ urgency: DecisionItem.Urgency) -> some View {
        let color: Color = {
            switch urgency {
            case .now: return ColorTheme.error()
            case .today: return ColorTheme.warning()
            case .thisWeek: return ColorTheme.accent()
            case .whenever: return ColorTheme.mutedText()
            }
        }()
        return Text(urgency.rawValue.uppercased())
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - 4. THOUGHTS — Centurion's Stream

    private var thoughtsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Sovereign AI Remote")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Button(action: {
                    openDiscuss(
                        title: "Sovereign AI Remote",
                        detail: "General updates stream from your Sovereign."
                    )
                }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .buttonStyle(.plain)
            }

            ForEach(thoughts) { thought in
                HStack(spacing: Spacing.sm) {
                    // New indicator dot
                    if isNew(thought.timestamp, category: .pulse) {
                        Circle()
                            .fill(ColorTheme.accent())
                            .frame(width: 6, height: 6)
                    }

                    Image(systemName: thought.type.icon)
                        .font(.caption)
                        .foregroundColor(thoughtTypeColor(thought.type))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(thought.text)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.primaryText())
                        if let mission = thought.relatedMission {
                            Text(mission)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(ColorTheme.accent())
                        }
                    }

                    Spacer()

                    // Discuss this thought
                    Button(action: {
                        openDiscuss(
                            title: "\(thought.type.rawValue): \(String(thought.text.prefix(60)))",
                            detail: thought.text
                        )
                    }) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 10))
                            .foregroundColor(ColorTheme.mutedText())
                    }
                    .buttonStyle(.plain)

                    Text(timeAgo(thought.timestamp))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .padding(Spacing.sm)
                .background(thoughtTypeColor(thought.type).opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(thoughtTypeColor(thought.type).opacity(0.1), lineWidth: 0.5)
                )
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 24)
    }

    private func thoughtTypeColor(_ type: CenturionThought.ThoughtType) -> Color {
        switch type {
        case .alert: return ColorTheme.warning()
        case .insight: return ColorTheme.accent()
        case .progress: return ColorTheme.success()
        case .suggestion: return ColorTheme.accent()
        case .question: return ColorTheme.mutedText()
        case .win: return ColorTheme.accent()
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Live Pulse Dot

struct PulseDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(ColorTheme.accent())
            .opacity(isAnimating ? 1.0 : 0.25)
            .scaleEffect(isAnimating ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}
