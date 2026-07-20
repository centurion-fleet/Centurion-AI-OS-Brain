import SwiftUI

/// Mission program detail — milestones expand inline to show tasks.
/// Everything is chat-able. Tap 💬 on any target or task to open the unified chat.
struct ProjectDetailView: View {
    let program: MissionProgram
    @EnvironmentObject private var messageService: MessageService
    @State private var targets: [MissionTarget] = []
    @State private var isAppeared = false

    /// Inline expansion
    @State private var expandedTargetId: UUID?

    /// Drag reorder state
    @State private var draggedTarget: MissionTarget?
    @State private var dragOffset: CGSize = .zero

    /// Unified chat sheet state — single source of truth
    @State private var chatTarget: ChatSheetTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                programHeader

                if targets.isEmpty {
                    emptyTargets
                } else {
                    targetsList
                }
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(secondaryBackground)
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPreviewTargets()
            withAnimation(Motion.appear.delay(0.05)) {
                isAppeared = true
            }
        }
        .sheet(item: $chatTarget) { target in
            chatSheet(for: target.context)
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()
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

    private func openTargetChat(_ target: MissionTarget) {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .target(id: target.id, name: target.title, programName: program.name))
    }

    private func openTaskChat(_ task: MissionTask, in target: MissionTarget) {
        Haptics.lightTap()
        chatTarget = ChatSheetTarget(context: .task(id: task.id, name: task.title, targetName: target.title, programName: program.name))
    }

    private func loadPreviewTargets() {
        targets = MissionTarget.preview()
    }

    // MARK: - Program Header

    private var programHeader: some View {
        AtmosphericSurface(elevated: true, showRim: true) {
            VStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: program.status.icon)
                        .foregroundColor(ColorTheme.accent())
                        .opacity(program.status.iconOpacity)
                        .font(.title3)
                    Text(program.name)
                        .font(Typography.screenTitle)
                        .foregroundColor(ColorTheme.primaryText())
                }

                Text(program.description)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                VStack(spacing: Spacing.xxs) {
                    ProgressView(value: Double(program.completedTaskCount), total: Double(max(program.taskCount, 1)))
                        .tint(ColorTheme.accent())
                    Text("\(program.completedTaskCount) of \(program.taskCount) tasks complete")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
                .padding(.top, Spacing.xxs)
            }
            .frame(maxWidth: .infinity)
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 8)
    }

    // MARK: - Empty State

    private var emptyTargets: some View {
        EmptyState(
            icon: "target",
            title: "No milestones yet",
            message: "Milestones will appear here once the Sovereign creates them"
        )
    }

    // MARK: - Targets with Inline Tasks + Drag Reorder

    private var targetsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Milestones", icon: "target")

            VStack(spacing: Spacing.xs) {
                ForEach(targets) { target in
                    VStack(spacing: 0) {
                        targetRow(target)

                        if expandedTargetId == target.id {
                            inlineTasks(for: target, parentTarget: target)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .offset(
                        x: draggedTarget?.id == target.id ? dragOffset.width : 0,
                        y: draggedTarget?.id == target.id ? dragOffset.height : 0
                    )
                    .zIndex(draggedTarget?.id == target.id ? 100 : 0)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .sequenced(before: DragGesture())
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    if let drag = drag {
                                        if draggedTarget == nil {
                                            Haptics.lightTap()
                                            draggedTarget = target
                                        }
                                        dragOffset = drag.translation
                                    }
                                default:
                                    break
                                }
                            }
                            .onEnded { _ in
                                guard let dragged = draggedTarget else { return }
                                let cardHeight: CGFloat = 52
                                let moveCount = Int(dragOffset.height / cardHeight)
                                withAnimation(Motion.heavy) {
                                    if let fromIndex = targets.firstIndex(where: { $0.id == dragged.id }) {
                                        let toIndex = max(0, min(fromIndex + moveCount, targets.count - 1))
                                        if toIndex != fromIndex {
                                            targets.move(fromOffsets: IndexSet(integer: fromIndex),
                                                         toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                            for (i, _) in targets.enumerated() { targets[i].order = i }
                                        }
                                    }
                                    dragOffset = .zero
                                    draggedTarget = nil
                                }
                                Haptics.success()
                            }
                    )
                    .opacity(draggedTarget?.id == target.id ? 0.85 : 1.0)
                    .scaleEffect(draggedTarget?.id == target.id ? 1.02 : 1.0)
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : 12)
                    .animation(Motion.appear.delay(Double(target.order) * 0.06), value: isAppeared)
                }
            }
        }
    }

    // MARK: - Target Row

    private func targetRow(_ target: MissionTarget) -> some View {
        let isExpanded = expandedTargetId == target.id

        return AtmosphericSurface(elevated: isExpanded) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "line.horizontal.3")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.trailing, 2)

                Circle()
                    .fill(targetStatusColor(target.status))
                    .frame(width: 8, height: 8)

                Button(action: {
                    Haptics.lightTap()
                    withAnimation(Motion.heavy) {
                        if isExpanded {
                            expandedTargetId = nil
                        } else {
                            expandedTargetId = target.id
                        }
                    }
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(ColorTheme.primaryText())
                        Text("\(target.status.rawValue) • \(target.tasks.count) tasks")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { openTargetChat(target) }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.accent())
            }
        }
    }

    // MARK: - Inline Tasks

    private func inlineTasks(for target: MissionTarget, parentTarget: MissionTarget) -> some View {
        AtmosphericSurface {
            VStack(spacing: 0) {
                if target.tasks.isEmpty {
                    Text("No tasks yet")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(target.tasks) { task in
                        taskRow(task, in: target)
                        if task.id != target.tasks.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.top, Spacing.xxs)
    }

    private func taskRow(_ task: MissionTask, in target: MissionTarget) -> some View {
        HStack(spacing: Spacing.sm) {
            taskStatusIcon(task.status)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primaryText())

                    if task.isBlocked {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Text(task.status.rawValue)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
            }

            Spacer()

            if task.isBlocked, let reason = task.blockedReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(.orange.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .trailing)
            }

            Button(action: { openTaskChat(task, in: target) }) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(ColorTheme.mutedText())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Three-Dot Status System

    private func taskStatusIcon(_ status: MissionTask.TaskStatus) -> some View {
        Group {
            switch status {
            case .done:
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(ColorTheme.accent())
                            .frame(width: 5, height: 5)
                    }
                }
            case .inProgress:
                HStack(spacing: 3) {
                    Circle()
                        .fill(ColorTheme.accent())
                        .frame(width: 5, height: 5)
                    Circle()
                        .stroke(ColorTheme.accent(), lineWidth: 1)
                        .frame(width: 5, height: 5)
                    Circle()
                        .stroke(ColorTheme.mutedText(), lineWidth: 1)
                        .frame(width: 5, height: 5)
                }
            case .todo:
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(ColorTheme.mutedText(), lineWidth: 1)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(width: 24)
    }

    // MARK: - Helpers

    private func targetStatusColor(_ status: MissionTarget.TargetStatus) -> Color {
        switch status {
        case .active: return ColorTheme.accent()
        case .review: return ColorTheme.accent().opacity(0.7)
        case .backlog: return ColorTheme.mutedText()
        case .completed: return ColorTheme.accent()
        }
    }
}

// MARK: - Preview Data

extension MissionTarget {
    static func preview() -> [MissionTarget] {
        let tasks = [
            MissionTask(id: UUID(), targetId: UUID(), title: "Research market positioning", description: "Analyse competitive landscape", status: .done, order: 0, isBlocked: false, createdAt: Date()),
            MissionTask(id: UUID(), targetId: UUID(), title: "Draft messaging framework", description: "Core narrative and key messages", status: .inProgress, order: 1, isBlocked: true, blockedReason: "Awaiting feedback", createdAt: Date()),
            MissionTask(id: UUID(), targetId: UUID(), title: "Design visual assets", description: "Brand deck and one-pager", status: .todo, order: 2, isBlocked: false, createdAt: Date()),
            MissionTask(id: UUID(), targetId: UUID(), title: "Finalise budget allocation", description: "Q3 spend approval", status: .todo, order: 3, isBlocked: true, blockedReason: "Pending director review", createdAt: Date()),
        ]

        return [
            MissionTarget(id: UUID(), programId: UUID(), title: "Q3 Go-to-Market", description: "Launch campaign", status: .active, order: 0, tasks: tasks, createdAt: Date()),
            MissionTarget(id: UUID(), programId: UUID(), title: "Partner Onboarding", description: "Onboard partners", status: .backlog, order: 1, tasks: [], createdAt: Date()),
            MissionTarget(id: UUID(), programId: UUID(), title: "Content Strategy", description: "Blog and whitepapers", status: .review, order: 2, tasks: [
                MissionTask(id: UUID(), targetId: UUID(), title: "Write Q3 thought leadership piece", description: "", status: .todo, order: 0, isBlocked: false, createdAt: Date()),
            ], createdAt: Date()),
        ]
    }
}
