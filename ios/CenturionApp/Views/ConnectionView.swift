import SwiftUI

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
                initialMessage: "Your Centurion's thinking service needs attention."
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
            Text("Your Centurion stays reliable when your iPhone is linked to your Centurion.")
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
            Text("This shows whether your iPhone is linked and whether your Centurion can think properly.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var deviceLinkCard: some View {
        CenturionStatusCard(
            title: "Device link",
            icon: "antenna.radiowaves.left.and.right",
            headline: deviceLinkHeadline,
            detail: deviceLinkDetail,
            isPositive: connectionManager.connectionState == .connected,
            accessibilityLabel: "Device link, \(deviceLinkHeadline). \(deviceLinkDetail)"
        )
    }

    private var thinkingServiceCard: some View {
        CenturionStatusCard(
            title: "Thinking service",
            icon: "brain.head.profile",
            headline: connectionManager.llmHealth.label,
            detail: thinkingServiceDetail,
            isPositive: !connectionManager.llmHealth.needsAttention,
            accessibilityLabel: "Thinking service, \(connectionManager.llmHealth.label). \(thinkingServiceDetail)"
        )
        .task {
            await connectionManager.refreshThinkingStatus()
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if connectionManager.connectionState != .connected {
            Button {
                Haptics.lightTap()
                showPairingSheet = true
            } label: {
                Text("Find my Centurion")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .accessibilityLabel("Find my Centurion")
        } else if connectionManager.llmHealth.needsAttention {
            Button {
                Haptics.lightTap()
                showRecoverySheet = true
            } label: {
                Text("Fix Thinking Service")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .accessibilityLabel("Fix Thinking Service")
        }
    }

    private var supportLinks: some View {
        HStack(spacing: Spacing.lg) {
            Button { showGetHelp = true } label: {
                Text("Get Help")
            }
            .buttonStyle(CenturionGhostButtonStyle())
            .accessibilityLabel("Get Help")
            AdrianLink(showAdrian: $showAdrian)
        }
        .frame(maxWidth: .infinity)
    }

    private var reassuranceSection: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CenturionSectionHeader(title: "Your Privacy", icon: "lock.shield")
                Text("Your Centurion runs on your network. Conversations stay between you and your Centurion — not on a public cloud.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(4)
            }
        }
    }

    private var deviceLinkHeadline: String {
        switch connectionManager.connectionState {
        case .connected: return "Linked"
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
                return "Securely linked to \(device.name)"
            }
            return "Securely linked to your Centurion"
        case .discovering:
            return "Looking for your Centurion on your network"
        case .connecting:
            return "Setting up your private connection…"
        case .disconnected:
            return "Link your iPhone to your Centurion to get started"
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
            return "Your Centurion can answer messages."
        case .unknown:
            return "Checking with your Centurion…"
        default:
            return "Your Centurion may not be able to reply right now."
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

                    if connectionManager.connectionState != .connected {
                        Button {
                            Haptics.lightTap()
                            showPairingSheet = true
                        } label: {
                            Text("Find my Centurion")
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())
                    } else {
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

                    Text("Your iPhone and Centurion should be on the same Wi‑Fi.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var deviceLinkHeadline: String {
        switch connectionManager.connectionState {
        case .connected: return "Linked"
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
                return "Securely linked to \(device.name)"
            }
            return "Securely linked to your Centurion"
        case .discovering:
            return "Looking for your Centurion on your network"
        case .connecting:
            return "Setting up your private connection…"
        case .disconnected:
            return "Link your iPhone to your Centurion to get started"
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "How Your Centurion Thinks", icon: "brain.head.profile")

            AtmosphericSurface {
                VStack(spacing: Spacing.md) {
                    if connectionManager.connectionState == .connected {
                        CenturionStatusCard(
                            title: "Thinking service",
                            icon: "brain.head.profile",
                            headline: connectionManager.llmHealth.label,
                            detail: thinkingServiceDetail,
                            isPositive: !connectionManager.llmHealth.needsAttention,
                            accessibilityLabel: "Thinking service, \(connectionManager.llmHealth.label). \(thinkingServiceDetail)"
                        )
                        .task(id: connectionManager.connectionState) {
                            await connectionManager.refreshThinkingStatus()
                        }

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
                        Text("Link your Centurion first to see whether it can think properly.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Text("Change on your computer")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .padding(.horizontal, Spacing.xs)
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
            return "Your Centurion can answer messages."
        case .unknown:
            return "Checking with your Centurion…"
        default:
            return "Your Centurion may not be able to reply right now."
        }
    }
}

// MARK: - Pairing Sheet

struct ConnectionPairingSheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if connectionManager.connectionState == .connected {
                    connectedState
                } else if case .awaitingApproval(let message) = connectionManager.connectionState {
                    awaitingApprovalState(message: message)
                } else if connectionManager.discoveredDevices.isEmpty {
                    searchingState
                } else {
                    deviceList
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
            .onAppear {
                if connectionManager.connectionState != .connected {
                    connectionManager.startDiscovery()
                }
            }
        }
    }

    private var connectedState: some View {
        VStack(spacing: Spacing.lg) {
            SuccessMoment(
                title: "Linked to your Centurion",
                message: connectionManager.connectedDevice?.name
            )
            Button("Done") { dismiss() }
                .buttonStyle(CenturionPrimaryButtonStyle())
        }
        .padding()
    }

    private func awaitingApprovalState(message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            SheetHeader(title: "Approve on your Centurion", subtitle: message)
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.accent())
            Button("Try Again") {
                connectionManager.retryConnection()
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
        }
        .padding()
    }

    private var searchingState: some View {
        LoadingState(message: "Looking for your Centurion on your network…")
            .padding()
            .overlay(alignment: .bottom) {
                Text("Make sure your Centurion is running and both devices are on the same network.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
                    .padding()
            }
    }

    private var deviceList: some View {
        List {
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
                    .overlay(alignment: .trailing) {
                        if device.isConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ColorTheme.success())
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
