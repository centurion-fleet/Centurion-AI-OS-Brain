import SwiftUI

/// Mission Control project detail — targets and tasks
struct ProjectDetailView: View {
    let project: MissionProject
    @State private var selectedTarget: MissionTarget?
    @State private var showTargetDetail = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
    }
    
    private var projectHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: project.status.icon)
                    .foregroundColor(statusColor)
                Text(project.name)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text(project.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Progress
            VStack(spacing: 4) {
                ProgressView(value: Double(project.completedTaskCount), total: Double(max(project.taskCount, 1)))
                    .tint(Color(red: 1.0, green: 0.84, blue: 0.0))
                Text("\(project.completedTaskCount) of \(project.taskCount) tasks complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var securityStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("This project is end-to-end encrypted")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Data synced via encrypted channel to your Centurion")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Targets", systemImage: "target")
                    .font(.headline)
                Spacer()
                Text("\(project.targetCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Note: In production, targets would come from the actual API
            // For now showing preview structure
            VStack(spacing: 8) {
                targetRow(title: "Q3 Go-to-Market", status: "Active", tasks: "3 tasks")
                targetRow(title: "Partner Onboarding", status: "Backlog", tasks: "0 tasks")
                targetRow(title: "Content Strategy", status: "In Review", tasks: "5 tasks")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func targetRow(title: String, status: String, tasks: String) -> some View {
        HStack {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(status) • \(tasks)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent Activity", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
            }
            
            activityRow("Task completed: Research market positioning", time: "2h ago")
            activityRow("Target status changed: Q3 GTM → Active", time: "1d ago")
            activityRow("New target created: Content Strategy", time: "2d ago")
            
            Text("All activity logs are encrypted end-to-end")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func activityRow(_ text: String, time: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(red: 1.0, green: 0.84, blue: 0.0))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.caption)
                Text(time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active": return .green
        case "backlog": return .gray
        case "in review": return .blue
        default: return .secondary
        }
    }
    
    private var statusColor: Color {
        switch project.status {
        case .active: return .green
        case .onHold: return .orange
        case .completed: return .blue
        case .archived: return .gray
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
                                .foregroundColor(task.status == .done ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.subheadline)
                                Text(task.status.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    Text("All targets and tasks are end-to-end encrypted")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
