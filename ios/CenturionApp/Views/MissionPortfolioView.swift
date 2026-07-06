import SwiftUI

/// Mission Control portfolio — list of all your projects
struct MissionPortfolioView: View {
    @State private var projects: [MissionProject] = MissionProject.preview()
    @State private var searchText = ""
    @EnvironmentObject private var connectionManager: ConnectionManager
    
    var filteredProjects: [MissionProject] {
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Security banner
                    securityBanner
                    
                    // Stats summary
                    statsSummary
                    
                    // Project list
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProjects) { project in
                            NavigationLink(destination: ProjectDetailView(project: project)) {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Mission Control")
            .searchable(text: $searchText, prompt: "Search projects…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Only visible when connected
                    if connectionManager.connectionState == .connected {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    private var securityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("End-to-end encrypted")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("All project data encrypted before transmission")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var statsSummary: some View {
        HStack(spacing: 0) {
            StatItem(value: "\(projects.count)", label: "Projects", icon: "folder.fill")
            Divider().frame(height: 40)
            StatItem(value: "\(projects.reduce(0) { $0 + $1.targetCount })", label: "Targets", icon: "target")
            Divider().frame(height: 40)
            StatItem(value: "\(projects.reduce(0) { $0 + $1.completedTaskCount })/\(projects.reduce(0) { $0 + $1.taskCount })", label: "Tasks Done", icon: "checkmark.circle.fill")
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProjectCard: View {
    let project: MissionProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: project.status.icon)
                    .foregroundColor(statusColor)
                Text(project.name)
                    .font(.headline)
                Spacer()
                if project.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(project.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack(spacing: 16) {
                Label("\(project.targetCount) targets", systemImage: "target")
                Label("\(project.completedTaskCount)/\(project.taskCount) tasks", systemImage: "checklist")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var progress: Double {
        guard project.taskCount > 0 else { return 0 }
        return Double(project.completedTaskCount) / Double(project.taskCount)
    }
    
    private var progressColor: Color {
        progress > 0.7 ? .green : progress > 0.3 ? Color(red: 1.0, green: 0.84, blue: 0.0) : .orange
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
