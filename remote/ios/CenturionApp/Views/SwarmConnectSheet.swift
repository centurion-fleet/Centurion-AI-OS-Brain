import SwiftUI

/// Join, invite, or start a collaboration — LAN-first; portal credentials behind Advanced.
struct SwarmConnectSheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var missionStore: MissionStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .start
    @State private var collaborationName = ""
    @State private var objective = ""
    @State private var showAdvancedPortal = false
    @State private var token = ""
    @State private var installId = ""
    @State private var projectId = ""
    @State private var friendCustomerId = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    enum Mode: String, CaseIterable {
        case start = "Start"
        case invite = "Invite"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Connect Sovereigns",
                        subtitle: "Start a collaboration on this Sovereign, or invite another owner. Collaborations serve your Life Mission."
                    )

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if mode == .start {
                        startForm
                    } else {
                        inviteForm
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

                    Button(mode == .start ? "Start on this Sovereign" : "Send invite") {
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
        }
    }

    private var startForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Creates a collaboration on your linked Sovereign — private to your network.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Name", text: $collaborationName)
            field("What it's for (optional)", text: $objective)

            if !missionStore.mission.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Grounded in your Life Mission")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.mutedText())
                Text(missionStore.mission.statement)
                    .font(.caption)
                    .foregroundColor(ColorTheme.primaryText())
                    .lineLimit(3)
            }

            DisclosureGroup("Advanced — join via Mission Control", isExpanded: $showAdvancedPortal) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Only if you received share credentials from another owner.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                    field("Project token", text: $token)
                    field("Install id", text: $installId)
                    field("Project id", text: $projectId)
                    Button("Join with credentials") {
                        Task { await submitPortalJoin() }
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                    .disabled(isBusy || !connectionManager.isCryptoChatReady)
                }
                .padding(.top, Spacing.xs)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(ColorTheme.mutedText())
        }
    }

    private var inviteForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Invite another owner after this Sovereign is linked to a shared collaboration.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Friend customer id", text: $friendCustomerId)
            field("Project id (optional)", text: $projectId)
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

    private func submit() async {
        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            if mode == .start {
                let name = collaborationName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    errorMessage = "Give this collaboration a name."
                    return
                }
                let payload = try await connectionManager.createSwarmBoard(
                    name: name,
                    objective: objective.trimmingCharacters(in: .whitespacesAndNewlines),
                    missionId: missionStore.mission.id.uuidString
                )
                statusMessage = payload["message"] as? String
                    ?? "Collaboration started on this Sovereign."
                await swarmStore.refresh(from: connectionManager)
                Haptics.success()
            } else {
                let message = try await connectionManager.inviteSwarmFriend(
                    customerId: friendCustomerId.trimmingCharacters(in: .whitespacesAndNewlines),
                    projectId: projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                statusMessage = message
                Haptics.success()
            }
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func submitPortalJoin() async {
        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let message = try await connectionManager.connectSwarm(
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                installId: installId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = message
            await swarmStore.refresh(from: connectionManager)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
