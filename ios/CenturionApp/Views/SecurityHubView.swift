import SwiftUI

/// Security Hub — every privacy and encryption detail, front and centre.
/// Designed to answer "how is this better than Signal/Telegram?" before the user asks.
struct SecurityHubView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var showCryptoDetail = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero shield
                    securityHero
                    
                    // Connection security
                    connectionSecurityCard
                    
                    // Encryption details
                    encryptionDetailsCard
                    
                    // Comparison table
                    comparisonCard
                    
                    // Zero trust explanation
                    zeroTrustCard
                    
                    // Technical details
                    if showCryptoDetail {
                        cryptoDetailCard
                    }
                    
                    Button(showCryptoDetail ? "Hide Technical Details" : "Show Technical Details") {
                        withAnimation { showCryptoDetail.toggle() }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Security")
        }
    }
    
    private var securityHero: some View {
        VStack(spacing: 16) {
            Image(systemName: connectionManager.connectionState == .connected
                  ? "lock.shield.fill" : "shield.fill")
                .font(.system(size: 60))
                .foregroundColor(connectionManager.connectionState == .connected ? .green : .secondary)
            
            Text("Your Centurion connection is")
                .font(.title3)
            
            Text(connectionManager.connectionState == .connected ? "SECURE" : "NOT CONNECTED")
                .font(.largeTitle)
                .fontWeight(.black)
                .foregroundColor(connectionManager.connectionState == .connected ? .green : .secondary)
            
            if connectionManager.connectionState == .connected {
                Text("X25519 + XSalsa20-Poly1305 • Perfect Forward Secrecy")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var connectionSecurityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connection Security", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            
            VStack(spacing: 12) {
                securityRow(
                    icon: "wifi",
                    iconColor: .green,
                    title: "Local Network (LAN)",
                    detail: "Direct connection to your Centurion. Zero internet required. Zero cloud dependency. Physically unreachable from outside your network."
                )
                
                securityRow(
                    icon: "shield.fill",
                    iconColor: .blue,
                    title: "Tailscale Tunnel (Remote)",
                    detail: "WireGuard-based tunnel when away from home. No open ports, no VPN configuration, no third-party routing."
                )
                
                securityRow(
                    icon: "magnifyingglass.circle.fill",
                    iconColor: .orange,
                    title: "No Server Discovery",
                    detail: "Centurions are discovered via mDNS/Bonjour on your local network. No cloud registry, no central directory, no phone-home."
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var encryptionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Encryption", systemImage: "key.fill")
                .font(.headline)
            
            VStack(spacing: 12) {
                securityRow(
                    icon: "1.circle.fill",
                    iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                    title: "X25519 Key Exchange",
                    detail: "Curve25519 ECDH — the same elliptic curve cryptography used by WireGuard, Signal, and Apple's iMessage. NSA-resistant."
                )
                
                securityRow(
                    icon: "2.circle.fill",
                    iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                    title: "XSalsa20-Poly1305 Encryption",
                    detail: "Authenticated encryption with fast stream cipher. Each message gets a unique nonce. Tamper-proof and eavesdrop-proof."
                )
                
                securityRow(
                    icon: "3.circle.fill",
                    iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                    title: "Perfect Forward Secrecy",
                    detail: "Every session generates fresh ephemeral keys. Compromising today's key cannot decrypt yesterday's messages. Even we can't go back and read old conversations."
                )
                
                securityRow(
                    icon: "4.circle.fill",
                    iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                    title: "Zero Server Metadata",
                    detail: "Unlike every other messaging platform, Centurion has no routing server. There is no log of who talked to who, when, or how much data moved. That metadata literally cannot exist."
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("How We Compare", systemImage: "arrow.left.arrow.right")
                .font(.headline)
            
            VStack(spacing: 0) {
                comparisonRow(feature: "End-to-end encrypted", centurion: "✅ Always", signal: "✅ Yes", telegram: "⚠️ Secret chats")
                Divider().padding(.leading, 100)
                comparisonRow(feature: "Zero server metadata", centurion: "✅ Yes", signal: "❌ Has phone#", telegram: "❌ Has IP")
                Divider().padding(.leading, 100)
                comparisonRow(feature: "Forward secrecy", centurion: "✅ Yes", signal: "✅ Yes", telegram: "❌ No")
                Divider().padding(.leading, 100)
                comparisonRow(feature: "No cloud dependency", centurion: "✅ Yes", signal: "❌ Needs servers", telegram: "❌ Needs servers")
                Divider().padding(.leading, 100)
                comparisonRow(feature: "No phone number required", centurion: "✅ Yes", signal: "❌ Required", telegram: "❌ Required")
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var zeroTrustCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Zero Trust Architecture", systemImage: "hand.raised.fill")
                .font(.headline)
            
            Text("Centurion has no backdoors, no admin access to your data, and no ability to read your conversations — even if compelled by law enforcement.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                trustRow("All encryption keys generated on-device")
                trustRow("No cloud backup of keys (optional local export)")
                trustRow("Open source cryptographic library (libsodium)")
                trustRow("Auditable: the entire crypto stack is ~500 lines of Swift")
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var cryptoDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Technical Specifications", systemImage: "doc.text.fill")
                .font(.headline)
            
            Group {
                detailRow("Key Exchange", "X25519 (Curve25519 ECDH)")
                detailRow("Encryption", "XSalsa20-Poly1305")
                detailRow("Nonce Size", "24 bytes (192 bits)")
                detailRow("Key Size", "32 bytes (256 bits)")
                detailRow("Auth Tag", "Poly1305 (16 bytes)")
                detailRow("Library", "libsodium (NaCl)")
                detailRow("PFS", "Ephemeral session keys, never persisted")
                detailRow("Transport", "TCP over LAN or WireGuard (Tailscale)")
                detailRow("Discovery", "mDNS/Bonjour (_centurion._tcp)")
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func securityRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
    }
    
    private func comparisonRow(feature: String, centurion: String, signal: String, telegram: String) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .frame(width: 100, alignment: .leading)
                .fontWeight(.medium)
            Text(centurion)
                .frame(width: 60, alignment: .center)
                .foregroundColor(.green)
            Text(signal)
                .frame(width: 60, alignment: .center)
            Text(telegram)
                .frame(width: 70, alignment: .center)
        }
        .padding(.vertical, 6)
    }
    
    private func trustRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
        }
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
        }
    }
}
