import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var showKeyExport = false
    @State private var showResetConfirmation = false

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { appearanceMode = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // Mission Horizon branding
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "app.connected.to.app.below.fill")
                                .font(.system(size: 32))
                                .foregroundColor(ColorTheme.accent())

                            Text("CENTURIONAI REMOTE")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(ColorTheme.accent())
                                .tracking(4)

                            Text("MISSION HORIZON  ·  v3.0.0")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(ColorTheme.dimAccent())
                                .tracking(3)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                // Identity section
                Section("Identity") {
                    HStack {
                        Label("Device Name", systemImage: "iphone")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text(UIDevice.current.name)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    HStack {
                        Label("Public Key", systemImage: "key.fill")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Button("Show") { showKeyExport = true }
                            .font(.caption)
                            .foregroundColor(ColorTheme.accent())
                    }
                }

                // Remote Control section
                Section("Remote Control") {
                    HStack {
                        Label("Transport", systemImage: "network")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text(connectionManager.connectedDevice?.connectionMethod.rawValue.uppercased()
                             ?? "—")
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    HStack {
                        Label("Encryption", systemImage: "lock.shield.fill")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text("X25519 + XSalsa20-Poly1305")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    if connectionManager.connectionState == .connected {
                        Button(role: .destructive) {
                            connectionManager.disconnect()
                        } label: {
                            Label("Disconnect Remote", systemImage: "power")
                        }
                    }
                }

                // Appearance section
                Section("Appearance") {
                    Picker("Theme", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ColorTheme.accent())
                }

                // Security section
                Section("Security") {
                    privacyRow("Messages are encrypted end-to-end",
                               "Your Centurion is the only device that can decrypt them")
                    privacyRow("No metadata in transit",
                               "Unlike Signal or Telegram, there is no routing server")
                    privacyRow("Forward secrecy",
                               "Today's keys can't decrypt yesterday's messages")
                    privacyRow("Local only",
                               "When on your home network, no internet is needed at all")
                }

                // About section
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text("3.0.0")
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    HStack {
                        Label("Release", systemImage: "sparkle")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text("Mission Horizon")
                            .font(.caption)
                            .foregroundColor(ColorTheme.accent())
                    }

                    HStack {
                        Label("Protocol", systemImage: "arrow.triangle.branch")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text("Centurion Secure Channel v1")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset Identity", systemImage: "trash")
                    }
                } footer: {
                    Text("This will generate a new encryption identity. You'll need to re-pair with your Centurion.")
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Identity?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    connectionManager.disconnect()
                }
            } message: {
                Text("Your current encryption keys will be discarded. You'll need to reconnect to your Centurion.")
            }
            .sheet(isPresented: $showKeyExport) {
                KeyExportView()
            }
        }
    }

    private func privacyRow(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(ColorTheme.primaryText())
            Text(description)
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
        }
        .padding(.vertical, 2)
    }
}

struct KeyExportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundColor(ColorTheme.accent())

                Text("Centurion Identity Key")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText())

                Text("Share this public key with your Centurion to establish a secure connection.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)

                Text("Not yet connected")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ColorTheme.border(), lineWidth: 0.5)
                    )

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
    }
}
