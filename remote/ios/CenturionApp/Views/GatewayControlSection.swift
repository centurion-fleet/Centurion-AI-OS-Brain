import SwiftUI

/// You-tab controls for the messaging gateway on the linked Sovereign.
struct GatewayControlSection: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var status: [String: Any] = [:]
    @State private var platforms: [[String: Any]] = []
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var running: Bool {
        (status["running"] as? Bool) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Messaging gateway", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Text(running ? "Running" : "Stopped")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(running ? ColorTheme.accent() : ColorTheme.mutedText())
            }

            Text("Start or stop the messaging bridge on your Sovereign from away. Platform toggles take effect after a restart.")
                .font(.footnote)
                .foregroundColor(ColorTheme.mutedText())

            HStack(spacing: Spacing.sm) {
                Button("Refresh") { Task { await refresh() } }
                    .disabled(busy || !connectionManager.isCryptoChatReady)
                Button(running ? "Stop" : "Start") {
                    Task { await toggleRunning() }
                }
                .disabled(busy || !connectionManager.isCryptoChatReady)
                Button("Restart") {
                    Task { await restart() }
                }
                .disabled(busy || !connectionManager.isCryptoChatReady)
            }
            .buttonStyle(.bordered)

            if !connectionManager.isCryptoChatReady {
                Text("Link your Sovereign away-from-home to manage the gateway.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }

            ForEach(Array(platforms.enumerated()), id: \.offset) { _, platform in
                let name = (platform["name"] as? String) ?? "platform"
                let enabled = (platform["enabled"] as? Bool) ?? false
                let label = (platform["label"] as? String) ?? name
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        Task { await setPlatform(name, enabled: newValue) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                        Text((platform["status"] as? String) ?? "")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .disabled(busy || !connectionManager.isCryptoChatReady)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(ColorTheme.error())
            }
            if let infoMessage {
                Text(infoMessage)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: connectionManager.connectionState) {
            guard connectionManager.isCryptoChatReady else { return }
            await refresh()
        }
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            let snapshot = try await connectionManager.refreshGatewayStatus()
            status = snapshot
            platforms = (snapshot["platforms"] as? [[String: Any]]) ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRunning() async {
        busy = true
        defer { busy = false }
        do {
            if running {
                _ = try await connectionManager.gatewayStop()
                infoMessage = "Gateway stop requested."
            } else {
                _ = try await connectionManager.gatewayStart()
                infoMessage = "Gateway start requested."
            }
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restart() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await connectionManager.gatewayRestart()
            infoMessage = "Gateway restart requested."
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setPlatform(_ name: String, enabled: Bool) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await connectionManager.gatewayPlatformSet(platform: name, enabled: enabled)
            infoMessage = "\(name) \(enabled ? "enabled" : "disabled")."
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
