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
    @State private var anywhereBusy = false
    @State private var anywhereError: String?
    @State private var deskOpsBusy = false
    @State private var deskOpsStatus = ""
    @State private var deskOpsError: String?
    @State private var showLicenseSheet = false
    @State private var licenseCode = ""
    @State private var firecrawlKey = ""
    @State private var showFirecrawlSheet = false
    @State private var brainVersionLabel = ""

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
                    if !connectionManager.isCryptoChatReady {
                        linkHeroSection
                        DeviceLinkSection(showPairingSheet: $showPairingSheet)
                        ThinkingServiceSection(showRecoverySheet: $showRecoverySheet)
                        GatewayControlSection()
                        DisclosureGroup("Why Sovereign is different") {
                            CenturionShowcaseSection()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                    } else {
                        CenturionShowcaseSection()
                        DeviceLinkSection(showPairingSheet: $showPairingSheet)
                        ThinkingServiceSection(showRecoverySheet: $showRecoverySheet)
                        GatewayControlSection()
                        anywhereRelaySection
                        deskOpsSection
                        brainUpdatesSection
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
        .sheet(isPresented: $showLicenseSheet) {
            NavigationStack {
                Form {
                    Section("Redeem") {
                        TextField("License code", text: $licenseCode)
                        Button("Activate") {
                            Task { await redeemLicense() }
                        }
                        .disabled(licenseCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || deskOpsBusy)
                    }
                }
                .navigationTitle("License")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showLicenseSheet = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showFirecrawlSheet) {
            NavigationStack {
                Form {
                    Section("FIRECRAWL_API_KEY") {
                        SecureField("API key", text: $firecrawlKey)
                        Button("Save on Brain") {
                            Task { await saveFirecrawlKey() }
                        }
                        .disabled(firecrawlKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || deskOpsBusy)
                    }
                }
                .navigationTitle("Firecrawl")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showFirecrawlSheet = false }
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

    private var brainUpdatesSection: some View {
        settingsSection(
            title: "Updates",
            icon: "arrow.triangle.2.circlepath",
            footer: "The iPhone app updates from the App Store. Brain / OS packages update on the desk — this phone does not rebuild GTK."
        ) {
            settingsRow(icon: "iphone", title: "Remote app") {
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }

            sectionDivider

            Button {
                Task { await refreshBrainVersion() }
            } label: {
                CenturionListRow(
                    icon: "desktopcomputer",
                    title: "Brain / OS",
                    subtitle: brainVersionLabel.isEmpty
                        ? "Tap to read version from this Brain"
                        : brainVersionLabel
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            CenturionReassuranceRow(
                icon: "hammer",
                title: "Update on the desk",
                detail: "Install Brain / Centurion OS updates on your computer, then reopen Remote."
            )
        }
        .onAppear {
            if brainVersionLabel.isEmpty {
                Task { await refreshBrainVersion() }
            }
        }
    }

    @MainActor
    private func refreshBrainVersion() async {
        do {
            let payload = try await connectionManager.bridgePing()
            let version = (payload["version"] as? String)
                ?? (payload["centurion_version"] as? String)
                ?? "unknown"
            brainVersionLabel = "Centurion OS \(version)"
        } catch {
            brainVersionLabel = connectionManager.friendlyRemoteError(error)
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

    private var anywhereRelaySection: some View {
        let enabled = (connectionManager.remoteRelayStatus["enabled"] as? Bool) ?? false
        let online = ((connectionManager.remoteRelayStatus["presence"] as? [String: Any])?["online"] as? Bool) ?? false
        let subtitle: String = {
            if anywhereBusy { return "Updating…" }
            if enabled && online {
                return "On — Brain presence live. Away uses Centurion cloud (E2E); home Wi‑Fi still preferred."
            }
            if enabled {
                return "On — waiting for Brain presence on the relay"
            }
            return "Off — Crypto Chat on home Wi‑Fi only (most private)"
        }()
        return settingsSection(
            title: "Chat from anywhere",
            icon: "globe",
            footer: "Pair once at home. Enable on this Brain so the same App Store app works away from Wi‑Fi while the Brain is online. Content stays end-to-end encrypted; Centurion cloud sees metadata only."
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anywhere")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            Task { @MainActor in
                                anywhereBusy = true
                                anywhereError = nil
                                do {
                                    if newValue {
                                        _ = try await connectionManager.enableRemoteRelay()
                                    } else {
                                        _ = try await connectionManager.disableRemoteRelay()
                                    }
                                    _ = await connectionManager.refreshRemoteRelayStatus()
                                } catch {
                                    anywhereError = connectionManager.friendlyRemoteError(error)
                                }
                                anywhereBusy = false
                            }
                        }
                    )
                )
                .labelsHidden()
                .disabled(anywhereBusy || !connectionManager.isCryptoChatReady)
            }
            .onAppear {
                Task { _ = await connectionManager.refreshRemoteRelayStatus() }
            }
            if let anywhereError {
                Text(anywhereError)
                    .font(.caption)
                    .foregroundColor(ColorTheme.error())
            }

            sectionDivider

            Button {
                UIApplication.shared.open(CenturionHelp.localRemoteTelegramPrivacy)
            } label: {
                CenturionListRow(
                    icon: "lock.shield",
                    title: "Privacy choices",
                    subtitle: "Local, Remote anywhere, or Telegram"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var deskOpsSection: some View {
        settingsSection(
            title: "Brain desk",
            icon: "desktopcomputer",
            footer: "Same controls as Linux Brain Settings — works on home Wi‑Fi and Chat from anywhere."
        ) {
            Button {
                Task { await refreshDeskOpsGlance() }
            } label: {
                CenturionListRow(
                    icon: "gauge.with.dots.needle.33percent",
                    title: "Ops glance",
                    subtitle: deskOpsStatus.isEmpty ? "Scheduled jobs & board summary" : deskOpsStatus
                )
            }
            .buttonStyle(.plain)
            .disabled(deskOpsBusy || !connectionManager.isCryptoChatReady)

            sectionDivider

            Button {
                Task { await refreshLicenseStatus() }
                showLicenseSheet = true
            } label: {
                CenturionListRow(
                    icon: "rosette",
                    title: "License",
                    subtitle: "Status and redeem on this Brain"
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            Button {
                showFirecrawlSheet = true
            } label: {
                CenturionListRow(
                    icon: "flame",
                    title: "Firecrawl",
                    subtitle: "Research tool API key on the Brain"
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            Button {
                Task { await refreshSkillsSnapshot() }
            } label: {
                CenturionListRow(
                    icon: "wrench.and.screwdriver",
                    title: "Skills & tools",
                    subtitle: deskOpsStatus.hasPrefix("Skills:") ? deskOpsStatus : "Snapshot of tools on this Brain"
                )
            }
            .buttonStyle(.plain)
            .disabled(deskOpsBusy || !connectionManager.isCryptoChatReady)

            sectionDivider

            Button {
                Task { await refreshFleetStatus() }
            } label: {
                CenturionListRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Fleet peer",
                    subtitle: "Status of this Brain on the fleet"
                )
            }
            .buttonStyle(.plain)
            .disabled(deskOpsBusy || !connectionManager.isCryptoChatReady)

            sectionDivider

            Button {
                Task { await refreshPlugins() }
            } label: {
                CenturionListRow(
                    icon: "puzzlepiece.extension",
                    title: "Installed plugins",
                    subtitle: "List plugins on this Brain"
                )
            }
            .buttonStyle(.plain)
            .disabled(deskOpsBusy || !connectionManager.isCryptoChatReady)

            sectionDivider

            Button {
                Task { await previewTelegramImport() }
            } label: {
                CenturionListRow(
                    icon: "paperplane",
                    title: "Telegram history",
                    subtitle: "Preview import into Brain sessions"
                )
            }
            .buttonStyle(.plain)
            .disabled(deskOpsBusy || !connectionManager.isCryptoChatReady)

            if let deskOpsError {
                Text(deskOpsError)
                    .font(.caption)
                    .foregroundColor(ColorTheme.error())
                    .padding(.top, 4)
            } else if !deskOpsStatus.isEmpty {
                Text(deskOpsStatus)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.top, 4)
            }
        }
    }

    @MainActor
    private func refreshDeskOpsGlance() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            let payload = try await connectionManager.opsGlance()
            if let summary = payload["summary"] as? String, !summary.isEmpty {
                deskOpsStatus = summary
            } else {
                deskOpsStatus = "Ops glance updated"
            }
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func refreshLicenseStatus() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            let payload = try await connectionManager.licenseStatus()
            let mode = (payload["mode"] as? String)
                ?? (payload["license_mode"] as? String)
                ?? "unknown"
            deskOpsStatus = "License: \(mode)"
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func redeemLicense() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            _ = try await connectionManager.licenseRedeem(code: licenseCode)
            deskOpsStatus = "License redeemed"
            showLicenseSheet = false
            licenseCode = ""
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func saveFirecrawlKey() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            _ = try await connectionManager.setToolEnv(key: "FIRECRAWL_API_KEY", value: firecrawlKey)
            deskOpsStatus = "Firecrawl key saved on Brain"
            showFirecrawlSheet = false
            firecrawlKey = ""
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func refreshSkillsSnapshot() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            let payload = try await connectionManager.toolsSkillsSnapshot()
            let count = (payload["skills"] as? [Any])?.count
                ?? (payload["tools"] as? [Any])?.count
                ?? 0
            deskOpsStatus = "Skills: \(count) entries"
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func refreshFleetStatus() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            let payload = try await connectionManager.fleetStatus()
            let peers = (payload["peers"] as? [Any])?.count ?? 0
            deskOpsStatus = "Fleet peers: \(peers)"
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func refreshPlugins() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            let payload = try await connectionManager.pluginList()
            let count = (payload["plugins"] as? [Any])?.count
                ?? (payload["installed"] as? [Any])?.count
                ?? 0
            deskOpsStatus = "Plugins: \(count)"
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
        }
    }

    @MainActor
    private func previewTelegramImport() async {
        deskOpsBusy = true
        deskOpsError = nil
        defer { deskOpsBusy = false }
        do {
            let payload = try await connectionManager.telegramImportPreview()
            let n = (payload["sessions"] as? [Any])?.count
                ?? (payload["count"] as? Int)
                ?? 0
            deskOpsStatus = "Telegram import preview: \(n) session(s)"
        } catch {
            deskOpsError = connectionManager.friendlyRemoteError(error)
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
                    subtitle: "Pair on home Wi‑Fi with the QR (or paste token:…@lan-host:9119). Away uses Chat from anywhere after you enable it — no home IP. On the same Wi‑Fi without a token, you can still approve with: centurion-remote approve <code>."
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
