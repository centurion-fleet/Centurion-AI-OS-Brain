import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection status card
                    connectionStatusCard
                    
                    // Discovered devices
                    if !connectionManager.discoveredDevices.isEmpty {
                        deviceList
                    }
                    
                    // Info section
                    infoSection
                }
                .padding()
            }
            .navigationTitle("Connect")
            .onAppear {
                if connectionManager.discoveredDevices.isEmpty
                    && connectionManager.connectionState == .disconnected {
                    connectionManager.startDiscovery()
                }
            }
        }
    }
    
    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            Image(systemName: connectionIcon)
                .font(.system(size: 48))
                .foregroundColor(connectionColor)
            
            Text(connectionTitle)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(connectionDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if connectionManager.connectionState == .discovering {
                ProgressView()
            }
            
            if connectionManager.connectionState == .connected,
               let device = connectionManager.connectedDevice {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Encrypted • \(device.connectionMethod.rawValue.uppercased())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Centurions")
                .font(.headline)
            
            ForEach(connectionManager.discoveredDevices) { device in
                Button(action: { connectionManager.connect(to: device) }) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("\(device.connectionMethod.rawValue.uppercased()) • \(device.hostname)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your privacy")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                privacyRow("End-to-end encrypted", "Messages are encrypted before they leave your phone")
                privacyRow("No cloud dependency", "Connects directly to your Centurion, no servers involved")
                privacyRow("Zero metadata", "No one can see who you talk to, when, or how much")
                privacyRow("Tailscale away from home", "Secure WireGuard tunnel when you're on the go")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func privacyRow(_ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(description)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var connectionIcon: String {
        switch connectionManager.connectionState {
        case .connected: return "lock.shield.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .discovering: return "magnifyingglass"
        case .disconnected: return "antenna.radiowaves.left.and.right"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    private var connectionColor: Color {
        switch connectionManager.connectionState {
        case .connected: return .green
        case .connecting, .discovering: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .disconnected: return .secondary
        case .error: return .red
        }
    }
    
    private var connectionTitle: String {
        switch connectionManager.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .discovering: return "Scanning your network…"
        case .disconnected: return "Not Connected"
        case .error(let msg): return msg
        }
    }
    
    private var connectionDescription: String {
        switch connectionManager.connectionState {
        case .connected: return "Your connection to your Centurion is secure and private"
        case .connecting: return "Establishing encrypted channel with your Centurion"
        case .discovering: return "Looking for Centurion devices on your network"
        case .disconnected: return "Tap a device below to connect"
        case .error: return "Try again or check that your Centurion is running"
        }
    }
}
