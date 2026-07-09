import SwiftUI

/// Security Hub — every privacy and encryption detail, front and centre.
/// Designed to answer "how is this better than Signal/Telegram?" before the user asks.
/// Award-winning visual language: calm, minimal, amber-tinted, no emoji text.
struct SecurityHubView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var showCryptoDetail = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Brand header
                    BrandHeader()
                        .padding(.bottom, Spacing.xs)

                    // Hero shield
                    securityHero

                    // Connection security
                    connectionSecurityCard

                    // Encryption details
                    encryptionDetailsCard

                    // Comparison — card-based, no table, no emoji text
                    comparisonSection

                    // Zero trust explanation
                    zeroTrustCard

                    // Technical specifications
                    cryptoFooter
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Security")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Hero
    
    private var securityHero: some View {
        VStack(spacing: 16) {
            Image(systemName: connectionManager.connectionState == .connected
                  ? "lock.shield.fill" : "shield.fill")
                .font(.system(size: 56))
                .foregroundColor(connectionManager.connectionState == .connected
                    ? ColorTheme.accent() : ColorTheme.mutedText())
            
            Text("Your Centurion connection is")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
            
            Text(connectionManager.connectionState == .connected ? "SECURE" : "NOT CONNECTED")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(connectionManager.connectionState == .connected
                    ? ColorTheme.accent() : ColorTheme.mutedText())
            
            if connectionManager.connectionState == .connected {
                Text("X25519 + XSalsa20-Poly1305 • PFS")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Connection Security
    
    private var connectionSecurityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Connection Security", icon: "antenna.radiowaves.left.and.right")
            
            VStack(spacing: 12) {
                detailRow(
                    icon: "wifi",
                    iconColor: ColorTheme.accent(),
                    title: "Local Network (LAN)",
                    detail: "Direct connection to your Centurion. Zero internet. Zero cloud. Physically unreachable from outside your network."
                )
                
                detailRow(
                    icon: "lock.shield",
                    iconColor: ColorTheme.accent(),
                    title: "No Server Discovery",
                    detail: "Centurions discovered via mDNS/Bonjour on your local network. No cloud registry, no central directory."
                )
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Encryption Details
    
    private var encryptionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Encryption Stack", icon: "key.fill")
            
            VStack(spacing: 12) {
                stepRow(number: 1, title: "X25519 Key Exchange",
                        detail: "Curve25519 ECDH — the same elliptic curve cryptography used by WireGuard, Signal, and Apple's iMessage.")
                
                stepRow(number: 2, title: "XSalsa20-Poly1305",
                        detail: "Authenticated encryption with a unique nonce per message. Tamper-proof and eavesdrop-proof.")
                
                stepRow(number: 3, title: "Perfect Forward Secrecy",
                        detail: "Every session generates fresh ephemeral keys. Today's key cannot decrypt yesterday's messages.")
                
                stepRow(number: 4, title: "Zero Server Metadata",
                        detail: "No routing server. No logs of who talked to who, when, or how much. That metadata cannot exist.")
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Comparison (replaces old emoji table)
    
    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("How We Compare", icon: "arrow.left.arrow.right")
            
            VStack(spacing: 0) {
                // Column header row
                HStack(spacing: 0) {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    headerLabel("Centurion")
                    headerLabel("Signal")
                    headerLabel("Telegram")
                }
                .padding(.bottom, 8)
                
                Divider()
                    .padding(.bottom, 4)
                
                // Feature rows
                compareRow(feature: "End-to-end encrypted",
                           centurion: .full, signal: .full, telegram: .partial)
                compareRow(feature: "Zero server metadata",
                           centurion: .full, signal: .none, telegram: .none)
                compareRow(feature: "Forward secrecy",
                           centurion: .full, signal: .full, telegram: .none)
                compareRow(feature: "No cloud dependency",
                           centurion: .full, signal: .none, telegram: .none)
                compareRow(feature: "No phone number required",
                           centurion: .full, signal: .none, telegram: .none)
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func headerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .textCase(.uppercase)
            .foregroundColor(ColorTheme.mutedText())
            .frame(width: 68, alignment: .center)
    }
    
    private enum SupportLevel { case full, partial, none }
    
    private func compareRow(feature: String, centurion: SupportLevel, signal: SupportLevel, telegram: SupportLevel) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            supportDot(centurion, color: ColorTheme.accent())
                .frame(width: 68, alignment: .center)
            supportDot(signal, color: ColorTheme.mutedText())
                .frame(width: 68, alignment: .center)
            supportDot(telegram, color: ColorTheme.mutedText())
                .frame(width: 68, alignment: .center)
        }
        .padding(.vertical, 8)
    }
    
    private func supportDot(_ level: SupportLevel, color: Color) -> some View {
        Group {
            switch level {
            case .full:
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            case .partial:
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            case .none:
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ColorTheme.mutedText().opacity(0.5))
            }
        }
    }
    
    // MARK: - Zero Trust
    
    private var zeroTrustCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Zero Trust Architecture", icon: "hand.raised")
            
            Text("Centurion has no backdoors, no admin access to your data, and no ability to read your conversations — even if compelled.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 6) {
                trustRow("Encryption keys generated on-device")
                trustRow("No cloud backup of keys")
                trustRow("Open source (libsodium)")
                trustRow("Auditable crypto stack — ~500 lines of Swift")
            }
            .font(.caption)
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Technical Footer
    
    private var cryptoFooter: some View {
        VStack(spacing: 8) {
            Button(showCryptoDetail ? "Hide Technical Details" : "Show Technical Details") {
                withAnimation { showCryptoDetail.toggle() }
            }
            .font(.caption)
            .foregroundColor(ColorTheme.accent())
            
            if showCryptoDetail {
                VStack(spacing: 6) {
                    specRow("Key Exchange", "X25519 (Curve25519 ECDH)")
                    specRow("Encryption", "XSalsa20-Poly1305")
                    specRow("Nonce Size", "24 bytes (192 bits)")
                    specRow("Key Size", "32 bytes (256 bits)")
                    specRow("Auth Tag", "Poly1305 (16 bytes)")
                    specRow("Library", "libsodium (NaCl)")
                    specRow("PFS", "Ephemeral keys, never persisted")
                    specRow("Transport", "TCP over LAN (mDNS/Bonjour)")
                }
                .font(.caption)
                .padding()
                .background(ColorTheme.accent().opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Shared Components
    
    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
            Text(text)
                .font(.headline)
        }
    }
    
    private func detailRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.15))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ColorTheme.accent())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func trustRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ColorTheme.accent())
            Text(text)
                .foregroundColor(.secondary)
        }
    }
    
    private func specRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
                .font(.caption)
        }
    }
}
