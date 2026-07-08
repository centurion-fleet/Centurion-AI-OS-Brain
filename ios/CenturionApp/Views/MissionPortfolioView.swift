import SwiftUI

/// Mission Control — the user's mission overview.
/// Programs sit at the top as hero cards, with drag-to-reorder.
/// Blocked tasks raise amber alerts. A context chat button lets the
/// user share thoughts from anywhere.
struct MissionPortfolioView: View {
    @State private var programs: [MissionProgram] = MissionProgram.preview()
    @State private var searchText = ""
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isAppeared = false
    
    /// Drag reorder state
    @State private var draggedProgram: MissionProgram?
    @State private var dragOffset: CGSize = .zero
    
    /// Blocked tasks
    private var blockedTasks: [(program: MissionProgram, task: MissionTask)] {
        var result: [(MissionProgram, MissionTask)] = []
        for program in programs {
            // In production, targets and tasks would be loaded from the API
            // For now we show preview data structure
        }
        return result
    }
    
    var filteredPrograms: [MissionProgram] {
        if searchText.isEmpty { return programs }
        return programs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    // Blocked tasks alert
                    blockedTasksBanner
                    
                    // Programs with drag reorder
                    programList
                }
                .padding()
            }
            .navigationTitle("Mission Control")
            .searchable(text: $searchText, prompt: "Search programs…")
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
            // Context chat FAB — floating button to talk to Centurion
            .overlay(alignment: .bottomTrailing) {
                contextChatButton
            }
        }
    }
    
    // MARK: - Blocked Tasks Banner
    
    private var blockedTasksBanner: some View {
        Group {
            if !programs.isEmpty {
                // Preview blocked tasks from sample data
                VStack(spacing: Spacing.xs) {
                    blockedTaskRow(program: programs[0], taskTitle: "Draft messaging framework",
                                   reason: "Awaiting stakeholder feedback on brand guidelines")
                    blockedTaskRow(program: programs[0], taskTitle: "Design visual assets",
                                   reason: "Dependent on messaging framework completion")
                }
                .opacity(isAppeared ? 1 : 0)
                .offset(y: isAppeared ? 0 : 8)
            }
        }
    }
    
    private func blockedTaskRow(program: MissionProgram, taskTitle: String, reason: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("\(taskTitle)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText())
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(program.name)
                .font(.caption2)
                .foregroundColor(ColorTheme.accent())
        }
        .padding(Spacing.sm)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - Program List with Drag Reorder
    
    private var programList: some View {
        VStack(spacing: Spacing.md) {
            ForEach(filteredPrograms) { program in
                ProgramCard(program: program)
                    .overlay(alignment: .topTrailing) {
                        // Drag handle
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
                    .gesture(
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
                            .onEnded { value in
                                guard let dragged = draggedProgram else { return }
                                
                                // Calculate new position
                                let dropIndex = indexFor(y: dragOffset.height, draggedId: dragged.id)
                                
                                withAnimation(Motion.heavy) {
                                    if let fromIndex = programs.firstIndex(where: { $0.id == dragged.id }),
                                       let toIndex = dropIndex {
                                        programs.move(fromOffsets: IndexSet(integer: fromIndex),
                                                      toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                        // Update orders
                                        for (i, _) in programs.enumerated() {
                                            programs[i].order = i
                                        }
                                    }
                                    dragOffset = .zero
                                    draggedProgram = nil
                                }
                                Haptics.success()
                            }
                    )
                    .opacity(draggedProgram?.id == program.id ? 0.9 : 1.0)
                    .opacity(isAppeared ? 1 : 0)
                    .offset(y: isAppeared ? 0 : CGFloat(program.order * 8))
                    .animation(Motion.appear.delay(Double(program.order) * 0.08).delay(0.15), value: isAppeared)
            }
        }
    }
    
    /// Find the index to drop at based on vertical drag offset
    private func indexFor(y offset: CGFloat, draggedId: UUID) -> Int? {
        let cardHeight: CGFloat = 160 // approximate card height
        let moveCount = Int(offset / cardHeight)
        guard let currentIndex = programs.firstIndex(where: { $0.id == draggedId }) else { return nil }
        let newIndex = currentIndex + moveCount
        return max(0, min(newIndex, programs.count - 1))
    }
    
    // MARK: - Context Chat FAB
    
    private var contextChatButton: some View {
        Button(action: {
            Haptics.mediumTap()
            // Present context chat sheet (future enhancement)
        }) {
            Image(systemName: "message.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(ColorTheme.accent())
                .clipShape(Circle())
                .shadow(color: ColorTheme.accent().opacity(0.3), radius: 8, y: 4)
        }
        .padding(.trailing, Spacing.md)
        .padding(.bottom, 70) // Above tab bar
        .opacity(isAppeared ? 1 : 0)
    }
}

// MARK: - Program Card

struct ProgramCard: View {
    let program: MissionProgram
    
    var body: some View {
        NavigationLink(destination: ProjectDetailView(program: program)) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Program header with progress
                HStack(spacing: Spacing.sm) {
                    Image(systemName: program.status.icon)
                        .font(.title2)
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
                    
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(ColorTheme.border(), lineWidth: 3)
                            .frame(width: 36, height: 36)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(ColorTheme.accent(), lineWidth: 3)
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ColorTheme.accent())
                    }
                }
                
                // Stats row
                HStack(spacing: Spacing.md) {
                    Label("\(program.targetCount) targets", systemImage: "target")
                    Label("\(program.completedTaskCount)/\(program.taskCount) tasks", systemImage: "checklist")
                }
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            }
            .padding()
            .cardStyle()
            .overlay(alignment: .bottom) {
                // Bottom accent line
                Rectangle()
                    .fill(ColorTheme.accent().opacity(program.status == .active ? 0.3 : 0.05))
                    .frame(height: 3)
                    .padding(.horizontal)
                    .padding(.bottom, -1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var progress: Double {
        guard program.taskCount > 0 else { return 0 }
        return Double(program.completedTaskCount) / Double(program.taskCount)
    }
}

// MARK: - Stat Item (reused)

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.primaryText())
            Text(label)
                .font(.caption2)
                .foregroundColor(ColorTheme.mutedText())
        }
        .frame(maxWidth: .infinity)
    }
}
