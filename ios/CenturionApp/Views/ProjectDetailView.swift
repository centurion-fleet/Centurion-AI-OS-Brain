import SwiftUI

/// Mission Control project detail — targets and tasks
/// Premium card-based design with amber accents.
struct ProjectDetailView: View {
    let project: MissionProject
    @State private var selectedTarget: MissionTarget?
    @State private var showTargetDetail = false
    @State private var isAppeared = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Project header
                projectHeader
                
                // Security status
                securityStatus
                
                // Targets section
                targetsSection
                
                // Recent activity
                recentActivity
            }
            .padding()
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTargetDetail) {
            if let target = selectedTarget {
                TargetDetailView(target: target)
            }
        }
        .onAppear {
            withAnimation(Motion.appear.delay(0.05)) {
                isAppeared = true
            }
        }
    }
    
    private var projectHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: project.status.icon)
                    .foregroundColor(ColorTheme.accent())
                    .opacity(project.status.iconOpacity)
                    .font(.title3)
                Text(project.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText())
            }
            
            Text(project.description)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
            
            // Progress bar
            VStack(spacing: Spacing.xxs) {
                ProgressView(value: Double(project.completedTaskCount), total: Double(max(project.taskCount, 1)))
                    .tint(ColorTheme.accent())
                Text("\(project.completedTaskCount) of \(project.taskCount) tasks complete")
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
    
    private var securityStatus: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(ColorTheme.success())
                .font(.caption)
            Text("This project is end-to-end encrypted")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(ColorTheme.primaryText())
            Spacer()
            StatusDot(isConnected: true)
        }
        .padding(Spacing.sm)
        .background(ColorTheme.success().opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Targets", icon: "target")
            
            VStack(spacing: Spacing.xs) {
                targetRow(title: "Q3 Go-to-Market", status: "Active", tasks: "3 tasks", color: ColorTheme.accent())
                targetRow(title: "Partner Onboarding", status: "Backlog", tasks: "0 tasks", color: .gray)
                targetRow(title: "Content Strategy", status: "In Review", tasks: "5 tasks", color: ColorTheme.accent().opacity(0.7))
            }
        }
        .cardStyle()
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 12)
        .animation(Motion.appear.delay(0.1), value: isAppeared)
    }
    
    private func targetRow(title: String, status: String, tasks: String, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primaryText())
                Text("\(status) • \(tasks)")
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
    }
    
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Recent Activity", icon: "clock.arrow.circlepath")
            
            activityRow("Task completed: Research market positioning", time: "2h ago")
            activityRow("Target status changed: Q3 GTM → Active", time: "1d ago")
            activityRow("New target created: Content Strategy", time: "2d ago")
            
            Text("All activity logs are encrypted end-to-end")
                .font(.caption2)
                .foregroundColor(ColorTheme.mutedText())
                .padding(.top, Spacing.xxs)
        }
        .cardStyle()
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 16)
        .animation(Motion.appear.delay(0.2), value: isAppeared)
    }
    
    private func activityRow(_ text: String, time: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Circle()
                .fill(ColorTheme.accent())
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.caption)
                    .foregroundColor(ColorTheme.primaryText())
                Text(time)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
    }
}

/// Target detail sheet
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
                                .foregroundColor(task.status == .done ? ColorTheme.success() : ColorTheme.mutedText())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText())
                                Text(task.status.rawValue)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
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
