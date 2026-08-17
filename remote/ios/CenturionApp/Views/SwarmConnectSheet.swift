import SwiftUI

/// Form a local swarm, create an empty board, or join/invite via Mission Control.
struct SwarmConnectSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case form = "Form"
        case board = "Empty board"
        case join = "Join"
        case invite = "Invite"

        var id: String { rawValue }
    }

    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var missionStore: MissionStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .form
    @State private var collaborationName = ""
    @State private var goal = ""
    @State private var worker1Profile = "default"
    @State private var worker2Profile = "default"
    @State private var verifierProfile = "default"
    @State private var synthesizerProfile = "default"
    @State private var worker1Title = "Research"
    @State private var worker2Title = "Draft"
    @State private var profiles: [String] = ["default"]
    @State private var joinToken = ""
    @State private var joinProjectId = ""
    @State private var joinInstallId = ""
    @State private var inviteCustomerId = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Collaborations",
                        subtitle: "Form a swarm on this Sovereign, or join/invite another owner through Mission Control."
                    )

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .form:
                        formFields
                    case .board:
                        emptyBoardFields
                    case .join:
                        joinFields
                    case .invite:
                        inviteFields
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(ColorTheme.error())
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(ColorTheme.success())
                    }

                    Button(primaryTitle) {
                        Task { await submit() }
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .disabled(isBusy || !connectionManager.isCryptoChatReady)

                    if !connectionManager.isCryptoChatReady {
                        Text("Link your Sovereign in You first.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .padding()
            }
            .background(ColorTheme.background())
            .navigationTitle("Collaborations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
            .task { await loadProfiles() }
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .form: return "Form swarm"
        case .board: return "Create empty board"
        case .join: return "Join collaboration"
        case .invite: return "Send invite"
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Creates a live Kanban swarm on this Brain: two workers, a verifier, then a synthesizer. Gateway must be running.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Name (optional)", text: $collaborationName)
            field("Goal", text: $goal)
            field("Worker 1 title", text: $worker1Title)
            profilePicker("Worker 1 profile", selection: $worker1Profile)
            field("Worker 2 title", text: $worker2Title)
            profilePicker("Worker 2 profile", selection: $worker2Profile)
            profilePicker("Verifier", selection: $verifierProfile)
            profilePicker("Synthesizer", selection: $synthesizerProfile)
            if profiles.filter({ $0 != "default" }).isEmpty {
                Text("Create worker profiles on the desk with `centurion -p researcher setup` so dispatch can spawn real workers.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            missionGrounding
        }
    }

    private var emptyBoardFields: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Empty board only — no workers until you Form a swarm.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Name", text: $collaborationName)
            field("What it's for (optional)", text: $goal)
            missionGrounding
        }
    }

    private var joinFields: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Paste the Mission Control project token from the invite. This Brain probes the portal before saving.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Project token (ctk_proj_…)", text: $joinToken)
            field("Project id", text: $joinProjectId)
            field("Install id", text: $joinInstallId)
        }
    }

    private var inviteFields: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Invite another owner onto the connected Mission Control project. They join from their Remote or Brain.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Their customer id", text: $inviteCustomerId)
        }
    }

    @ViewBuilder
    private var missionGrounding: some View {
        if !missionStore.mission.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Grounded in your Life Mission")
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.mutedText())
            Text(missionStore.mission.statement)
                .font(.caption)
                .foregroundColor(ColorTheme.primaryText())
                .lineLimit(3)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.mutedText())
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(Spacing.sm)
                .background(ColorTheme.surface())
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func profilePicker(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.mutedText())
            Picker(title, selection: selection) {
                ForEach(profiles, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .tint(ColorTheme.accent())
        }
    }

    private func loadProfiles() async {
        guard connectionManager.isCryptoChatReady else { return }
        do {
            let rows = try await connectionManager.listProfiles()
            let names = rows.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
            if !names.isEmpty {
                profiles = names.contains("default") ? names : (["default"] + names)
                if !profiles.contains(worker1Profile) { worker1Profile = profiles[0] }
                if !profiles.contains(worker2Profile) {
                    worker2Profile = profiles.count > 1 ? profiles[1] : profiles[0]
                }
                if !profiles.contains(verifierProfile) { verifierProfile = profiles[0] }
                if !profiles.contains(synthesizerProfile) { synthesizerProfile = profiles[0] }
            }
        } catch {
            // Keep default so Form still submits; desk will reject missing profiles.
        }
    }

    private func submit() async {
        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            switch mode {
            case .form:
                try await submitForm()
            case .board:
                try await submitEmptyBoard()
            case .join:
                try await submitJoin()
            case .invite:
                try await submitInvite()
            }
            await swarmStore.refresh(from: connectionManager)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func submitForm() async throws {
        let goalText = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goalText.isEmpty else {
            throw ConnectionError.serverRejected("Describe what the collaboration should achieve.")
        }
        let payload = try await connectionManager.createLocalSwarm(
            goal: goalText,
            workers: [
                [
                    "profile": worker1Profile,
                    "title": worker1Title.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("Research"),
                    "body": worker1Title,
                ],
                [
                    "profile": worker2Profile,
                    "title": worker2Title.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("Draft"),
                    "body": worker2Title,
                ],
            ],
            verifier: verifierProfile,
            synthesizer: synthesizerProfile,
            name: collaborationName.trimmingCharacters(in: .whitespacesAndNewlines),
            missionId: missionStore.mission.id.uuidString
        )
        statusMessage = payload["message"] as? String ?? "Swarm formed on this Sovereign."
    }

    private func submitEmptyBoard() async throws {
        let name = collaborationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ConnectionError.serverRejected("Give this collaboration a name.")
        }
        let payload = try await connectionManager.createSwarmBoard(
            name: name,
            objective: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            missionId: missionStore.mission.id.uuidString
        )
        statusMessage = payload["message"] as? String
            ?? "Empty board created on this Sovereign."
    }

    private func submitJoin() async throws {
        let token = joinToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectId = joinProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let installId = joinInstallId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("ctk_proj_") else {
            throw ConnectionError.serverRejected("Paste a ctk_proj_… token.")
        }
        statusMessage = try await connectionManager.connectSwarm(
            token: token,
            installId: installId,
            projectId: projectId
        )
    }

    private func submitInvite() async throws {
        let customerId = inviteCustomerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customerId.isEmpty else {
            throw ConnectionError.serverRejected("Enter their Mission Control customer id.")
        }
        statusMessage = try await connectionManager.inviteSwarmFriend(customerId: customerId)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
