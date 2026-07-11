import SwiftUI

/// Connection Hub — the trust layer of the app.
///
/// When LLM connections or the remote link break, users should see the real state
/// here instead of blaming their Centurion.
struct ConnectionView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var showPairingSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    trustStatement

                    remoteConnectionSection

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
        }
    }

    // MARK: - Trust Statement

    private var trustStatement: some View {
        VStack(spacing: 6) {
            Text("Your Centurion stays reliable when your iPhone is linked to your Centurion.")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)

            Text("This shows whether your iPhone is linked to your Centurion.")
                .font(.system(size: 13))
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    // MARK: - Remote Connection

    private var remoteConnectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your private connection", icon: "antenna.radiowaves.left.and.right")

            Text("The link between this iPhone and your Centurion.")
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())

            HStack(spacing: Spacing.md) {
                StatusDot(isConnected: connectionManager.connectionState == .connected)

                VStack(alignment: .leading, spacing: 4) {
                    Text(remoteStatusTitle)
                        .font(.headline)
                        .foregroundColor(remoteStatusColor)

                    Text(remoteStatusDetail)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Haptics.lightTap()
                    if case .awaitingApproval = connectionManager.connectionState {
                        connectionManager.retryConnection()
                    } else {
                        showPairingSheet = true
                    }
                } label: {
                    Text(remoteActionLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ColorTheme.accent())
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )
        }
    }

    private var remoteStatusTitle: String {
        switch connectionManager.connectionState {
        case .connected:    return "Connected"
        case .discovering:  return "Looking for your Centurion"
        case .connecting:   return "Connecting"
        case .disconnected: return "Disconnected"
        case .awaitingApproval: return "Waiting for approval"
        case .error:        return "Connection Issue"
        }
    }

    private var remoteStatusDetail: String {
        switch connectionManager.connectionState {
        case .connected:
            if let device = connectionManager.connectedDevice {
                return "Securely linked to \(device.name)"
            }
            return "Your iPhone is securely linked to your Centurion"
        case .discovering:
            return "Looking for your Centurion on the local network"
        case .connecting:
            return "Setting up your private connection…"
        case .disconnected:
            return "Tap Connect to pair with your Centurion"
        case .awaitingApproval(let message):
            return message
        case .error(let message):
            return message
        }
    }

    private var remoteStatusColor: Color {
        switch connectionManager.connectionState {
        case .connected: return ColorTheme.success()
        case .error:     return ColorTheme.error()
        case .awaitingApproval: return ColorTheme.accent()
        default:         return ColorTheme.mutedText()
        }
    }

    private var remoteActionLabel: String {
        switch connectionManager.connectionState {
        case .connected: return "Manage"
        case .awaitingApproval: return "Try Again"
        default:         return "Connect"
        }
    }

    // MARK: - Reassurance

    private var reassuranceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your Privacy", icon: "lock.shield")

            Text("Your Centurion runs on your network. Conversations stay between you and your Centurion — not on a public cloud.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(4)

            Text("For advanced options, including how your Centurion thinks, open Settings.")
                .font(.caption)
                .foregroundColor(ColorTheme.dimAccent())
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
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.success())

            Text("Connected")
                .font(.title2.weight(.semibold))

            if let device = connectionManager.connectedDevice {
                Text(device.name)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }

            Button(role: .destructive) {
                connectionManager.disconnect()
                Haptics.mediumTap()
            } label: {
                Text("Disconnect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding()
    }

    private func awaitingApprovalState(message: String) -> some View {
        ContentUnavailableView {
            Label("Waiting for approval", systemImage: "hourglass")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                connectionManager.retryConnection()
                Haptics.lightTap()
            }
            .buttonStyle(AmberButtonStyle())
        }
    }

    private var searchingState: some View {
        ContentUnavailableView {
            Label("Looking for your Centurion", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Make sure your Centurion is running on the same Wi‑Fi. We look for it automatically — no account needed.")
        } actions: {
            if case .discovering = connectionManager.connectionState {
                ProgressView()
                    .padding(.top, Spacing.sm)
            } else {
                Button("Search Again") {
                    connectionManager.startDiscovery()
                }
                .buttonStyle(AmberButtonStyle())
            }
        }
    }

    private var deviceList: some View {
        List(connectionManager.discoveredDevices) { device in
            Button {
                connectionManager.connect(to: device)
                Haptics.connectionEstablished()
            } label: {
                HStack {
                    Image(systemName: device.connectionMethod.icon)
                        .foregroundColor(ColorTheme.accent())
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText())
                        Text("Local network")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    Spacer()

                    if connectionManager.connectionState == .connecting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Dial Style LLM Selector

struct LLMProviderDial: View {
    @Binding var selectedProvider: LLMProvider

    private let providers = LLMProvider.allCases

    var body: some View {
        VStack(spacing: Spacing.md) {
            GeometryReader { geometry in
                let segmentWidth = geometry.size.width / CGFloat(providers.count)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ColorTheme.surface(),
                                    ColorTheme.accent().opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 18)
                        .fill(ColorTheme.accent().opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(ColorTheme.accent().opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: segmentWidth - 8, height: geometry.size.height - 8)
                        .offset(x: selectionOffset(segmentWidth: segmentWidth) + 4)
                        .animation(Motion.standard, value: selectedProvider)

                    HStack(spacing: 0) {
                        ForEach(providers) { provider in
                            dialSegment(for: provider)
                                .frame(width: segmentWidth)
                        }
                    }
                }
            }
            .frame(height: 108)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )

            prairieIndicator
        }
    }

    private func selectionOffset(segmentWidth: CGFloat) -> CGFloat {
        CGFloat(providers.firstIndex(of: selectedProvider) ?? 0) * segmentWidth
    }

    private func dialSegment(for provider: LLMProvider) -> some View {
        Button {
            guard selectedProvider != provider else { return }
            withAnimation(Motion.standard) {
                selectedProvider = provider
            }
            Haptics.lightTap()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(provider.status.color.opacity(selectedProvider == provider ? 0.18 : 0.08))
                        .frame(width: 34, height: 34)

                    Text(provider.shortLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(
                            selectedProvider == provider
                                ? ColorTheme.accent()
                                : ColorTheme.mutedText()
                        )
                }

                Text(provider.displayName)
                    .font(.system(size: 12, weight: selectedProvider == provider ? .semibold : .medium))
                    .foregroundColor(
                        selectedProvider == provider
                            ? ColorTheme.primaryText()
                            : ColorTheme.mutedText()
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 4) {
                    Circle()
                        .fill(provider.status.color)
                        .frame(width: 6, height: 6)
                    Text(provider.status.label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(provider.status.color)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.displayName), \(provider.status.label)")
        .accessibilityAddTraits(selectedProvider == provider ? .isSelected : [])
    }

    private var prairieIndicator: some View {
        HStack(spacing: 0) {
            ForEach(providers) { provider in
                Rectangle()
                    .fill(
                        selectedProvider == provider
                            ? ColorTheme.accent()
                            : ColorTheme.border().opacity(0.5)
                    )
                    .frame(height: selectedProvider == provider ? 2 : 1)
                    .frame(maxWidth: .infinity)
                    .animation(Motion.light, value: selectedProvider)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Status Detail

struct LLMStatusDetail: View {
    let provider: LLMProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)

                if provider.isRecommended {
                    Text("RECOMMENDED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorTheme.accent())
                        .clipShape(Capsule())
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(provider.status.color)
                        .frame(width: 8, height: 8)
                    Text(provider.status.label.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(provider.status.color)
                }
            }

            Text(provider.description)
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())

            if let reassurance = provider.status.reassurance {
                Text(reassurance)
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundColor(provider.status == .broken ? ColorTheme.error() : .orange)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.border(), lineWidth: 0.5)
        )
        .animation(Motion.light, value: provider)
    }
}
