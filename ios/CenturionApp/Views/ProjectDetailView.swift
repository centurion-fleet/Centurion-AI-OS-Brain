import SwiftUI

/// Mission Control program detail — targets expand inline to show tasks.
/// Drag-to-reorder targets with haptic feedback.
/// Tasks show their status at a glance: amber dots = done, outlined = in progress, gray = todo.
struct ProjectDetailView: View {
    let program: MissionProgram
    @State private var targets: [MissionTarget] = []
    @State private var selectedTarget: MissionTarget?
    @State private var showTargetDetail = false
    @State private var isAppeared = false
    
    /// Inline expansion — tap a target to see its tasks
    @State private var expandedTargetId: UUID?
    
    /// Drag reorder state
    @State private var draggedTarget: MissionTarget?
    @State private var dragOffset: CGSize = .zero
    
    /// Task commenting
    @State private var commentingOnTask: MissionTask?
    @State private var taskComment: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                programHeader
                
                if targets.isEmpty {
                    emptyTargets
                } else {
                    targetsList
                }
            }
            .padding()
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPreviewTargets()
            withAnimation(Motion.appear.delay(0.05)) {
                isAppeared = true
            }
        }
        .sheet(item: $commentingOnTask) { task in
            taskCommentSheet(task)
        }
    }
    
    private func loadPreviewTargets() {
        targets = MissionTarget.preview()
    }
    
    // MARK: - Program Header
    
    private var programHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: program.status.icon)
                    .foregroundColor(ColorTheme.accent())
                    .opacity(program.status.iconOpacity)
                    .font(.title3)
                Text(program.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText())
            }
            
            Text(program.description)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
            
            VStack(spacing: Spacing.xxs) {
                ProgressView(value: Double(program.completedTaskCount), total: Double(max(program.taskCount, 1)))
                    .tint(ColorTheme.accent())
                Text("\(program.completedTaskCount) of \(program.taskCount) tasks complete")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            .padding(.top, Spacing.xxs)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 8)
    }
    
    // MARK: - Empty State
    
    private var emptyTargets: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "target")
                .font(.system(size: 36))
                .foregroundColor(ColorTheme.mutedText())
            Text("No targets yet")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())
            Text("Targets will appear here once the Centurion creates them")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xxl)
    }
    
    // MARK: - Targets with Inline Tasks + Drag Reorder
    
    private var targetsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Targets", icon: "target")
            
            VStack(spacing: Spacing.xs) {
                ForEach(targets) { target in
                    VStack(spacing: 0) {
                        // Target row (tappable + draggable)
                        targetRow(target)
                        
                        // Inline tasks — shown when expanded
                        if expandedTargetId == target.id {
                            inlineTasks(for: target)
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
                    .gesture(
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
                                            for (i, _) in targets.enumerated() {
                                                targets[i].order = i
                                            }
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
        .cardStyle()
    }
    
    // MARK: - Target Row
    
    private func targetRow(_ target: MissionTarget) -> some View {
        let isExpanded = expandedTargetId == target.id
        
        return Button(action: {
            Haptics.lightTap()
            withAnimation(Motion.heavy) {
                if isExpanded {
                    expandedTargetId = nil
                } else {
                    expandedTargetId = target.id
                }
            }
        }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "line.horizontal.3")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.trailing, 2)
                
                Circle()
                    .fill(targetStatusColor(target.status))
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primaryText())
                    Text("\(target.status.rawValue) • \(target.tasks.count) tasks")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.accent())
            }
            .padding(Spacing.sm)
            .background(isExpanded ? ColorTheme.accent().opacity(0.04) : ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isExpanded ? ColorTheme.accent().opacity(0.3) : ColorTheme.border(), lineWidth: isExpanded ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Inline Tasks
    
    private func inlineTasks(for target: MissionTarget) -> some View {
        VStack(spacing: 0) {
            if target.tasks.isEmpty {
                Text("No tasks yet")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(target.tasks) { task in
                    taskRow(task)
                    if task.id != target.tasks.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .padding(.leading, 32)
        .padding(.vertical, Spacing.xxs)
        .background(ColorTheme.surface().opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func taskRow(_ task: MissionTask) -> some View {
        HStack(spacing: Spacing.sm) {
            // Status indicator — amber filled/outlined/gray
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
            
            // Comment button
            Button(action: {
                Haptics.lightTap()
                commentingOnTask = task
                taskComment = ""
            }) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
    
    /// Three-dot status system — like Things 3
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
    
    // MARK: - Task Commenting
    
    private func taskCommentSheet(_ task: MissionTask) -> some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                // Context header
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundColor(ColorTheme.accent())
                    Text("From: \(program.name) > task")
                        .font(.caption)
                        .foregroundColor(ColorTheme.accent())
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(ColorTheme.accent().opacity(0.05))
                
                VStack(spacing: Spacing.sm) {
                    // Task info
                    HStack {
                        taskStatusIcon(task.status)
                        Text(task.title)
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                    }
                    
                    Text("Leave a comment for your Centurion about this task. They'll see your message in context.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                    
                    // Comment input
                    HStack(spacing: Spacing.sm) {
                        TextField("Write your comment…", text: $taskComment)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(ColorTheme.chatInput())
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(ColorTheme.border(), lineWidth: 1)
                            )
                        
                        Button(action: { sendTaskComment(task) }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(
                                    taskComment.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? ColorTheme.mutedText() : ColorTheme.accent()
                                )
                        }
                        .disabled(taskComment.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, Spacing.md)
                
                Spacer()
            }
            .navigationTitle("Comment on Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel") { commentingOnTask = nil }
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
    
    private func sendTaskComment(_ task: MissionTask) {
        let comment = taskComment.trimmingCharacters(in: .whitespaces)
        guard !comment.isEmpty else { return }
        
        Haptics.messageSent()
        // In production: send to Centurion with full context
        // [User was viewing: $program.name > $expandedTarget (find target name) > $task.title]
        // User comment: $comment
        
        taskComment = ""
        commentingOnTask = nil
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
