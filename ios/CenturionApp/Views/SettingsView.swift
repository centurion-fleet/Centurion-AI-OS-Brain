import SwiftUI

/// You tab — sales hero, personal hub, link, thinking, mission, collaborations, privacy, support, prefs.
struct SettingsView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var adrianService: AdrianService
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var beneficiaryStore: BeneficiaryStore
    @EnvironmentObject private var oversightStore: OversightStore
    @EnvironmentObject private var memoryHorizonStore: MemoryHorizonStore
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var showKeyExport = false
    @State private var showResetConfirmation = false
    @State private var showGetHelp = false
    @State private var showAdrian = false
    @State private var showCollaborations = false
    @State private var showSwarmConnect = false
    @State private var selectedCollaboration: SwarmSummary?
    @State private var showPrivacyTrust = false
    @State private var showPairingSheet = false
    @State private var showRecoverySheet = false

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
        TabPageChrome(title: "You") {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if connectionManager.connectionState != .connected {
                        linkHeroSection
                        DeviceLinkSection(showPairingSheet: $showPairingSheet)
                        ThinkingServiceSection(showRecoverySheet: $showRecoverySheet)
                        DisclosureGroup("Why Sovereign is different") {
                            CenturionShowcaseSection()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                    } else {
                        CenturionShowcaseSection()
                        DeviceLinkSection(showPairingSheet: $showPairingSheet)
                        ThinkingServiceSection(showRecoverySheet: $showRecoverySheet)
                    }
                    youSection
                    memoryHorizonSection
                    reportingOversightSection
                    collaborationsSection
                    privacySection
                    supportSection
                    identitySection
                    appearanceSection
                    aboutSection
                    resetSection
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
        .alert("Reset Identity?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                connectionManager.disconnect()
                try? IdentityKey.reset()
            }
        } message: {
            Text("Your iPhone will get a new security identity. Approve it again on your Sovereign before reconnecting.")
        }
        .sheet(isPresented: $showKeyExport) {
            KeyExportView()
        }
        .sheet(isPresented: $showPairingSheet) {
            ConnectionPairingSheet()
                .environmentObject(connectionManager)
        }
        .sheet(isPresented: $showRecoverySheet) {
            ThinkingRecoverySheet(
                initialMessage: "Your Sovereign's thinking service needs attention."
            )
            .environmentObject(connectionManager)
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
        .sheet(isPresented: $showCollaborations) {
            ConstellationView { swarm in
                showCollaborations = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    selectedCollaboration = swarm
                }
            }
            .environmentObject(swarmStore)
        }
        .sheet(isPresented: $showSwarmConnect) {
            SwarmConnectSheet()
                .environmentObject(connectionManager)
                .environmentObject(swarmStore)
        }
        .sheet(item: $selectedCollaboration) { swarm in
            SwarmDetailSheet(swarm: swarm)
                .environmentObject(swarmStore)
        }
        .sheet(isPresented: $showPrivacyTrust) {
            NavigationStack {
                SecurityHubView()
                    .environmentObject(connectionManager)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPrivacyTrust = false }
                                .foregroundColor(ColorTheme.accent())
                        }
                    }
            }
        }
    }

    // MARK: - Sections

    private var linkHeroSection: some View {
        AtmosphericSurface(elevated: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Link your Centurion")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Paste a pairing code from Sovereign AI Brain on your computer. That unlocks Crypto Chat and Thinking Service on this iPhone.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)
                Button("Paste pairing code") {
                    showPairingSheet = true
                    Haptics.lightTap()
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var youSection: some View {
        settingsSection(title: "You", icon: "sparkles") {
            NavigationLink(destination: MissionView()) {
                CenturionListRow(
                    icon: "target",
                    title: "Your Mission",
                    subtitle: missionStore.hasMissionStatement
                        ? missionStore.mission.statement
                        : "Your life purpose and commitments"
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            NavigationLink(destination: SoulDocumentView()) {
                CenturionListRow(
                    icon: "sparkles",
                    title: "Your Sovereign's Soul",
                    subtitle: missionStore.soulSubtitle
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            NavigationLink(destination: AutonomyLevelView()) {
                CenturionListRow(
                    icon: "slider.horizontal.3",
                    title: "Autonomy Level",
                    subtitle: oversightStore.autonomySubtitle
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var memoryHorizonSection: some View {
        settingsSection(
            title: "Memory",
            icon: "circle.hexagongrid",
            footer: "How your Centurion remembers — a small always-on card, conversation history, and optional sealed notes. Not a hardware meter."
        ) {
            NavigationLink(destination: MemoryHorizonView()) {
                CenturionListRow(
                    icon: "circle.hexagongrid",
                    title: "Memory Horizon",
                    subtitle: memoryHorizonStore.subtitle
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var reportingOversightSection: some View {
        settingsSection(
            title: "Reporting & Oversight",
            icon: "eye",
            footer: "Controls how often your Centurion reports back and what needs your confirmation. Changes apply on the next conversation."
        ) {
            NavigationLink(destination: ReportingOversightView()) {
                CenturionListRow(
                    icon: "eye",
                    title: "Reporting & Oversight",
                    subtitle: oversightStore.oversightSubtitle
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var collaborationsSection: some View {
        settingsSection(
            title: "Collaborations",
            icon: "circle.hexagongrid.fill",
            footer: "Collaborations live on Home as orbs — not a separate tab. You're notified only when a choice is needed."
        ) {
            Button {
                showCollaborations = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.body)
                        .foregroundColor(ColorTheme.accent())
                        .frame(width: 24)
                    Text("Active collaborations")
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText())
                    Spacer()
                    Text("\(swarmStore.heroSwarms.count)")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            sectionDivider

            Button {
                showSwarmConnect = true
            } label: {
                CenturionListRow(
                    icon: "person.badge.plus",
                    title: "Connect another Sovereign",
                    subtitle: "Invite a friend or join a shared collaboration"
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Pulse attention")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Controls what shows in the app — not phone alerts. OS notifications are not part of this build.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Pulse attention", selection: Binding(
                    get: { swarmStore.digestMode },
                    set: { swarmStore.setDigestMode($0) }
                )) {
                    ForEach(SwarmStore.SwarmDigestMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .tint(ColorTheme.accent())
                .labelsHidden()
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var supportSection: some View {
        settingsSection(
            title: "Support",
            icon: "lifepreserver",
            footer: "Adrian helps you live your mission — listen first, one step at a time."
        ) {
            Button { showGetHelp = true } label: {
                CenturionListRow(icon: "lifepreserver", title: "Get Help", showChevron: false)
            }
            .buttonStyle(.plain)

            sectionDivider

            Button { showAdrian = true } label: {
                CenturionListRow(icon: "person.crop.circle.fill", title: "Talk to Adrian", showChevron: false)
            }
            .buttonStyle(.plain)

            sectionDivider

            Button {
                UIApplication.shared.open(CenturionHelp.baseURL)
            } label: {
                CenturionListRow(
                    icon: "book.pages",
                    title: "Browse Help Center",
                    subtitle: "help.1human1ai.com"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var identitySection: some View {
        settingsSection(title: "Identity", icon: "person.crop.circle") {
            settingsRow(icon: "iphone", title: "Device Name") {
                Text(UIDevice.current.name)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }

            sectionDivider

            settingsRow(icon: "key.fill", title: "Security Code") {
                Button("Show") { showKeyExport = true }
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
            }
        }
    }

    private var appearanceSection: some View {
        settingsSection(title: "Appearance", icon: "paintbrush.fill") {
            settingsRow(icon: "paintbrush.fill", title: "Theme") {
                Picker("Theme", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(ColorTheme.accent())
                .labelsHidden()
            }
        }
    }

    private var privacySection: some View {
        settingsSection(
            title: "Privacy & Trust",
            icon: "lock.shield",
            footer: "Share this with leadership when someone says AI is \"too risky\" — Sovereign is built differently."
        ) {
            Button { showPrivacyTrust = true } label: {
                CenturionListRow(
                    icon: "lock.shield.fill",
                    title: "Privacy & Trust",
                    subtitle: "Why Sovereign is different — comparisons & calm answers"
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            CenturionReassuranceRow(
                icon: "network",
                title: "Private on your network",
                detail: "Messages stay between your iPhone and Sovereign"
            )

            sectionDivider

            CenturionReassuranceRow(
                icon: "lock.fill",
                title: "Crypto Chat",
                detail: connectionManager.isChannelEncrypted
                    ? "On — private encrypted conversation with your Sovereign"
                    : "Link your Sovereign to turn on Crypto Chat — something public AIs do not offer"
            )

            sectionDivider

            CenturionReassuranceRow(
                icon: "person.crop.circle.badge.checkmark",
                title: "No cloud account",
                detail: "You don't need to sign in to a third-party service for the private link"
            )
        }
    }

    private var aboutSection: some View {
        settingsSection(title: "About", icon: "info.circle") {
            VStack(spacing: Spacing.sm) {
                CenturionAppMark(size: 64)
                Text("Centurion")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Sovereign AI Remote")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                Text("1 Human 1 AI")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)

            sectionDivider

            settingsRow(icon: "info.circle", title: "Version") {
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }

            sectionDivider

            settingsRow(icon: "sparkle", title: "Release") {
                Text("Mission Horizon")
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
            }
        }
    }

    private var resetSection: some View {
        settingsSection(
            title: "Danger Zone",
            icon: "exclamationmark.triangle",
            footer: "Not sure you need this? Tap Talk to Adrian in Support above — Adrian can help first. Resetting gives you a new pairing code; you'll need to link again in You."
        ) {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(ColorTheme.error())
                        .frame(width: 24)
                    Text("Reset Identity")
                        .font(.body)
                        .foregroundColor(ColorTheme.error())
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Layout Helpers

    private var sectionDivider: some View {
        Rectangle()
            .fill(ColorTheme.border())
            .frame(height: 0.5)
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsSectionCard(title: title, icon: icon, footer: footer, content: content())
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(ColorTheme.accent())
                .frame(width: 24)
            Text(title)
                .font(.body)
                .foregroundColor(ColorTheme.primaryText())
            Spacer()
            trailing()
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Settings Section Card

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let footer: String?
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: title, icon: icon)
            AtmosphericSurface {
                VStack(spacing: Spacing.sm) {
                    content
                }
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.horizontal, Spacing.xs)
                    .lineSpacing(2)
            }
        }
    }
}

struct KeyExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fingerprint = ""
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                SheetHeader(
                    title: "Your iPhone Security Code",
                    subtitle: "For remote pairing, paste the token:…@host:9119 code from your Centurion. On the same Wi‑Fi without a token, you can still approve with: centurion-remote approve <code>."
                )

                Image(systemName: "key.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(ColorTheme.accent())
                    .symbolRenderingMode(.hierarchical)

                if let loadError {
                    ErrorState(
                        title: "Couldn't load code",
                        message: loadError,
                        retryTitle: "Try again",
                        onRetry: loadFingerprint
                    )
                } else {
                    AtmosphericSurface(elevated: true) {
                        Text(fingerprint)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(ColorTheme.primaryText())
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if !fingerprint.isEmpty {
                        Button("Copy Code") {
                            UIPasteboard.general.string = fingerprint
                            Haptics.success()
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())
                    }
                }

                Spacer()
            }
            .padding()
            .background(ColorTheme.background())
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
            loadError = nil
        } catch {
            loadError = "Your secure identity couldn't be loaded."
        }
    }
}
