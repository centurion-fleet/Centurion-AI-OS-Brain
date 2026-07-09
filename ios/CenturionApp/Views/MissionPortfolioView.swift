import SwiftUI

/// Mission Control — the cockpit where the human aligns with their Centurion.
///
/// Two layers of time live here:
///   • HUMAN SPEED — mission statement, vital stat, programs, milestones — days/weeks/months
///   • AI SPEED — the Centurion's live loops, sub-agents, discoveries — seconds/minutes
///
/// The Centurion Pulse section makes the invisible visible: your AI is working
/// at the speed of thought, and you can see every cycle, every agent, every insight.
/// Everything is chat-able. Tap 💬 on anything to open the unified stream.
struct MissionPortfolioView: View {
    @State private var mission: LifeMission = LifeMission.preview()
    @State private var programs: [MissionProgram] = MissionProgram.preview()
    @State private var activity: CenturionActivity? = CenturionActivity.preview()
    @State private var thoughts: [CenturionThought] = CenturionThought.preview()
    @State private var focusActions: [FocusAction] = FocusAction.preview()
    @State private var searchText = ""
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var isAppeared = false
    @State private var pulseExpanded = true

    /// Drag reorder state
    @State private var draggedProgram: MissionProgram?
    @State private var dragOffset: CGSize = .zero

    /// Unified chat sheet state
    @State private var chatTarget: ChatSheetTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    missionHeader
                    centurionPulseSection      // 🆕 AI-speed visibility
                    vitalStatCard
                    alertsSection
                    focusActionsSection
                    targetsSection
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("My Mission")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if activity != nil {
                            LoopPhaseIndicator(phase: activity!.phase)
                        }
                        if connectionManager.connectionState == .connected {
                            StatusDot(isConnected: true)
                        }
                    }
                }
            }
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

    // MARK: - Chat Sheet (unified)

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

    private func openChat(for program: MissionProgram) {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .program(id: program.id, name: program.name))
    }

    private func openMissionChat() {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .standalone(title: "My Mission"))
    }

    private func openAlertsChat() {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .standalone(title: "Alerts & Pulse"))
    }

    private func openFocusChat() {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .standalone(title: "Focus Today"))
    }

    private func openPulseChat() {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .standalone(title: "Centurion Remote"))
    }

    // MARK: - Mission Header (Human Speed)

    private var missionHeader: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorTheme.accent())

                Spacer()

                Button(action: { openMissionChat() }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .buttonStyle(.plain)
            }

            Text(mission.statement)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
                .lineSpacing(4)

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

    // MARK: - Centurion Pulse (AI Speed) 🆕

    private var centurionPulseSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with expand/collapse
            Button(action: {
                withAnimation(Motion.heavy) { pulseExpanded.toggle() }
            }) {
                HStack(spacing: Spacing.xs) {
                    if let activity = activity {
                        // Animated phase indicator
                        PulseDot(phase: activity.phase)
                            .frame(width: 10, height: 10)
                    }

                    Text("Centurion Remote")
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())

                    Spacer()

                    if let activity = activity {
                        Text("\(Int(activity.progress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(ColorTheme.accent())
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .rotationEffect(.degrees(pulseExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if pulseExpanded, let activity = activity {
                // Loop phase indicator bar
                loopPhaseBar(currentPhase: activity.phase)

                // Activity detail card
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.summary)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.primaryText())
                            Text(activity.detail)
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                                .lineLimit(2)
                        }

                        Spacer()

                        // Chat about current activity
                        Button(action: { openPulseChat() }) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ColorTheme.mutedText())
                        }
                        .buttonStyle(.plain)
                    }

                    // Progress bar
                    ProgressView(value: activity.progress)
                        .tint(ColorTheme.accent())

                    // Sub-agents working in parallel
                    if !activity.subAgents.isEmpty {
                        VStack(spacing: Spacing.xs) {
                            Text("\(activity.agentCount) agents working in parallel")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(ColorTheme.mutedText())
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(activity.subAgents) { agent in
                                subAgentRow(agent)
                            }
                        }
                        .padding(Spacing.sm)
                        .background(ColorTheme.accent().opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func loopPhaseBar(currentPhase: CenturionActivity.LoopPhase) -> some View {
        HStack(spacing: 0) {
            ForEach(CenturionActivity.LoopPhase.allCases.filter { $0 != .idle }, id: \.self) { phase in
                let isActive = phase == currentPhase
                let isPast = phaseIndex(phase) < phaseIndex(currentPhase)

                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isPast ? ColorTheme.accent() : (isActive ? ColorTheme.accent().opacity(0.2) : Color.clear))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(isActive ? ColorTheme.accent() : ColorTheme.border(), lineWidth: 1.5)
                            )

                        if isPast {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                        } else {
                            Image(systemName: phase.icon)
                                .font(.system(size: 11))
                                .foregroundColor(isActive ? ColorTheme.accent() : ColorTheme.mutedText())
                        }
                    }

                    Text(phase.rawValue)
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? ColorTheme.accent() : ColorTheme.mutedText())
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)

                if phase != .verifying {
                    Rectangle()
                        .fill(isPast ? ColorTheme.accent() : ColorTheme.border())
                        .frame(height: 1)
                        .frame(maxWidth: 16)
                }
            }
        }
    }

    private func phaseIndex(_ phase: CenturionActivity.LoopPhase) -> Int {
        CenturionActivity.LoopPhase.allCases.firstIndex(of: phase) ?? 0
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

    // MARK: - Vital Statistic (Human Speed)

    private var vitalStatCard: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(ColorTheme.border(), lineWidth: 4)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: mission.vitalProgress)
                    .stroke(ColorTheme.accent(), lineWidth: 4)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.heavy, value: mission.vitalProgress)
                Text("\(Int(mission.vitalProgress * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ColorTheme.accent())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Vital Statistic")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .textCase(.uppercase)
                Text(mission.vitalStatName)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                HStack(spacing: 4) {
                    Text("\(mission.vitalStatCurrent, format: .number)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.accent())
                    Text("of \(mission.vitalStatTarget, format: .number)")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }

            Spacer()
        }
        .padding()
        .cardStyle()
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 8)
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        let alertThoughts = thoughts.filter { $0.type == .alert }

        return Group {
            if !alertThoughts.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Alerts")
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text("\(alertThoughts.count)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                        Button(action: { openAlertsChat() }) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ColorTheme.mutedText())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(alertThoughts) { thought in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(thought.text)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(ColorTheme.primaryText())
                                if let target = thought.relatedTarget {
                                    Text(target)
                                        .font(.caption2)
                                        .foregroundColor(ColorTheme.accent())
                                }
                            }

                            Spacer()
                        }
                        .padding(Spacing.sm)
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                        )
                    }
                }
                .opacity(isAppeared ? 1 : 0)
            }
        }
    }

    // MARK: - Focus Today (Human Speed)

    private var focusActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Focus Today")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("\(focusActions.filter { !$0.isDone }.count) remaining")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                Button(action: { openFocusChat() }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .buttonStyle(.plain)
            }

            ForEach(focusActions) { action in
                Button(action: {
                    Haptics.lightTap()
                    withAnimation(Motion.light) {
                        if let idx = focusActions.firstIndex(where: { $0.id == action.id }) {
                            focusActions[idx].isDone.toggle()
                        }
                    }
                }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: action.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(action.isDone ? ColorTheme.accent() : ColorTheme.mutedText())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(action.isDone ? ColorTheme.mutedText() : ColorTheme.primaryText())
                                .strikethrough(action.isDone)
                            Text(action.targetName)
                                .font(.caption2)
                                .foregroundColor(ColorTheme.accent())
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .cardStyle()
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 24)
    }

    // MARK: - Mission Programs (Human Speed)

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Mission Programs", icon: "target")

            VStack(spacing: Spacing.sm) {
                ForEach(programs) { program in
                    ProgramCard(program: program, onChat: { openChat(for: program) })
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "line.horizontal.3")
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                                .padding(Spacing.xs)
                        }
                        .offset(
                            x: draggedProgram?.id == program.id ? dragOffset.width : 0,
                            y: draggedProgram?.id == program.id ? dragOffset.height : 0
                        )
                        .zIndex(draggedProgram?.id == program.id ? 100 : 0)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.3)
                                .sequenced(before: DragGesture())
                                .onChanged { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if let drag = drag {
                                            if draggedProgram == nil {
                                                Haptics.mediumTap()
                                                draggedProgram = program
                                            }
                                            dragOffset = drag.translation
                                        }
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    guard let dragged = draggedProgram else { return }
                                    let dropIndex = indexFor(y: dragOffset.height, draggedId: dragged.id)
                                    withAnimation(Motion.heavy) {
                                        if let fromIndex = programs.firstIndex(where: { $0.id == dragged.id }),
                                           let toIndex = dropIndex {
                                            programs.move(fromOffsets: IndexSet(integer: fromIndex),
                                                          toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                            for (i, _) in programs.enumerated() { programs[i].order = i }
                                        }
                                        dragOffset = .zero
                                        draggedProgram = nil
                                    }
                                    Haptics.success()
                                }
                        )
                        .opacity(draggedProgram?.id == program.id ? 0.9 : 1.0)
                }
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 32)
    }

    private func indexFor(y offset: CGFloat, draggedId: UUID) -> Int? {
        let cardHeight: CGFloat = 120
        let moveCount = Int(offset / cardHeight)
        guard let currentIndex = programs.firstIndex(where: { $0.id == draggedId }) else { return nil }
        let newIndex = currentIndex + moveCount
        return max(0, min(newIndex, programs.count - 1))
    }
}

// MARK: - Pulse Dot

/// An animated dot that indicates the Centurion is actively looping.
struct PulseDot: View {
    let phase: CenturionActivity.LoopPhase
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(phaseColor)
            .opacity(isAnimating ? 1.0 : 0.3)
            .scaleEffect(isAnimating ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }

    private var phaseColor: Color {
        switch phase {
        case .discovering: return ColorTheme.accent()
        case .planning: return ColorTheme.accent()
        case .executing: return ColorTheme.accent()
        case .verifying: return .green
        case .idle: return ColorTheme.mutedText()
        }
    }
}

// MARK: - Loop Phase Indicator

struct LoopPhaseIndicator: View {
    let phase: CenturionActivity.LoopPhase

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: phase.icon)
                .font(.system(size: 8))
            Text(phase.rawValue)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(ColorTheme.accent())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ColorTheme.accent().opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Centurion Thought Preview

extension CenturionThought {
    static func preview() -> [CenturionThought] {
        [
            CenturionThought(id: UUID(), text: "Q3 Go-to-Market target is on track. Revenue at 74% of quarterly target with 6 weeks remaining.", type: .progress, timestamp: Date().addingTimeInterval(-300), relatedTarget: "Q3 Go-to-Market", phase: .verifying),
            CenturionThought(id: UUID(), text: "Content Strategy target is blocked. 'Draft messaging framework' awaiting stakeholder feedback for 8 days.", type: .alert, timestamp: Date().addingTimeInterval(-600), relatedTarget: "Content Strategy", phase: .executing),
            CenturionThought(id: UUID(), text: "I suggest we reprioritise Partner Onboarding ahead of Content Strategy given the revenue impact.", type: .suggestion, timestamp: Date().addingTimeInterval(-3600), relatedTarget: "Partner Onboarding", phase: .planning),
            CenturionThought(id: UUID(), text: "Cashflow projection updated. Next 30 days look stable.", type: .insight, timestamp: Date().addingTimeInterval(-7200), relatedTarget: nil, phase: .discovering),
        ]
    }
}

// MARK: - Program Card

struct ProgramCard: View {
    let program: MissionProgram
    var onChat: (() -> Void)?

    var body: some View {
        NavigationLink(destination: ProjectDetailView(program: program)) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: program.status.icon)
                    .font(.title3)
                    .foregroundColor(ColorTheme.accent())
                    .opacity(program.status.iconOpacity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())
                    Text(program.description)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { onChat?() }) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(ColorTheme.mutedText())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(program.completedTaskCount)/\(program.taskCount)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(ColorTheme.accent())
                        Text("tasks")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
            }
            .padding()
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}
