import SwiftUI

/// Join or invite another Centurion owner for multi-brain collaboration.
struct SwarmConnectSheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var swarmStore: SwarmStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .join
    @State private var token = ""
    @State private var installId = ""
    @State private var projectId = ""
    @State private var friendCustomerId = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    enum Mode: String, CaseIterable {
        case join = "Join"
        case invite = "Invite"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Connect Centurions",
                        subtitle: "Invite another owner, or join a shared collaboration with Mission Control credentials."
                    )

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if mode == .join {
                        joinForm
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

                    Button(mode == .join ? "Connect this Centurion" : "Send invite") {
                        Task { await submit() }
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .disabled(isBusy || connectionManager.connectionState != .connected)

                    if connectionManager.connectionState != .connected {
                        Text("Link your Centurion in You first.")
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

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("From the invite or Mission Control setup, paste:")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            field("Project token (ctk_proj_…)", text: $token)
            field("Install id", text: $installId)
            field("Project id", text: $projectId)
        }
    }

    private var inviteForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your Centurion must already be connected to Mission Control. Enter your friend’s customer id.")
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
            if mode == .join {
                let message = try await connectionManager.connectSwarm(
                    token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                    installId: installId.trimmingCharacters(in: .whitespacesAndNewlines),
                    projectId: projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                statusMessage = message
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
}
