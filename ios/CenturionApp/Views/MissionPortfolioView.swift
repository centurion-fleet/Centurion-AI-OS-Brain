import SwiftUI

/// Mission Control — the cockpit where the human aligns with their Centurion.
///
/// Everything is chat-able. Tap 💬 on any program to chat about it.
/// Those messages flow into the unified chat stream automatically.
struct MissionPortfolioView: View {
    @State private var mission: LifeMission = LifeMission.preview()
    @State private var programs: [MissionProgram] = MissionProgram.preview()
    @State private var thoughts: [CenturionThought] = CenturionThought.preview()
    @State private var focusActions: [FocusAction] = FocusAction.preview()
    @State private var searchText = ""
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var isAppeared = false

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
                    if connectionManager.connectionState == .connected {
                        StatusDot(isConnected: true)
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

    // MARK: - Mission Header

    private var missionHeader: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorTheme.accent())

                Spacer()

                // Chat about My Mission
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

    // MARK: - Vital Statistic

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
                        // Chat about alerts
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

    // MARK: - Focus Actions

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
                // Chat about focus
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

    // MARK: - Milestones (Programs)

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

// MARK: - Centurion Thought Preview

extension CenturionThought {
    static func preview() -> [CenturionThought] {
        [
            CenturionThought(id: UUID(), text: "Q3 Go-to-Market target is on track. Revenue at 74% of quarterly target with 6 weeks remaining.", type: .progress, timestamp: Date().addingTimeInterval(-300), relatedTarget: "Q3 Go-to-Market"),
            CenturionThought(id: UUID(), text: "Content Strategy target is blocked. 'Draft messaging framework' awaiting stakeholder feedback for 8 days.", type: .alert, timestamp: Date().addingTimeInterval(-600), relatedTarget: "Content Strategy"),
            CenturionThought(id: UUID(), text: "I suggest we reprioritise Partner Onboarding ahead of Content Strategy given the revenue impact.", type: .suggestion, timestamp: Date().addingTimeInterval(-3600), relatedTarget: "Partner Onboarding"),
            CenturionThought(id: UUID(), text: "Cashflow projection updated. Next 30 days look stable.", type: .insight, timestamp: Date().addingTimeInterval(-7200), relatedTarget: nil),
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
                    // Chat button — thin grey line icon
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
