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
        NavigationStack {
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
                .padding()
            }
            .background(ColorTheme.background())
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    // MARK: - Trust Statement

    private var trustStatement: some View {
        VStack(spacing: 6) {
            Text("Your Centurion stays reliable when your iPhone is linked to your Centurion.")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)

            Text("This shows whether your iPhone is linked and whether your Centurion can think properly.")
                .font(.system(size: 13))
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    // MARK: - Device Link Card

    private var deviceLinkCard: some View {
        statusCard(
            title: "Device link",
            icon: "antenna.radiowaves.left.and.right",
            headline: deviceLinkHeadline,
            detail: deviceLinkDetail,
            dotColor: deviceLinkDotColor,
            accessibilityLabel: "Device link, \(deviceLinkHeadline). \(deviceLinkDetail)"
        )
    }

    // MARK: - Thinking Service Card

    private var thinkingServiceCard: some View {
        statusCard(
            title: "Thinking service",
            icon: "brain.head.profile",
            headline: connectionManager.llmHealth.label,
            detail: thinkingServiceDetail,
            dotColor: thinkingDotColor,
            accessibilityLabel: "Thinking service, \(connectionManager.llmHealth.label). \(thinkingServiceDetail)"
        )
        .task {
            await connectionManager.refreshThinkingStatus()
        }
    }

    private func statusCard(
        title: String,
        icon: String,
        headline: String,
        detail: String,
        dotColor: Color,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: title, icon: icon)

            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())

                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.border(), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Primary CTA (one filled button)

    @ViewBuilder
    private var primaryActionButton: some View {
        if connectionManager.connectionState != .connected {
            Button {
                Haptics.lightTap()
                showPairingSheet = true
            } label: {
                Text("Find my Centurion")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .accessibilityLabel("Find my Centurion")
        } else if connectionManager.llmHealth.needsAttention {
            Button {
                Haptics.lightTap()
                showRecoverySheet = true
            } label: {
                Text("Fix Thinking Service")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .accessibilityLabel("Fix Thinking Service")
        }
    }

    private var supportLinks: some View {
        HStack(spacing: Spacing.lg) {
            Button {
                showGetHelp = true
            } label: {
                Text("Get Help")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
            }
            .accessibilityLabel("Get Help")

            AdrianLink(showAdrian: $showAdrian)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Reassurance

    private var reassuranceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your Privacy", icon: "lock.shield")

            Text("Your Centurion runs on your network. Conversations stay between you and your Centurion — not on a public cloud.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(4)
        }
    }

    // MARK: - Copy helpers

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

    private var deviceLinkDotColor: Color {
        switch connectionManager.connectionState {
        case .connected: return ColorTheme.success()
        case .error: return ColorTheme.error()
        case .awaitingApproval: return ColorTheme.accent()
        default: return ColorTheme.mutedText()
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

    private var thinkingDotColor: Color {
        switch connectionManager.llmHealth {
        case .healthy: return ColorTheme.success()
        case .degraded: return .orange
        case .broken, .unknown: return ColorTheme.error()
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
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(ColorTheme.success())

            Text("Linked to your Centurion")
                .font(.title2.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText())

            if let device = connectionManager.connectedDevice {
                Text(device.name)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }

            Button("Done") { dismiss() }
                .buttonStyle(AmberButtonStyle())
                .padding(.top, Spacing.md)
        }
        .padding()
    }

    private func awaitingApprovalState(message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(ColorTheme.accent())

            Text("Approve on your Centurion")
                .font(.title2.weight(.semibold))

            Text(message)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)

            Button("Try Again") {
                connectionManager.retryConnection()
            }
            .buttonStyle(AmberButtonStyle())
        }
        .padding()
    }

    private var searchingState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Looking for your Centurion…")
                .font(.headline)

            Text("Make sure your Centurion is running and both devices are on the same network.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var deviceList: some View {
        List {
            ForEach(connectionManager.discoveredDevices) { device in
                Button {
                    connectionManager.connect(to: device)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            Text(device.hostname.isEmpty ? "On your network" : device.hostname)
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                        }
                        Spacer()
                        if device.isConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ColorTheme.success())
                        }
                    }
                }
            }
        }
    }
}
