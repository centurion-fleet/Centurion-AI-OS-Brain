import SwiftUI

/// Mission Control — the Life Mission Dashboard.
/// 
/// This is not a project management tool. It is the cockpit where the human
/// aligns with their Centurion on what actually advances their life mission.
/// 
/// Principles from the Target Series:
/// - The vital statistic is the only number that matters
/// - Targets must be few, clear, and measurable
/// - The Centurion's thoughts live here, not in a separate chat
/// - The human steers, the Centurion executes and alerts
struct MissionPortfolioView: View {
    @State private var mission: LifeMission = LifeMission.preview()
    @State private var programs: [MissionProgram] = MissionProgram.preview()
    @State private var thoughts: [CenturionThought] = CenturionThought.preview()
    @State private var focusActions: [FocusAction] = FocusAction.preview()
    @State private var searchText = ""
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isAppeared = false
    
    /// Drag reorder
    @State private var draggedProgram: MissionProgram?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    // 1. Mission Statement — the highest level
                    missionHeader
                    
                    // 2. Vital Statistic — the one number
                    vitalStatCard
                    
                    // 3. Centurion Pulse — thoughts live here
                    centurionPulse
                    
                    // 4. Alerts — blocked items, risks
                    alertsSection
                    
                    // 5. Focus Actions — what the human does today
                    focusActionsSection
                    
                    // 6. Current Targets — the programs
                    targetsSection
                }
                .padding()
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
    }
    
    // MARK: - Mission Header
    
    private var missionHeader: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "target")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ColorTheme.accent())
            
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
            // Ring
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
    
    // MARK: - Centurion Pulse
    
    private var centurionPulse: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Centurion Pulse")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
                Text("Live")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ColorTheme.accent().opacity(0.1))
                    .clipShape(Capsule())
            }
            
            ForEach(thoughts) { thought in
                thoughtRow(thought)
            }
        }
        .padding()
        .cardStyle()
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 16)
    }
    
    private func thoughtRow(_ thought: CenturionThought) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: thought.type.icon)
                .font(.caption)
                .foregroundColor(thoughtTypeColor(thought.type))
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(thought.text)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.primaryText())
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 8) {
                    Text(thought.type.rawValue)
                        .font(.caption2)
                        .foregroundColor(thoughtTypeColor(thought.type))
                    if let target = thought.relatedTarget {
                        Text(target)
                            .font(.caption2)
                            .foregroundColor(ColorTheme.accent())
                    }
                    Text(thought.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func thoughtTypeColor(_ type: CenturionThought.ThoughtType) -> Color {
        switch type {
        case .alert: return .orange
        case .insight: return ColorTheme.accent()
        case .progress: return ColorTheme.success()
        case .suggestion: return ColorTheme.accent()
        case .question: return ColorTheme.accent().opacity(0.7)
        }
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
    
    // MARK: - Targets (Programs)
    
    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Current Targets", icon: "target")
            
            VStack(spacing: Spacing.sm) {
                ForEach(programs) { program in
                    ProgramCard(program: program)
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
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(program.completedTaskCount)/\(program.taskCount)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(ColorTheme.accent())
                    Text("tasks")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .padding()
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}
