import SwiftUI

/// You tab — shared map with Brain Settings (same labels, same order):
/// You → Your Sovereign → Collaborations → Family & friends →
/// Connect → This Brain → Privacy & Trust → Help & about.
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
    @State private var showSwarmConnect = false
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
                    if connectionManager.isCryptoChatReady && connectionManager.llmHealth.needsAttention {
                        thinkingAttentionBanner
                    }
                    if !connectionManager.isCryptoChatReady {
                        linkHeroSection
                    }
                    youSection
                    youHubMenu
                    if !connectionManager.isCryptoChatReady {
                        DisclosureGroup("Why Sovereign is different") {
                            CenturionShowcaseSection()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                    }
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                guard connectionManager.isCryptoChatReady else { return }
                await beneficiaryStore.refresh(from: connectionManager)
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
        .sheet(isPresented: $showSwarmConnect) {
            SwarmConnectSheet(presentation: .advanced)
                .environmentObject(connectionManager)
                .environmentObject(swarmStore)
                .environmentObject(missionStore)
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

    // MARK: - Hub

    private var thinkingAttentionBanner: some View {
        NavigationLink {
            YouSettingsPage(title: "Your Sovereign") {
                ThinkingServiceSection(showRecoverySheet: $showRecoverySheet)
                memoryHorizonSection
                reportingOversightSection
            }
        } label: {
            AtmosphericSurface(elevated: true) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(ColorTheme.error())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thinking needs attention")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText())
                        Text("Open Your Sovereign to fix it")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var youHubMenu: some View {
        AtmosphericSurface {
            VStack(spacing: Spacing.sm) {
                hubLink(icon: "brain.head.profile", title: "Your Sovereign", subtitle: sovereignHubSubtitle) {
                    YouSettingsPage(title: "Your Sovereign") {
                        ThinkingServiceSection(showRecoverySheet: $showRecoverySheet)
                        memoryHorizonSection
                        reportingOversightSection
                    }
                }

                sectionDivider

                hubLink(icon: "circle.hexagongrid.fill", title: "Collaborations", subtitle: collaborationsHubSubtitle) {
                    YouSettingsPage(title: "Collaborations") {
                        collaborationsSection
                    }
                }

                sectionDivider

                hubLink(icon: "person.2.fill", title: "Family & friends", subtitle: familyHubSubtitle) {
                    YouSettingsPage(title: "Family & friends") {
                        FamilyFriendsReferralSection()
                    }
                }

                sectionDivider

                hubLink(icon: "antenna.radiowaves.left.and.right", title: "Connect", subtitle: connectHubSubtitle) {
                    YouSettingsPage(title: "Connect") {
                        DeviceLinkSection(showPairingSheet: $showPairingSheet)
                    }
                }

                sectionDivider

                hubLink(icon: "desktopcomputer", title: "This Brain", subtitle: "Gateway, updates, desk") {
                    YouSettingsPage(title: "This Brain") {
                        GatewayControlSection()
                        if connectionManager.isCryptoChatReady {
                            anywhereRelaySection
                            deskOpsSection
                            brainUpdatesSection
                        }
                    }
                }

                sectionDivider

                hubLink(icon: "lock.shield", title: "Privacy & Trust", subtitle: "What stays private") {
                    YouSettingsPage(title: "Privacy & Trust") {
                        privacySection
                    }
                }

                sectionDivider

                hubLink(icon: "lifepreserver", title: "Help & about", subtitle: "Get Help, Adrian, appearance") {
                    YouSettingsPage(title: "Help & about") {
                        supportSection
                        appearanceSection
                        identitySection
                        aboutSection
                        resetSection
                    }
                }
            }
        }
    }

    private var connectHubSubtitle: String {
        if connectionManager.isRelayAwayConnected {
            return "Linked · Away"
        }
        if connectionManager.isCryptoChatReady {
            let badge = connectionManager.linkPathBadge
            return badge.isEmpty ? "Linked" : "Linked · \(badge)"
        }
        return "Not linked"
    }

    private var sovereignHubSubtitle: String {
        if connectionManager.llmHealth.needsAttention {
            return "Thinking needs attention"
        }
        if connectionManager.isCryptoChatReady {
            return connectionManager.thinkingServiceHeadline
        }
        return "Thinking, memory, reporting"
    }

    private var collaborationsHubSubtitle: String {
        let count = swarmStore.heroSwarms.count
        if count == 1 { return "1 active" }
        return "\(count) active"
    }

    private var familyHubSubtitle: String {
        if beneficiaryStore.hasBeneficiary {
            return beneficiaryStore.beneficiaryFirstName
        }
        return "Nominate family"
    }

    private func hubLink<Dest: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder destination: () -> Dest
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            CenturionListRow(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections

    private var linkHeroSection: some View {
        AtmosphericSurface(elevated: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Connect to your Brain")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Start pairing to scan the QR on Sovereign AI Brain. That unlocks Crypto Chat on this iPhone.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)
                Button("Start pairing") {
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
            footer: "Collaborations live on the Collab tab as orbs. Form a swarm on this Brain, or join another owner through Mission Control."
        ) {
            Button {
                AdrianNavigation.selectTab(AdrianNavigation.collabTab)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.body)
                        .foregroundColor(ColorTheme.accent())
                        .frame(width: 24)
                    Text("Open Collab")
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
                AdrianNavigation.selectTab(AdrianNavigation.collabTab)
            } label: {
                CenturionListRow(
                    icon: "person.badge.plus",
                    title: "Start a collaboration",
                    subtitle: "Opens Collab — give your Sovereign a goal"
                )
            }
            .buttonStyle(.plain)

            sectionDivider

            Button {
                showSwarmConnect = true
            } label: {
                CenturionListRow(
                    icon: "person.2.badge.gearshape",
                    title: "Join or invite",
                    subtitle: "Mission Control token — a down portal shows an error"
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
        let wsOk = (connectionManager.remoteRelayStatus["websockets_installed"] as? Bool) ?? true
        let pipeReady = (connectionManager.remoteRelayStatus["realtime_pipe_ready"] as? Bool) ?? false
        let urlConfigured = (connectionManager.remoteRelayStatus["supabase_url_configured"] as? Bool) ?? false
        let presenceError = ((connectionManager.remoteRelayStatus["presence"] as? [String: Any])?["last_error"] as? String)
        let hint = connectionManager.remoteRelayStatus["hint"] as? String
        let subtitle: String = {
            if anywhereBusy { return "Updating…" }
            if enabled, !wsOk {
                return presenceError
                    ?? hint
                    ?? "On — but Away needs websockets on the Brain (Check for update)."
            }
            if enabled, pipeReady {
                return "On — Away pipe ready. Home Wi‑Fi still preferred when you’re here."
            }
            if enabled && online {
                return "On — Brain presence live. Away uses Centurion cloud (E2E); home Wi‑Fi still preferred."
            }
            if enabled, !urlConfigured {
                return presenceError
                    ?? "On — Centurion cloud did not return Realtime endpoints"
            }
            if enabled, let presenceError, !presenceError.isEmpty {
                return presenceError
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
                        .foregroundColor(
                            enabled && !wsOk ? ColorTheme.warning() : ColorTheme.mutedText()
                        )
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
                UIPasteboard.general.string = connectionManager.speedSoakExportText(
                    away: connectionManager.isRelayAwayConnected
                        || !connectionManager.prefersLanCryptoChat
                )
                anywhereError = nil
                deskOpsStatus = "Speed soak command copied"
            } label: {
                CenturionListRow(
                    icon: "gauge.with.needle",
                    title: "Copy speed soak samples",
                    subtitle: {
                        let rtt = connectionManager.lastTransportRttMs.map { String(format: "%.0f ms RTT", $0) }
                        let ttft = connectionManager.lastTtftOverheadMs.map { String(format: "%.0f ms TTFT", $0) }
                        let bits = [rtt, ttft].compactMap { $0 }
                        return bits.isEmpty
                            ? "Ping / chat a few times, then paste into the Brain soak CLI"
                            : bits.joined(separator: " · ")
                    }()
                )
            }
            .buttonStyle(.plain)
            .disabled(!connectionManager.isCryptoChatReady)

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
            footer: "Status glances from this Brain — not full desk control. Manage skills, fleet, plugins, and Telegram on Linux."
        ) {
            Button {
                Task { await refreshDeskOpsGlance() }
            } label: {
                CenturionListRow(
                    icon: "gauge.with.dots.needle.33percent",
                    title: "Ops glance",
                    subtitle: deskOpsStatus.isEmpty ? "Glance: scheduled jobs & board summary" : deskOpsStatus
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
                    title: "Skills & tools (glance)",
                    subtitle: deskOpsStatus.hasPrefix("Skills:") ? deskOpsStatus : "Status only — manage on the desk"
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
                    title: "Fleet peer (glance)",
                    subtitle: "Status only — manage fleet on the desk"
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
                    title: "Installed plugins (glance)",
                    subtitle: "Status only — install/remove on the desk"
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
                    title: "Telegram history (glance)",
                    subtitle: "Preview only — import runs on the desk"
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

// MARK: - Subpage chrome

private struct YouSettingsPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                content
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
