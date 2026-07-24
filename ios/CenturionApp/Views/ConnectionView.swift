import SwiftUI
import UIKit

/// Connection Hub — device link and thinking service as separate, calm status cards.
struct ConnectionView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var adrianService: AdrianService
    @EnvironmentObject private var missionStore: MissionStore
    @State private var showPairingSheet = false
    @State private var showRecoverySheet = false
    @State private var showGetHelp = false
    @State private var showAdrian = false

    var body: some View {
        MainTabChrome(title: "Connect") {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    trustStatement
                    deviceLinkCard

                    if connectionManager.connectionState == .connected {
                        thinkingServiceCard
                    }

                    primaryActionButton
                    supportLinks
                    reassuranceSection
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }
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
    }

    private var trustStatement: some View {
        VStack(spacing: Spacing.xs) {
            Text("Your Sovereign stays with you anywhere — link once with a remote pairing code. Same Wi‑Fi is a bonus when you’re home.")
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
            Text("This shows whether your iPhone is linked and whether your Sovereign can think properly.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var deviceLinkCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionStatusCard(
                title: "Device link",
                icon: "antenna.radiowaves.left.and.right",
                headline: deviceLinkHeadline,
                detail: deviceLinkDetail,
                isPositive: connectionManager.connectionState == .connected,
                accessibilityLabel: "Device link, \(deviceLinkHeadline). \(deviceLinkDetail)"
            )
            if connectionManager.connectionState == .connected {
                EncryptionStatusBadge(isEncrypted: connectionManager.isChannelEncrypted)
            }
        }
    }

    private var thinkingServiceCard: some View {
        CenturionStatusCard(
            title: "Thinking service",
            icon: "brain.head.profile",
            headline: connectionManager.thinkingServiceHeadline,
            detail: connectionManager.thinkingServiceSubtitle,
            isPositive: !connectionManager.llmHealth.needsAttention,
            accessibilityLabel: "Thinking service, \(connectionManager.thinkingServiceHeadline). \(connectionManager.thinkingServiceSubtitle)"
        )
        .task {
            await connectionManager.refreshThinkingStatus()
            await connectionManager.refreshRoutingMode()
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if connectionManager.connectionState != .connected {
            if hasSavedLink {
                VStack(spacing: Spacing.sm) {
                    Button {
                        Haptics.lightTap()
                        connectionManager.reconnect()
                    } label: {
                        Text("Reconnect")
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .accessibilityLabel("Reconnect to your Centurion")

                    Button {
                        Haptics.lightTap()
                        showPairingSheet = true
                    } label: {
                        Text("Link to your Centurion")
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                    .accessibilityLabel("Link to your Centurion")
                }
            } else {
                Button {
                    Haptics.lightTap()
                    showPairingSheet = true
                } label: {
                    Text("Link to your Centurion")
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .accessibilityLabel("Link to your Centurion")
            }
        } else if connectionManager.llmHealth.needsAttention {
            Button {
                Haptics.lightTap()
                showRecoverySheet = true
            } label: {
                Text("Fix Thinking Service")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .accessibilityLabel("Fix Thinking Service")
        } else {
            Button {
                Haptics.lightTap()
                connectionManager.reconnect()
            } label: {
                Text("Reconnect")
            }
            .buttonStyle(CenturionGhostButtonStyle())
            .accessibilityLabel("Reconnect to your Centurion")
        }
    }

    private var hasSavedLink: Bool {
        if case .error = connectionManager.connectionState { return true }
        if case .awaitingApproval = connectionManager.connectionState { return true }
        if case .connecting = connectionManager.connectionState { return true }
        return connectionManager.hasPersistedLink
    }

    private var supportLinks: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.lg) {
                Button { showGetHelp = true } label: {
                    Text("Get Help")
                }
                .buttonStyle(CenturionGhostButtonStyle())
                .accessibilityLabel("Get Help")
                AdrianLink(showAdrian: $showAdrian)
            }
            HelpCenterLink()
        }
        .frame(maxWidth: .infinity)
    }

    private var reassuranceSection: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CenturionSectionHeader(title: "Your Privacy", icon: "lock.shield")
                Text("Crypto Chat keeps conversations between you and your Sovereign — encrypted end to end. Public AIs have no equivalent.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(4)
            }
        }
    }

    private var deviceLinkHeadline: String {
        switch connectionManager.connectionState {
        case .connected:
            let badge = connectionManager.linkPathBadge
            return badge.isEmpty ? "Linked" : "Linked · \(badge)"
        case .awaitingApproval: return "Waiting for approval"
        case .discovering, .connecting: return "Connecting"
        case .error: return "Connection issue"
        case .disconnected: return "Not linked"
        }
    }

    private var deviceLinkDetail: String {
        switch connectionManager.connectionState {
        case .connected:
            if let device = connectionManager.connectedDevice {
                let base = connectionManager.isChannelEncrypted
                    ? "Crypto Chat on — linked to \(device.name)"
                    : "Linked to \(device.name)"
                if device.isRemotePath || device.isTailscalePath {
                    return base
                }
                return "\(base). Remote pairing keeps you linked away from home."
            }
            return connectionManager.isChannelEncrypted
                ? "Crypto Chat on — linked to your Sovereign"
                : "Linked to your Sovereign"
        case .discovering:
            return "Looking for your Sovereign on this network…"
        case .connecting:
            return "Setting up Crypto Chat…"
        case .disconnected:
            return "Paste a remote pairing code from your Centurion — or find it on the same Wi‑Fi"
        case .awaitingApproval(let message):
            return message
        case .error(let message):
            return message
        }
    }

    private var thinkingServiceDetail: String {
        if let status = connectionManager.thinkingStatus {
            if status.lastGoodAvailable && connectionManager.llmHealth.needsAttention {
                return "Last working setup is available."
            }
            if !status.healthMessage.isEmpty, connectionManager.llmHealth.needsAttention {
                return status.healthMessage
            }
        }
        switch connectionManager.llmHealth {
        case .healthy:
            return "Your Sovereign can answer messages."
        case .unknown:
            return "Checking with your Sovereign…"
        default:
            return "Your Sovereign may not be able to reply right now."
        }
    }
}

// MARK: - Device Link Section (You tab)

struct DeviceLinkSection: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Binding var showPairingSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Your link", icon: "antenna.radiowaves.left.and.right")

            AtmosphericSurface {
                VStack(spacing: Spacing.md) {
                    CenturionStatusCard(
                        title: "Device link",
                        icon: "antenna.radiowaves.left.and.right",
                        headline: deviceLinkHeadline,
                        detail: deviceLinkDetail,
                        isPositive: connectionManager.connectionState == .connected,
                        accessibilityLabel: "Device link, \(deviceLinkHeadline). \(deviceLinkDetail)"
                    )

                    if connectionManager.connectionState == .connected {
                        EncryptionStatusBadge(isEncrypted: connectionManager.isChannelEncrypted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if connectionManager.connectionState != .connected {
                        VStack(spacing: Spacing.sm) {
                            if hasSavedLink {
                                Button {
                                    Haptics.lightTap()
                                    connectionManager.reconnect()
                                } label: {
                                    Text("Reconnect")
                                }
                                .buttonStyle(CenturionPrimaryButtonStyle())

                                Button {
                                    Haptics.lightTap()
                                    showPairingSheet = true
                                } label: {
                                    Text("Link to your Centurion")
                                }
                                .buttonStyle(CenturionGhostButtonStyle())
                            } else {
                                Button {
                                    Haptics.lightTap()
                                    showPairingSheet = true
                                } label: {
                                    Text("Link to your Centurion")
                                }
                                .buttonStyle(CenturionPrimaryButtonStyle())
                            }
                        }
                    } else {
                        VStack(spacing: Spacing.sm) {
                            Button {
                                Haptics.lightTap()
                                connectionManager.reconnect()
                            } label: {
                                Text("Reconnect")
                            }
                            .buttonStyle(CenturionGhostButtonStyle())

                            Button(role: .destructive) {
                                connectionManager.disconnect()
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "power")
                                    Text("Disconnect")
                                    Spacer()
                                }
                                .font(.body)
                                .foregroundColor(ColorTheme.error())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Link once with a remote pairing code from your Centurion. Same Wi‑Fi still works when you’re home.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var hasSavedLink: Bool {
        if case .error = connectionManager.connectionState { return true }
        if case .awaitingApproval = connectionManager.connectionState { return true }
        if case .connecting = connectionManager.connectionState { return true }
        return connectionManager.hasPersistedLink
    }

    private var deviceLinkHeadline: String {
        switch connectionManager.connectionState {
        case .connected:
            let badge = connectionManager.linkPathBadge
            return badge.isEmpty ? "Linked" : "Linked · \(badge)"
        case .awaitingApproval: return "Waiting for approval"
        case .discovering, .connecting: return "Connecting"
        case .error: return "Connection issue"
        case .disconnected: return "Not linked"
        }
    }

    private var deviceLinkDetail: String {
        switch connectionManager.connectionState {
        case .connected:
            if let device = connectionManager.connectedDevice {
                let base = connectionManager.isChannelEncrypted
                    ? "Crypto Chat on — linked to \(device.name)"
                    : "Linked to \(device.name)"
                if device.isRemotePath || device.isTailscalePath {
                    return base
                }
                return "\(base). Remote pairing keeps you linked away from home."
            }
            return connectionManager.isChannelEncrypted
                ? "Crypto Chat on — linked to your Sovereign"
                : "Linked to your Sovereign"
        case .discovering:
            return "Looking for your Sovereign on this network…"
        case .connecting:
            return "Setting up Crypto Chat…"
        case .disconnected:
            return "Paste a remote pairing code from your Centurion — or find it on the same Wi‑Fi"
        case .awaitingApproval(let message):
            return message
        case .error(let message):
            return message
        }
    }
}

// MARK: - Thinking Service Section (You tab)

struct ThinkingServiceSection: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Binding var showRecoverySheet: Bool
    @State private var showThinkingDial = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "How Your Sovereign Thinks", icon: "brain.head.profile")

            AtmosphericSurface {
                VStack(spacing: Spacing.md) {
                    if connectionManager.connectionState == .connected {
                        CenturionStatusCard(
                            title: "Thinking service",
                            icon: "brain.head.profile",
                            headline: connectionManager.thinkingServiceHeadline,
                            detail: connectionManager.thinkingServiceSubtitle,
                            isPositive: !connectionManager.llmHealth.needsAttention,
                            accessibilityLabel: "Thinking service, \(connectionManager.thinkingServiceHeadline). \(connectionManager.thinkingServiceSubtitle)"
                        )
                        .task(id: connectionManager.connectionState) {
                            await connectionManager.refreshThinkingStatus()
                            await connectionManager.refreshRoutingMode()
                            _ = await connectionManager.fetchRemoteModelCatalog()
                        }

                        if connectionManager.routingMode == "phoenix" {
                            Text("Automatic choice is on — your Sovereign picks a thinking service from your message.")
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let routed = connectionManager.lastRoutedDisplayName {
                            Text("Last routed to \(routed)")
                                .font(.caption)
                                .foregroundColor(ColorTheme.accent())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Haptics.lightTap()
                            showThinkingDial = true
                        } label: {
                            Text("Choose Thinking Service")
                        }
                        .buttonStyle(CenturionSecondaryButtonStyle())

                        if connectionManager.llmHealth.needsAttention {
                            Button {
                                Haptics.lightTap()
                                showRecoverySheet = true
                            } label: {
                                Text("Fix Thinking Service")
                            }
                            .buttonStyle(CenturionPrimaryButtonStyle())
                        }
                    } else {
                        Text("Link your Sovereign first to see whether it can think properly.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Text("Access codes are saved on your Sovereign, not on this iPhone.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .padding(.horizontal, Spacing.xs)
        }
        .fullScreenCover(isPresented: $showThinkingDial) {
            ThinkingServiceDialView()
                .environmentObject(connectionManager)
        }
    }

    private var thinkingServiceDetail: String {
        if let status = connectionManager.thinkingStatus {
            if status.lastGoodAvailable && connectionManager.llmHealth.needsAttention {
                return "Last working setup is available."
            }
            if !status.healthMessage.isEmpty, connectionManager.llmHealth.needsAttention {
                return status.healthMessage
            }
        }
        switch connectionManager.llmHealth {
        case .healthy:
            return "Your Sovereign can answer messages."
        case .unknown:
            return "Checking with your Sovereign…"
        default:
            return "Your Sovereign may not be able to reply right now."
        }
    }
}

// MARK: - Pairing Sheet

struct ConnectionPairingSheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var connectionString = ""
    @State private var showManualEntry = false
    @State private var showNetworkFind = false
    @State private var manualHost = ""
    @State private var manualPort = "9119"

    var body: some View {
        NavigationStack {
            Group {
                switch connectionManager.connectionState {
                case .connected:
                    connectedState
                case .awaitingApproval(let message):
                    awaitingApprovalState(message: message)
                case .connecting:
                    connectingState
                case .error(let message):
                    errorState(message: message)
                default:
                    pairingForm
                }
            }
            .background(ColorTheme.background())
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
            .onChange(of: connectionManager.connectionState) { _, newState in
                // Stay open for pairing approval; only auto-close on a stable link.
                if newState == .connected {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        if connectionManager.connectionState == .connected {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var pairingForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SheetHeader(
                    title: "Link to your Centurion",
                    subtitle: "Paste the remote pairing code from your Centurion computer. It looks like token:…@host:9119."
                )

                TextField("token:…@host:9119", text: $connectionString, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)
                    .padding(Spacing.sm)
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button("Link Remotely") {
                    Haptics.lightTap()
                    connectionManager.connectRemote(connectionString: connectionString)
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .disabled(
                    connectionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityLabel("Link Remotely")

                Text("On your Centurion: generate a code under Remote pairing, expose TCP 9119 if you’re away from home, then paste it here.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)

                Divider()

                Button {
                    showNetworkFind.toggle()
                    if showNetworkFind {
                        connectionManager.startDiscovery()
                    }
                } label: {
                    Text(showNetworkFind ? "Hide same-network find" : "Find on this Wi‑Fi")
                }
                .buttonStyle(CenturionGhostButtonStyle())

                if showNetworkFind {
                    if connectionManager.discoveredDevices.isEmpty {
                        Text("Looking for your Sovereign on this network…")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    } else {
                        ForEach(connectionManager.discoveredDevices) { device in
                            Button {
                                Haptics.lightTap()
                                connectionManager.connect(to: device)
                            } label: {
                                CenturionListRow(
                                    icon: "desktopcomputer",
                                    title: device.name,
                                    subtitle: device.hostname.isEmpty ? "On your network" : device.hostname,
                                    showChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(connectionManager.connectionState == .connecting)
                        }
                    }
                }

                manualConnectSection
            }
            .padding()
        }
    }

    private var connectingState: some View {
        VStack(spacing: Spacing.lg) {
            LoadingState(
                message: connectionManager.activeConnectionTarget.map {
                    "Linking to \($0)…"
                } ?? "Setting up Crypto Chat…"
            )
            Text("Keep this screen open while Crypto Chat finishes linking.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            ErrorState(
                title: "Couldn't link",
                message: message,
                retryTitle: "Reconnect",
                onRetry: { connectionManager.reconnect() }
            )
            Button("Back") {
                connectionManager.resetPairingAttempt()
            }
            .buttonStyle(CenturionGhostButtonStyle())
        }
        .padding()
    }

    private var connectedState: some View {
        VStack(spacing: Spacing.lg) {
            SuccessMoment(
                title: linkedSuccessTitle,
                message: connectionManager.connectedDevice?.name
            )
            EncryptionStatusBadge(isEncrypted: connectionManager.isChannelEncrypted)
            Button("Done") { dismiss() }
                .buttonStyle(CenturionPrimaryButtonStyle())
        }
        .padding()
    }

    private var linkedSuccessTitle: String {
        let badge = connectionManager.linkPathBadge
        return badge.isEmpty ? "Linked to your Sovereign" : "Linked · \(badge)"
    }

    private func awaitingApprovalState(message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            SheetHeader(
                title: "Approve on your Sovereign",
                subtitle: "Your iPhone found your Sovereign on this network. Approve it once on the computer, then this screen will finish linking automatically."
            )
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.accent())
            AtmosphericSurface {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primaryText())
                    if let fingerprint = connectionManager.clientFingerprint, !fingerprint.isEmpty {
                        Text("On your Sovereign computer, run:")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                        Text("centurion-remote approve \(fingerprint)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(ColorTheme.primaryText())
                            .textSelection(.enabled)
                        Button("Copy approve command") {
                            UIPasteboard.general.string =
                                "centurion-remote approve \(fingerprint)"
                            Haptics.success()
                        }
                        .buttonStyle(CenturionGhostButtonStyle())
                    }
                    Text("We retry automatically after you approve.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Try Again Now") {
                connectionManager.retryConnection()
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            NavigationLink {
                KeyExportView()
            } label: {
                Text("Show iPhone security code")
            }
            .buttonStyle(CenturionGhostButtonStyle())
        }
        .padding()
    }

    private var manualConnectSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                showManualEntry.toggle()
            } label: {
                Text(showManualEntry ? "Hide host entry" : "Enter host and port")
            }
            .buttonStyle(CenturionGhostButtonStyle())

            if showManualEntry {
                TextField("Hostname or IP", text: $manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(Spacing.sm)
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                TextField("Port", text: $manualPort)
                    .keyboardType(.numberPad)
                    .padding(Spacing.sm)
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("Connect") {
                    let port = Int(manualPort) ?? 9119
                    connectionManager.connect(host: manualHost, port: port)
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
