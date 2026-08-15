import SwiftUI

/// Mission Stack — Primary / Supporting / Dreams from Brain life.db.
struct MissionStackView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedMission: FullMission?
    @State private var chatTarget: ChatSheetTarget?
    @State private var statusMessage: String?

    var body: some View {
        List {
            if let primary = missionStore.stack.primary {
                Section("Primary Mission") {
                    Button {
                        selectedMission = primary
                    } label: {
                        missionRow(primary, badge: "Primary")
                    }
                }
            }

            if !missionStore.stack.supporting.isEmpty {
                Section("Supporting Missions") {
                    ForEach(missionStore.stack.supporting) { mission in
                        Button {
                            selectedMission = mission
                        } label: {
                            missionRow(mission, badge: nil)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Make Primary") {
                                Task {
                                    statusMessage = await missionStore.setPrimaryMission(
                                        mission.id,
                                        connectionManager: connectionManager
                                    )
                                }
                            }
                            .tint(ColorTheme.warning())
                        }
                    }
                }
            }

            if !missionStore.stack.dreams.isEmpty {
                Section("Dreams") {
                    ForEach(missionStore.stack.dreams) { dream in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dream.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(ColorTheme.primaryText())
                            if !dream.description.isEmpty {
                                Text(dream.description)
                                    .font(.caption)
                                    .foregroundStyle(ColorTheme.mutedText())
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Promote") {
                                Task {
                                    statusMessage = await missionStore.promoteDream(
                                        dream.id,
                                        connectionManager: connectionManager
                                    )
                                }
                            }
                            .tint(ColorTheme.accent())
                        }
                    }
                }
            }

            if !missionStore.subjects.isEmpty {
                Section("Subjects") {
                    ForEach(missionStore.subjects) { subject in
                        Label(subject.name, systemImage: subject.icon)
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(ColorTheme.mutedText())
                }
            }
        }
        .navigationTitle("Mission Stack")
        .task {
            await missionStore.refreshLifeStack(from: connectionManager)
        }
        .refreshable {
            await missionStore.refreshLifeStack(from: connectionManager)
        }
        .sheet(item: $selectedMission) { mission in
            NavigationStack {
                MissionDetailView(mission: mission, chatTarget: $chatTarget)
                    .environmentObject(missionStore)
                    .environmentObject(connectionManager)
            }
        }
        .sheet(item: $chatTarget) { target in
            let conversation = messageService.findOrCreateConversation(for: target.context)
            NavigationStack {
                ChatView(conversation: conversation, usesPageChrome: false)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { chatTarget = nil }
                        }
                    }
            }
            .presentationDetents([.height(380), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func missionRow(_ mission: FullMission, badge: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mission.title.isEmpty ? mission.statement : mission.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ColorTheme.primaryText())
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ColorTheme.accent().opacity(0.2)))
                }
            }
            Text(mission.phase.label)
                .font(.caption)
                .foregroundStyle(ColorTheme.mutedText())
            if let focus = mission.focusTarget {
                Text("Focus · \(focus.title)")
                    .font(.caption)
                    .foregroundStyle(ColorTheme.mutedText())
            }
            ProgressView(
                value: Double(mission.completedTargetCount),
                total: Double(max(mission.targetCount, 1))
            )
        }
        .padding(.vertical, 4)
    }
}

struct MissionDetailView: View {
    let mission: FullMission
    @Binding var chatTarget: ChatSheetTarget?
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Where I’m At") {
                Text(mission.situation.isEmpty ? "No situation set yet." : mission.situation)
            }
            Section("Why") {
                Text(mission.why.isEmpty ? "No why yet." : mission.why)
            }
            Section("Success Looks Like") {
                Text(mission.purpose.isEmpty ? mission.statement : mission.purpose)
            }

            targetSection("Must Do", mission.mustDo)
            targetSection("Should Do", mission.shouldDo)
            targetSection("Nice to Do", mission.niceToDo)

            if !missionStore.thoughts.isEmpty {
                Section("Recent Thoughts") {
                    ForEach(missionStore.thoughts.prefix(8)) { thought in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thought.summary)
                            Text(thought.activityType)
                                .font(.caption2)
                                .foregroundStyle(ColorTheme.mutedText())
                        }
                    }
                }
            }

            if !missionStore.decisions.isEmpty {
                Section("Decisions") {
                    ForEach(missionStore.decisions.prefix(8)) { decision in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(decision.title)
                            if !decision.chosen.isEmpty {
                                Text("Chose: \(decision.chosen)")
                                    .font(.caption)
                                    .foregroundStyle(ColorTheme.mutedText())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(mission.title.isEmpty ? "Mission" : mission.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Discuss") {
                    let subject = missionStore.subjects.first { $0.id == mission.subjectId }?.name
                    chatTarget = ChatSheetTarget(
                        context: .mission(
                            id: mission.id,
                            name: mission.title.isEmpty ? mission.statement : mission.title,
                            subjectName: subject
                        )
                    )
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func targetSection(_ title: String, _ targets: [MissionTargetDetail]) -> some View {
        if !targets.isEmpty {
            Section(title) {
                ForEach(targets) { target in
                    Button {
                        let subject = missionStore.subjects.first { $0.id == mission.subjectId }?.name
                        chatTarget = ChatSheetTarget(
                            context: .missionTarget(
                                id: target.id,
                                name: target.title,
                                missionId: mission.id,
                                missionName: mission.title.isEmpty ? mission.statement : mission.title,
                                subjectName: subject
                            )
                        )
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: target.focusTarget ? "scope" : statusIcon(target.status))
                                .foregroundStyle(target.focusTarget ? ColorTheme.accent() : ColorTheme.mutedText())
                            VStack(alignment: .leading) {
                                Text("\(target.sequenceNumber). \(target.title)")
                                if !target.description.isEmpty {
                                    Text(target.description)
                                        .font(.caption)
                                        .foregroundStyle(ColorTheme.mutedText())
                                }
                            }
                            Spacer()
                            Image(systemName: "bubble.left")
                                .font(.caption)
                                .foregroundStyle(ColorTheme.mutedText().opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statusIcon(_ status: TargetStatus) -> String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .inProgress: return "circle.lefthalf.filled"
        case .blocked: return "exclamationmark.triangle"
        case .notStarted: return "circle"
        }
    }
}
