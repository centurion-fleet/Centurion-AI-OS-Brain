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
                // Identity section
                Section("Identity") {
                    HStack {
                        Label("Device Name", systemImage: "iphone")
                        Spacer()
                        Text(UIDevice.current.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Public Key", systemImage: "key.fill")
                        Spacer()
                        Button("Show") { showKeyExport = true }
                            .font(.caption)
                    }
                }
                
                // Connection section
                Section("Connection") {
                    HStack {
                        Label("Transport", systemImage: "network")
                        Spacer()
                        Text(connectionManager.connectedDevice?.connectionMethod.rawValue.uppercased()
                             ?? "—")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Encryption", systemImage: "lock.shield.fill")
                        Spacer()
                        Text("X25519 + XSalsa20-Poly1305")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if connectionManager.connectionState == .connected {
                        Button(role: .destructive) {
                            connectionManager.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "power")
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
                        Spacer()
                        Text("0.1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Protocol", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text("Centurion Secure Channel v1")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
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
                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                
                Text("Centurion Identity Key")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Share this public key with your Centurion to establish a secure connection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // In production: display the actual public key
                Text("Not yet connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
