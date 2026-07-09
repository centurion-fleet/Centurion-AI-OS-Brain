import SwiftUI

/// The pairing ceremony — your iPhone discovers and connects to your Centurion
/// like a remote control finding its console. Signal bars, encrypted handshake,
/// and a warm amber glow when connected.
///
/// Remote Control theme: This is the moment your remote finds its brain.
/// Concentric signal rings represent the mDNS broadcast, the encrypted handshake
/// is the pairing ceremony, and the connected state means your remote is live.
struct ConnectionView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var signalBarAnimation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Brand header
                    BrandHeader()
                        .padding(.bottom, Spacing.sm)

                    // Remote Control hero
                    remoteControlHero

                    // Signal bars — visual remote-control strength indicator
                    if case .discovering = connectionManager.connectionState {
                        signalBars
                    }

                    // Discovered devices
                    if !connectionManager.discoveredDevices.isEmpty {
                        deviceList
                    }

                    // When connected — show the remote control is live
                    if case .connected = connectionManager.connectionState {
                        remoteControlActiveCard
                    }

                    // Info section
                    infoSection
                }
                .padding()
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if connectionManager.discoveredDevices.isEmpty
                    && connectionManager.connectionState == .disconnected {
                    connectionManager.startDiscovery()
                }
            }
        }
    }

    // MARK: - Remote Control Hero

    private var remoteControlHero: some View {
        VStack(spacing: 16) {
            // Signal strength icon — changes with connection state
            ZStack {
                // Outer glow ring when connected
                if case .connected = connectionManager.connectionState {
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(signalBarAnimation ? 1.1 : 0.95)
                }

                Image(systemName: connectionIcon)
                    .font(.system(size: 44))
                    .foregroundColor(connectionColor)
            }

            Text(connectionTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText())

            Text(connectionDescription)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if case .connected = connectionManager.connectionState {
                // Remote Control active badge
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                    Text("X25519 + XSalsa20-Poly1305")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            }

            if case .discovering = connectionManager.connectionState {
                ProgressView()
                    .tint(ColorTheme.accent())
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(connectionColor.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                signalBarAnimation = true
            }
        }
    }

    // MARK: - Signal Bars

    private var signalBars: some View {
        VStack(spacing: 8) {
            Text("SIGNAL STRENGTH")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(ColorTheme.mutedText())
                .tracking(3)

            HStack(spacing: 4) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ColorTheme.accent())
                        .frame(width: 4, height: CGFloat(8 + i * 6))
                        .opacity(signalBarAnimation ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6).delay(Double(i) * 0.15).repeatForever(autoreverses: true),
                            value: signalBarAnimation
                        )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.border(), lineWidth: 0.5)
        )
    }

    // MARK: - Device List

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Discovered Centurions")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
            }

            ForEach(connectionManager.discoveredDevices) { device in
                Button(action: { connectionManager.connect(to: device) }) {
                    HStack(spacing: 14) {
                        // Globe icon
                        ZStack {
                            Circle()
                                .fill(ColorTheme.accent().opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "cpu")
                                .font(.system(size: 16))
                                .foregroundColor(ColorTheme.accent())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(ColorTheme.primaryText())

                            HStack(spacing: 4) {
                                Image(systemName: device.connectionMethod == .lan
                                      ? "wifi" : "shield.fill")
                                    .font(.system(size: 8))
                                Text("\(device.connectionMethod.rawValue.uppercased()) • \(device.hostname)")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundColor(ColorTheme.mutedText())
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                            Text("PAIR")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(ColorTheme.accent())
                                .tracking(2)
                        }
                    }
                    .padding()
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(ColorTheme.border(), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Remote Control Active

    private var remoteControlActiveCard: some View {
        VStack(spacing: 16) {
            // Animated signal ring
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(signalBarAnimation ? 1.15 : 0.9)

                Circle()
                    .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 60, height: 60)
                    .scaleEffect(signalBarAnimation ? 1.1 : 0.95)

                Image(systemName: "app.connected.to.app.below.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
            }

            Text("Remote Control Active")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())

            Text("Your iPhone is securely paired with your Centurion")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)

            if let device = connectionManager.connectedDevice {
                HStack(spacing: 12) {
                    remoteDetail("Connection", device.connectionMethod.rawValue.uppercased())
                    remoteDetail("Encryption", "X25519 + XSalsa20")
                    remoteDetail("Latency", "< 1ms")
                }
                .font(.system(size: 9, design: .monospaced))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    private func remoteDetail(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .foregroundColor(ColorTheme.mutedText())
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText())
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())

            VStack(alignment: .leading, spacing: 8) {
                privacyRow("Direct Connection", "Your iPhone talks directly to your Centurion. No cloud servers, no intermediaries.")
                privacyRow("End-to-End Encrypted", "Messages are encrypted with X25519 + XSalsa20-Poly1305 before they leave your phone.")
                privacyRow("No Metadata", "There is no routing server. No logs of who talked to who, when, or how much.")
                privacyRow("Forward Secrecy", "Every session generates fresh ephemeral keys. Today's keys can't decrypt yesterday's messages.")
            }
            .font(.caption)
            .foregroundColor(ColorTheme.mutedText())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.border(), lineWidth: 0.5)
        )
    }

    private func privacyRow(_ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primaryText())
                Text(description)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
    }

    // MARK: - Connection State Helpers

    private var connectionIcon: String {
        switch connectionManager.connectionState {
        case .connected: return "app.connected.to.app.below.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .discovering: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "antenna.radiowaves.left.and.right"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var connectionColor: Color {
        switch connectionManager.connectionState {
        case .connected: return .green
        case .connecting, .discovering: return ColorTheme.accent()
        case .disconnected: return ColorTheme.mutedText()
        case .error: return .red
        }
    }

    private var connectionTitle: String {
        switch connectionManager.connectionState {
        case .connected: return "Remote Active"
        case .connecting: return "Handshaking…"
        case .discovering: return "Scanning for Centurions"
        case .disconnected: return "Not Paired"
        case .error(let msg): return msg
        }
    }

    private var connectionDescription: String {
        switch connectionManager.connectionState {
        case .connected: return "Your remote control is live. All communication is encrypted end-to-end."
        case .connecting: return "Establishing encrypted channel with your Centurion"
        case .discovering: return "Looking for Centurion devices on your network via Bonjour"
        case .disconnected: return "Your Centurion will appear here when detected on your network"
        case .error: return "Try again or check that your Centurion is running"
        }
    }
}
