import SwiftUI

/// Privacy reassurance — plain language first, technical details on request.
struct SecurityHubView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var showTechnicalDetails = false

    var body: some View {
        TabPageChrome(title: "Privacy") {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    privacyHero
                    plainLanguageCard
                    connectionCard

                    if showTechnicalDetails {
                        technicalDetailsCard
                    } else {
                        Button {
                            withAnimation(Motion.standard) {
                                showTechnicalDetails = true
                            }
                        } label: {
                            Text("Technical details")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(ColorTheme.accent())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                    }
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Hero

    private var privacyHero: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: connectionManager.connectionState == .connected
                  ? "lock.shield.fill" : "shield.fill")
                .font(.system(size: 52))
                .foregroundColor(connectionManager.connectionState == .connected
                    ? ColorTheme.accent() : ColorTheme.mutedText())

            Text(connectionManager.connectionState == .connected
                 ? "Your connection is private"
                 : "Connect to enable private messaging")
                .font(.title3.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)

            Text("Your Centurion talks to this iPhone directly on your network. No cloud account required.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Plain language

    private var plainLanguageCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "What this means for you", icon: "checkmark.shield")

            reassuranceRow(
                icon: "house.fill",
                title: "Stays on your network",
                detail: "Messages travel between your iPhone and your Centurion — not through a public server."
            )
            reassuranceRow(
                icon: "lock.fill",
                title: "Encrypted conversations",
                detail: "Your words are protected in transit, the same way banking apps protect your data."
            )
            reassuranceRow(
                icon: "person.fill.checkmark",
                title: "You stay in control",
                detail: "No phone number, no social login, no company reading your messages."
            )
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Connection", icon: "antenna.radiowaves.left.and.right")

            HStack(spacing: Spacing.md) {
                StatusDot(isConnected: connectionManager.connectionState == .connected)
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionManager.connectionState == .connected ? "Connected" : "Not connected")
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())
                    Text(connectionManager.connectionState == .connected
                         ? "Your Centurion is reachable on your local network."
                         : "Open the Connect tab to link your Centurion.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var technicalDetailsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Technical details", icon: "key.fill")

            Text("X25519 key exchange, XSalsa20-Poly1305 authenticated encryption, and perfect forward secrecy on each session.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(4)

            Text("Discovery uses mDNS on your local network. No central registry.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func reassuranceRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(ColorTheme.accent())
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)
            }
        }
    }
}
