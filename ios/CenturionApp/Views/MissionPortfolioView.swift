import SwiftUI

/// Centurion Remote — the AI's dashboard. The human's window into what their
/// Centurion is doing, has done, and needs.
///
/// This is NOT a human project management tool. There are no tasks to check off,
/// no milestones to track, no human-speed progress bars. This is the Centurion's
/// cockpit — showing live loops, completed wins, and decisions that need the human.
///
/// Notification system: each category has a badge count for items newer than
/// the user's last visit to that category. Badges clear when you tap the pill.
enum PulseCategory: String, CaseIterable {
    case live = "LIVE"
    case wins = "WINS"
    case outputs = "OUTPUTS"
    case decisions = "DECISIONS"
    case pulse = "PULSE"

    var icon: String {
        switch self {
        case .live: return "bolt.fill"
        case .wins: return "star.fill"
        case .outputs: return "doc.text.fill"
        case .decisions: return "hand.raised.fill"
        case .pulse: return "waveform.path.ecg"
        }
    }
}

struct MissionPortfolioView: View {
    @State private var mission: LifeMission = LifeMission.preview()
    @State private var liveActivity: LiveActivity? = LiveActivity.preview()
    @State private var completedLoops: [CompletedLoop] = CompletedLoop.preview()
    @State private var decisions: [DecisionItem] = DecisionItem.preview()
    @State private var outputs: [CenturionOutput] = CenturionOutput.preview()
    @State private var thoughts: [CenturionThought] = CenturionThought.preview()
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var isAppeared = false
    @State private var liveExpanded = true
    @State private var selectedCategory: PulseCategory = .live

    /// Unified chat sheet state
    @State private var chatTarget: ChatSheetTarget?
    /// Output document viewer state
    @State private var selectedOutput: CenturionOutput?

    // MARK: - Notification tracking
    // Stores the last time each category was viewed. Items newer than this date
    // show a "new" indicator and contribute to the pill badge count.
    @AppStorage("pulse_note_live")     private var lastSeenLive: TimeInterval = 0
    @AppStorage("pulse_note_wins")     private var lastSeenWins: TimeInterval = 0
    @AppStorage("pulse_note_outputs")  private var lastSeenOutputs: TimeInterval = 0
    @AppStorage("pulse_note_decisions") private var lastSeenDecisions: TimeInterval = 0
    @AppStorage("pulse_note_pulse")    private var lastSeenThoughts: TimeInterval = 0

    /// Count of unseen items per category
    private var badgeCounts: [PulseCategory: Int] {
        let wins = Date(timeIntervalSinceReferenceDate: lastSeenWins)
        let outputs = Date(timeIntervalSinceReferenceDate: lastSeenOutputs)
        let decisions = Date(timeIntervalSinceReferenceDate: lastSeenDecisions)
        let thoughts = Date(timeIntervalSinceReferenceDate: lastSeenThoughts)
        return [
            .live: 0,
            .wins: completedLoops.filter { $0.completedAt > wins }.count,
            .outputs: self.outputs.filter { $0.createdAt > outputs }.count,
            .decisions: self.decisions.filter { $0.createdAt > decisions }.count,
            .pulse: self.thoughts.filter { $0.timestamp > thoughts }.count,
        ]
    }

    /// Mark a category as seen — clear its badge
    private func markSeen(_ category: PulseCategory) {
        let now = Date.timeIntervalSinceReferenceDate
        switch category {
        case .live:     lastSeenLive = now
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
        case .wins:     threshold = Date(timeIntervalSinceReferenceDate: lastSeenWins)
        case .outputs:  threshold = Date(timeIntervalSinceReferenceDate: lastSeenOutputs)
        case .decisions: threshold = Date(timeIntervalSinceReferenceDate: lastSeenDecisions)
        case .pulse:    threshold = Date(timeIntervalSinceReferenceDate: lastSeenThoughts)
        }
        return date > threshold
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pill navigation — one category at a time
                pillNavigation

                ScrollView {
                    VStack(spacing: Spacing.md) {
                        // Only the selected category renders
                        switch selectedCategory {
                        case .live:
                            liveActivitySection
                        case .wins:
                            completedLoopsSection
                        case .outputs:
                            if !outputs.isEmpty {
                                outputsSection
                            } else {
                                emptyCategory("No outputs yet", "Documents the Centurion creates will appear here")
                            }
                        case .decisions:
                            if !decisions.isEmpty {
                                decisionsSection
                            } else {
                                emptyCategory("All clear", "Nothing needs your attention right now")
                            }
                        case .pulse:
                            thoughtsSection
                        }
                    }
                    .frame(maxWidth: 428)
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(Motion.appear.delay(0.1)) {
                    isAppeared = true
                }
            }
        }
        .sheet(item: $chatTarget) { target in
            chatSheet(for: target.context)
        }
    }

    // MARK: - Pill Navigation

    private var pillNavigation: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PulseCategory.allCases, id: \.self) { category in
                    Button(action: {
                        Haptics.lightTap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedCategory = category
                        }
                        markSeen(category)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: 9))
                            Text(category.rawValue)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1)

                            // Badge count
                            if let count = badgeCounts[category], count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(ColorTheme.mutedText().opacity(0.5))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(selectedCategory == category
                            ? ColorTheme.primaryText()
                            : ColorTheme.mutedText())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedCategory == category
                            ? ColorTheme.mutedText().opacity(0.1)
                            : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            selectedCategory == category
                                ? Capsule().stroke(ColorTheme.mutedText().opacity(0.2), lineWidth: 0.5)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(ColorTheme.background())
    }

    // MARK: - Chat Sheet

    private func chatSheet(for context: ConversationContext) -> some View {
        let conversation = messageService.findOrCreateConversation(for: context)
        return NavigationStack {
            ChatView(conversation: conversation)
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

    // MARK: - Mission Statement

    private var missionStatement: some View {
        VStack(spacing: 4) {
            Text("Advancing")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(ColorTheme.dimAccent())
                .tracking(3)
                .textCase(.uppercase)

            Text(mission.statement)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Rectangle()
                .fill(ColorTheme.accent())
                .frame(width: 40, height: 2)
                .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 10)
    }

    // MARK: - 1. LIVE — What the Centurion Is Doing Right Now

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            Button(action: {
                withAnimation(Motion.heavy) { liveExpanded.toggle() }
            }) {
                HStack(spacing: Spacing.xs) {
                    PulseDot()
                        .frame(width: 10, height: 10)

                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ColorTheme.accent())
                        .tracking(3)

                    if let activity = liveActivity {
                        Text(activity.phase.rawValue.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(ColorTheme.dimAccent())
                            .tracking(2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ColorTheme.accent().opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let activity = liveActivity {
                        Text("\(Int(activity.progress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                // Orbital agent visualization — mesmerising to watch
                LoopVisualizationView(activity: activity)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ColorTheme.border(), lineWidth: 0.5)
                    )

                // Loop phase bar
                loopPhaseBar(currentPhase: activity.phase)

                // Activity details
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(activity.summary)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText())

                    Text(activity.detail)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(3)

                    // Progress
                    ProgressView(value: activity.progress)
                        .tint(ColorTheme.accent())

                    // Est completion
                    if let est = activity.estimatedCompletion {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("Est. \(Int(est / 60))m remaining")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(ColorTheme.dimAccent())
                    }

                    // Sub-agents
                    if !activity.subAgents.isEmpty {
                        VStack(spacing: Spacing.xxs) {
                            ForEach(activity.subAgents) { agent in
                                subAgentRow(agent)
                            }
                        }
                        .padding(Spacing.sm)
                        .background(ColorTheme.accent().opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Chat about this activity
                    HStack {
                        Spacer()
                        Button(action: {
                            openChat(context: .standalone(title: "Centurion Remote — Live Activity"))
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 10))
                                Text("Discuss this")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(ColorTheme.accent())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .cardStyle()
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
                                .foregroundColor(.black)
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
                               : agent.status == .completed ? .green
                               : agent.status == .error ? .red
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
                    .foregroundColor(.green)

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
            .foregroundColor(.green)

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

            // Share this win
            HStack {
                Spacer()
                Button(action: {
                    openChat(context: .standalone(title: "Win: \(loop.summary)"))
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
        }
        .padding()
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - 3. OUTPUTS — Documents the Centurion Created

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Outputs")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("\(outputs.count) documents")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ColorTheme.mutedText())
            }

            ForEach(outputs) { output in
                outputCard(output)
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 30)
    }

    private func outputCard(_ output: CenturionOutput) -> some View {
        VStack(spacing: 0) {
            // Tappable content area — opens DocumentViewer
            Button(action: {
                selectedOutput = output
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

                        Text(output.summary)
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
                    openChat(context: .standalone(title: "Output: \(output.title)"))
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

    // MARK: - 4. DECISIONS — Only When Human Input Is Needed

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Needs Your Decision")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("\(decisions.count)")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }

            ForEach(decisions) { decision in
                decisionCard(decision)
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
                    openChat(context: .standalone(title: "Decision: \(decision.title)"))
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

            Text(decision.context)
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineLimit(4)

            // Options
            VStack(spacing: Spacing.xxs) {
                ForEach(decision.options) { option in
                    Button(action: {
                        Haptics.mediumTap()
                        openChat(context: .standalone(title: "Decision: \(decision.title) — \(option.label)"))
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
                .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Empty State

    private func emptyCategory(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer().frame(height: 60)
            Image(systemName: "sparkle")
                .font(.system(size: 32))
                .foregroundColor(ColorTheme.dimAccent())
            Text(title)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func urgencyBadge(_ urgency: DecisionItem.Urgency) -> some View {
        let color: Color = {
            switch urgency {
            case .now: return .red
            case .today: return .orange
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
                Text("Centurion Remote")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Button(action: {
                    openChat(context: .standalone(title: "Centurion Remote"))
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
                        openChat(context: .standalone(
                            title: "\(thought.type.rawValue): \(String(thought.text.prefix(60)))..."
                        ))
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
        case .alert: return .orange
        case .insight: return ColorTheme.accent()
        case .progress: return .green
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
