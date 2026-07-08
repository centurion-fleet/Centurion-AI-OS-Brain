import SwiftUI

/// Mission Control portfolio — premium project overview with amber accents
struct MissionPortfolioView: View {
    @State private var projects: [MissionProject] = MissionProject.preview()
    @State private var searchText = ""
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var isAppeared = false
    
    var filteredProjects: [MissionProject] {
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    // Security banner
                    securityBanner
                        .opacity(isAppeared ? 1 : 0)
                        .offset(y: isAppeared ? 0 : 10)
                    
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
    
    private var securityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundColor(ColorTheme.accent())
            VStack(alignment: .leading, spacing: 2) {
                Text("End-to-end encrypted")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText())
                Text("All project data encrypted before transmission")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
            }
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(ColorTheme.accent())
                .font(.caption)
        }
        .padding(12)
        .background(ColorTheme.accent().opacity(0.08))
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
                        .foregroundColor(ColorTheme.accent())
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            
            Text(project.description)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .lineLimit(2)
            
            HStack(spacing: 16) {
                Label("\(project.targetCount) targets", systemImage: "target")
                Label("\(project.completedTaskCount)/\(project.taskCount) tasks", systemImage: "checklist")
            }
            .font(.caption)
            .foregroundColor(ColorTheme.mutedText())
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorTheme.border())
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .cardStyle()
    }
    
    private var progress: Double {
        guard project.taskCount > 0 else { return 0 }
        return Double(project.completedTaskCount) / Double(project.taskCount)
    }
    
    private var progressColor: Color {
        progress > 0.7 ? ColorTheme.accent() : progress > 0.3 ? ColorTheme.accent().opacity(0.7) : ColorTheme.mutedText()
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
