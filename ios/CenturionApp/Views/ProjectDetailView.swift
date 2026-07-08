import SwiftUI

/// Mission Control program detail — targets and tasks
/// Drag-to-reorder targets with haptic feedback.
struct ProjectDetailView: View {
    let program: MissionProgram
    @State private var targets: [MissionTarget] = []
    @State private var selectedTarget: MissionTarget?
    @State private var showTargetDetail = false
    @State private var isAppeared = false
    
    /// Drag reorder state
    @State private var draggedTarget: MissionTarget?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Program header
                programHeader
                
                // Targets with drag reorder
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
        .sheet(isPresented: $showTargetDetail) {
            if let target = selectedTarget {
                TargetDetailView(target: target)
            }
        }
        .onAppear {
            loadPreviewTargets()
            withAnimation(Motion.appear.delay(0.05)) {
                isAppeared = true
            }
        }
    }
    
    private func loadPreviewTargets() {
        // In production, load from API
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
            
            // Progress ring
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
    
    // MARK: - Targets with Drag Reorder
    
    private var targetsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Targets", icon: "target")
            
            VStack(spacing: Spacing.xs) {
                ForEach(targets) { target in
                    targetRow(target)
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
                .onMove { source, destination in
                    withAnimation(Motion.heavy) {
                        targets.move(fromOffsets: source, toOffset: destination)
                        for (i, _) in targets.enumerated() {
                            targets[i].order = i
                        }
                    }
                }
            }
        }
        .cardStyle()
    }
    
    private func targetRow(_ target: MissionTarget) -> some View {
        Button(action: {
            Haptics.mediumTap()
            selectedTarget = target
            showTargetDetail = true
        }) {
            HStack(spacing: Spacing.sm) {
                // Drag handle
                Image(systemName: "line.horizontal.3")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.trailing, 2)
                
                // Status dot
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
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
            }
            .padding(Spacing.sm)
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )
            .shadow(color: draggedTarget?.id == target.id ? ColorTheme.accent().opacity(0.1) : .clear,
                    radius: draggedTarget?.id == target.id ? 8 : 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private func targetStatusColor(_ status: MissionTarget.TargetStatus) -> Color {
        switch status {
        case .active: return ColorTheme.accent()
        case .review: return ColorTheme.accent().opacity(0.7)
        case .backlog: return ColorTheme.mutedText()
        case .completed: return ColorTheme.accent()
        }
    }
}

// MARK: - Target Preview Data

extension MissionTarget {
    static func preview() -> [MissionTarget] {
        let tasks = [
            MissionTask(id: UUID(), targetId: UUID(), title: "Research market positioning", description: "Analyse competitive landscape", status: .done, order: 0, isBlocked: false, createdAt: Date()),
            MissionTask(id: UUID(), targetId: UUID(), title: "Draft messaging framework", description: "Core narrative and key messages", status: .inProgress, order: 1, isBlocked: true, blockedReason: "Awaiting feedback", createdAt: Date()),
        ]
        
        return [
            MissionTarget(id: UUID(), programId: UUID(), title: "Q3 Go-to-Market", description: "Launch campaign", status: .active, order: 0, tasks: tasks, createdAt: Date()),
            MissionTarget(id: UUID(), programId: UUID(), title: "Partner Onboarding", description: "Onboard partners", status: .backlog, order: 1, tasks: [], createdAt: Date()),
            MissionTarget(id: UUID(), programId: UUID(), title: "Content Strategy", description: "Blog and whitepapers", status: .review, order: 2, tasks: [], createdAt: Date()),
        ]
    }
}

// MARK: - Target Detail Sheet

struct TargetDetailView: View {
    let target: MissionTarget
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Status", value: target.status.rawValue)
                    LabeledContent("Created", value: target.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                
                Section("Tasks (\(target.tasks.count))") {
                    ForEach(target.tasks) { task in
                        HStack {
                            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.status == .done ? ColorTheme.accent() : ColorTheme.mutedText())
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
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
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                                if task.isBlocked, let reason = task.blockedReason {
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Text("All targets and tasks are end-to-end encrypted")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
