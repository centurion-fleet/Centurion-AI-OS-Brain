import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var adrianService: AdrianService
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var showKeyExport = false
    @State private var showResetConfirmation = false
    @State private var showGetHelp = false
    @State private var showAdrian = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0.0"
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { appearanceMode = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    HStack {
                        Label("Device Name", systemImage: "iphone")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Text(UIDevice.current.name)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    HStack {
                        Label("Security Code", systemImage: "key.fill")
                            .foregroundColor(ColorTheme.primaryText())
                        Spacer()
                        Button("Show") { showKeyExport = true }
                            .font(.caption)
                            .foregroundColor(ColorTheme.accent())
                    }
                }

                Section("You") {
                    NavigationLink(destination: MissionView()) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(ColorTheme.accent())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Your Mission")
                                    .foregroundColor(ColorTheme.primaryText())
                                Text(missionStore.hasMissionStatement
                                     ? missionStore.mission.statement
                                     : "Your life purpose and commitments")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                                    .lineLimit(1)
                            }
                        }
                    }

                    NavigationLink(destination: SoulDocumentView()) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(ColorTheme.accent())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Your Centurion's Soul")
                                    .foregroundColor(ColorTheme.primaryText())
                                Text(missionStore.hasSoulConfiguration
                                     ? "Personality and rules configured"
                                     : "Personality and rules for your AI")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                        }
                    }
                }

                Section("Connection") {
                    HStack {
                        Label("Device link", systemImage: "app.connected.to.app.below.fill")
                        Spacer()
                        Text(connectionManager.connectionState == .connected ? "Linked" : "Not linked")
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    if connectionManager.connectionState == .connected {
                        Button(role: .destructive) {
                            connectionManager.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "power")
                        }
                    }
                }

                Section {
                    HStack {
                        Label("Thinking service", systemImage: "brain.head.profile")
                        Spacer()
                        Text(connectionManager.llmHealth.label)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    if let status = connectionManager.thinkingStatus,
                       status.lastGoodAvailable,
                       connectionManager.llmHealth.needsAttention {
                        Text("Last working setup is available.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    Text("Change on your computer")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                } header: {
                    Text("How Your Centurion Thinks")
                }
                .task(id: connectionManager.connectionState) {
                    guard connectionManager.connectionState == .connected else { return }
                    await connectionManager.refreshThinkingStatus()
                }

                Section {
                    Button {
                        showGetHelp = true
                    } label: {
                        Label("Get Help", systemImage: "lifepreserver")
                    }
                    .accessibilityLabel("Get Help")
                    .accessibilityHint("Create a support code or try automatic recovery")

                    Button {
                        showAdrian = true
                    } label: {
                        Label("Talk to Adrian", systemImage: "person.crop.circle.fill")
                    }
                    .accessibilityLabel("Talk to Adrian")
                    .accessibilityHint("Open Centurion's cloud support guide")
                } header: {
                    Text("Support")
                } footer: {
                    Text("Adrian works over the internet — even when your Centurion isn't linked.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ColorTheme.accent())
                }

                Section("Privacy") {
                    privacyRow("Private on your network",
                               "Messages stay between your iPhone and Centurion")
                    privacyRow("Encrypted in transit",
                               "Protected the same way sensitive apps protect your data")
                    privacyRow("No cloud account",
                               "You don't need to sign in to a third-party service")
                }

                Section("About") {
                    HStack {
                        Spacer()
                        VStack(spacing: Spacing.sm) {
                            CenturionAppMark(size: 64)
                            Text("CenturionAI Remote")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(ColorTheme.primaryText())
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    HStack {
                        Label("Release", systemImage: "sparkle")
                        Spacer()
                        Text("Mission Horizon")
                            .font(.caption)
                            .foregroundColor(ColorTheme.accent())
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset Identity", systemImage: "trash")
                    }
                } footer: {
                    Text("This will get a new pairing code. You'll need to link again in Connect.")
                }
            }
            .background(ColorTheme.background())
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .alert("Reset Identity?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    connectionManager.disconnect()
                    try? IdentityKey.reset()
                }
            } message: {
                Text("Your iPhone will get a new security identity. Approve it again on your Centurion before reconnecting.")
            }
            .sheet(isPresented: $showKeyExport) {
                KeyExportView()
            }
            .sheet(isPresented: $showGetHelp) {
                GetHelpView()
                    .environmentObject(connectionManager)
            }
            .sheet(isPresented: $showAdrian) {
                AdrianView { action in
                    AdrianNavigation.handleAction(
                        action,
                        showAdrian: $showAdrian,
                        showGetHelp: $showGetHelp,
                        connectionManager: connectionManager
                    )
                }
                .environmentObject(adrianService)
                .environmentObject(connectionManager)
                .environmentObject(missionStore)
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
    @State private var fingerprint = ""
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundColor(ColorTheme.accent())

                Text("Your iPhone Security Code")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText())

                Text("Approve this code on your Centurion → Devices when pairing for the first time.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)

                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundColor(ColorTheme.error())
                } else {
                    Text(fingerprint)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(ColorTheme.primaryText())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(ColorTheme.surface())
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ColorTheme.border(), lineWidth: 0.5)
                        )
                }

                if !fingerprint.isEmpty {
                    Button("Copy Code") {
                        UIPasteboard.general.string = fingerprint
                        Haptics.success()
                    }
                    .buttonStyle(AmberButtonStyle())
                }

                Spacer()
            }
            .padding()
            .onAppear(perform: loadFingerprint)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
    }

    private func loadFingerprint() {
        do {
            let identity = try IdentityKey.loadOrCreate()
            fingerprint = identity.fingerprint
        } catch {
            loadError = "Your secure identity couldn't be loaded."
        }
    }
}
