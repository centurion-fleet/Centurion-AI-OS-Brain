import SwiftUI

/// Start a local collaboration board on the linked Sovereign.
/// Portal Mission Control connect/invite (`swarm_connect` / `swarm_invite`) stays frozen — not offered here.
struct SwarmConnectSheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var missionStore: MissionStore
    @Environment(\.dismiss) private var dismiss

    @State private var collaborationName = ""
    @State private var objective = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Start a collaboration",
                        subtitle: "Creates a board on your linked Sovereign. Cross-owner portal connect and invite are not available in this build."
                    )

                    startForm

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

                    Button("Start on this Sovereign") {
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
            Text("Private to your Sovereign — local board snapshot, create, and resolve stay available.")
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
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
