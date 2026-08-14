import SwiftUI

/// Privacy & difference explainer — secondary screen under You.
/// Arms clients to calmly rebuke common "AI is unsafe" claims with how Centurion differs.
struct SecurityHubView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTechnicalDetails = false
    @State private var showMessagingComparison = true

    private var isConnected: Bool {
        connectionManager.isCryptoChatReady
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()
                privacyHero
                differentiatorCard
                rebukeSection
                comparisonSection
                plainLanguageCard
                connectionCard
                zeroTrustCard

                if showTechnicalDetails {
                    technicalDetailsCard
                } else {
                    Button {
                        withAnimation(Motion.standard) {
                            showTechnicalDetails = true
                        }
                    } label: {
                        Text("Technical details")
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil().ignoresSafeArea()
            }
        )
        .navigationTitle("Privacy & Trust")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var privacyHero: some View {
        AtmosphericSurface(elevated: true, showRim: true) {
            VStack(spacing: Spacing.md) {
                ZStack {
                    MetallicRim(diameter: 96, opacity: 0.45)
                    Image(systemName: isConnected ? "lock.shield.fill" : "shield.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(isConnected ? ColorTheme.accent() : ColorTheme.mutedText())
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(height: 96)

                Text(isConnected
                     ? "Crypto Chat is on"
                     : "Private by design — even before you connect")
                    .font(Typography.screenTitle)
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)

                Text("Crypto Chat is your private encrypted conversation with your Sovereign. On home Wi‑Fi it stays on your network. Chat from anywhere keeps message content end-to-end encrypted while Centurion cloud only sees connection metadata — not your words.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity)
        }
        .shadow(
            color: Elevation.cardShadow(colorScheme: colorScheme),
            radius: Elevation.cardRadius,
            x: 0,
            y: Elevation.cardYOffset
        )
    }

    // MARK: - Why Sovereign is different

    private var differentiatorCard: some View {
        AtmosphericSurface(elevated: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "Why Sovereign is different", icon: "sparkles")

                Text("Most AI tools send your prompts to someone else's computers. Sovereign is your private AI — on your machine, under your control.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(4)

                CenturionReassuranceRow(
                    icon: "desktopcomputer",
                    title: "Runs on your Sovereign",
                    detail: "Your companion lives on your computer — not a shared public service that trains on strangers' chats."
                )
                CenturionReassuranceRow(
                    icon: "lock.shield.fill",
                    title: "Crypto Chat",
                    detail: "End-to-end encrypted talk with your Sovereign — content stays private; public AIs have nothing like it."
                )
                CenturionReassuranceRow(
                    icon: "house.fill",
                    title: "Home Wi‑Fi by default",
                    detail: "Pair once on your private network. No cloud account required for the home link."
                )
                CenturionReassuranceRow(
                    icon: "iphone.and.arrow.forward",
                    title: "Chat from anywhere (optional)",
                    detail: "When enabled on your Sovereign, the phone and Brain dial out through Centurion relay. Message bodies stay E2E encrypted; the cloud sees presence/routing metadata only."
                )
                CenturionReassuranceRow(
                    icon: "person.fill.checkmark",
                    title: "You stay in charge",
                    detail: "You set the mission, the Soul, and who may connect. Sovereign works for you — not the other way around."
                )
            }
        }
    }

    // MARK: - Arm clients against common claims

    private var rebukeSection: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "When someone says…", icon: "quote.bubble")

                Text("Use these calm answers when colleagues or leaders push back on AI. Sovereign is not \"another chatbot in the cloud.\"")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)

                rebukeCard(
                    claim: "\"That's too much of a security risk.\"",
                    answer: "Typical cloud AI sends your words to a company's servers. Sovereign runs on your computer. Home Crypto Chat stays on your network; Chat from anywhere keeps content end-to-end encrypted with only connection metadata on Centurion cloud — not a public chatbot training on your chats."
                )
                rebukeCard(
                    claim: "\"It's unsafe — anyone could read it.\"",
                    answer: "Your Remote link uses modern end-to-end encryption with perfect forward secrecy. Message content is not stored in a shared public inbox. On home Wi‑Fi there is no Centurion routing hop; away-from-home uses outbound relay for presence only — not readable transcripts."
                )
                rebukeCard(
                    claim: "\"AI will replace our jobs / we can't trust it.\"",
                    answer: "Sovereign is built for a 1:1 relationship with your private AI — to lift day-to-day pressure and help you live your mission. You stay the decision-maker. It is assistance under your control, not a black-box service owned by someone else."
                )
                rebukeCard(
                    claim: "\"We're not allowed to put company data in AI.\"",
                    answer: "That policy usually targets public cloud chatbots. With Sovereign, work stays on your machine and your network by design. You can show leadership this Privacy & Trust page — including how we compare to cloud AI and messaging apps."
                )
            }
        }
    }

    private func rebukeCard(claim: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(claim)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText())
                .italic()
            Text(answer)
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(3)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.accent().opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - Comparison (restored + expanded)

    private var comparisonSection: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "How we compare", icon: "arrow.left.arrow.right")

                Picker("Compare with", selection: $showMessagingComparison) {
                    Text("Cloud AI").tag(false)
                    Text("Messaging").tag(true)
                }
                .pickerStyle(.segmented)
                .tint(ColorTheme.accent())

                if showMessagingComparison {
                    Text("Privacy of the private link — how Sovereign AI Remote compares to popular messengers.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                    comparisonTable(
                        headers: ["", "Sovereign", "Signal", "Telegram"],
                        rows: [
                            ("End-to-end encrypted content", .full, .full, .partial),
                            ("No phone number required", .full, .none, .none),
                            ("Home link without cloud hop", .full, .none, .none),
                            ("Forward secrecy", .full, .full, .none),
                            ("Optional away relay (metadata only)", .partial, .none, .none),
                        ]
                    )
                } else {
                    Text("What changes when AI lives on your Sovereign instead of a public cloud chatbot.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                    comparisonTable(
                        headers: ["", "Sovereign", "Cloud AI"],
                        rows: [
                            ("Runs on your computer", .full, .none),
                            ("Private Crypto Chat remote", .full, .none),
                            ("No shared public chat cloud", .full, .none),
                            ("You own mission & Soul", .full, .none),
                            ("Works on home LAN without relay", .full, .none),
                        ]
                    )
                }

                HStack(spacing: Spacing.md) {
                    legendItem(level: .full, label: "Yes")
                    legendItem(level: .partial, label: "Partial")
                    legendItem(level: .none, label: "No")
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private enum SupportLevel { case full, partial, none }

    private func comparisonTable(
        headers: [String],
        rows: [(String, SupportLevel, SupportLevel, SupportLevel)]
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(headers[0])
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(headers.dropFirst().enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(Typography.sectionLabel)
                        .textCase(.uppercase)
                        .foregroundColor(ColorTheme.mutedText())
                        .frame(width: 68, alignment: .center)
                }
            }
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Text(row.0)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    supportDot(row.1, highlight: true)
                        .frame(width: 68)
                    supportDot(row.2, highlight: false)
                        .frame(width: 68)
                    supportDot(row.3, highlight: false)
                        .frame(width: 68)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func comparisonTable(
        headers: [String],
        rows: [(String, SupportLevel, SupportLevel)]
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(headers[0])
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(headers.dropFirst().enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(Typography.sectionLabel)
                        .textCase(.uppercase)
                        .foregroundColor(ColorTheme.mutedText())
                        .frame(width: 88, alignment: .center)
                }
            }
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Text(row.0)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    supportDot(row.1, highlight: true)
                        .frame(width: 88)
                    supportDot(row.2, highlight: false)
                        .frame(width: 88)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func supportDot(_ level: SupportLevel, highlight: Bool) -> some View {
        let color = highlight ? ColorTheme.accent() : ColorTheme.mutedText()
        return Group {
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
                    .foregroundColor(ColorTheme.mutedText().opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(level == .full ? "Yes" : level == .partial ? "Partial" : "No")
    }

    private func legendItem(level: SupportLevel, label: String) -> some View {
        HStack(spacing: 6) {
            supportDot(level, highlight: level == .full)
                .frame(width: 16)
            Text(label)
                .font(.caption2)
                .foregroundColor(ColorTheme.mutedText())
        }
    }

    // MARK: - Plain language

    private var plainLanguageCard: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "What this means for you", icon: "checkmark.shield")

                CenturionReassuranceRow(
                    icon: "house.fill",
                    title: "Home Wi‑Fi link",
                    detail: "On your network, messages travel between your iPhone and your Sovereign — not through a public messaging inbox."
                )
                CenturionReassuranceRow(
                    icon: "lock.fill",
                    title: "Encrypted conversations",
                    detail: "Your words are protected in transit, the same way banking apps protect your data."
                )
                CenturionReassuranceRow(
                    icon: "person.fill.checkmark",
                    title: "You stay in control",
                    detail: "No phone number and no social login for Crypto Chat. Optional Chat from anywhere uses Centurion relay for presence only — not readable message content."
                )
            }
        }
    }

    private var connectionCard: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "Connection", icon: "antenna.radiowaves.left.and.right")

                HStack(spacing: Spacing.md) {
                    StatusDot(isConnected: isConnected)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isConnected ? "Connected" : "Not connected")
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText())
                        Text(isConnected
                             ? "Your Sovereign is reachable (home Wi‑Fi or Chat from anywhere)."
                             : "Open You to link your Sovereign.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
            }
        }
    }

    private var zeroTrustCard: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "Built so we can't peek", icon: "hand.raised")

                Text("Sovereign has no backdoors and no ability to read your private link conversations — even if someone demanded it. The encryption is designed so that data simply is not available off your devices.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(4)

                CenturionReassuranceRow(
                    icon: "key.fill",
                    title: "Keys on your devices",
                    detail: "Encryption keys are generated on-device — not handed to a cloud admin."
                )
                CenturionReassuranceRow(
                    icon: "eye.slash.fill",
                    title: "Content stays on your side",
                    detail: "Home Crypto Chat has no Centurion routing hop. Away mode may see connection metadata so the link can find your Sovereign — not your message text."
                )
                CenturionReassuranceRow(
                    icon: "checkmark.seal.fill",
                    title: "Proven crypto building blocks",
                    detail: "Built on open, well-studied cryptography (the same family used by serious secure products)."
                )
            }
        }
    }

    private var technicalDetailsCard: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CenturionSectionHeader(title: "Technical details", icon: "key.fill")

                Text("X25519 key exchange, XSalsa20-Poly1305 authenticated encryption, and perfect forward secrecy on each session.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(4)

                Text("Discovery uses mDNS on your local network for home pairing. Chat from anywhere uses outbound Centurion relay for presence — not DIY port-forward.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())

                Text("Library: libsodium (NaCl). Ephemeral session keys are never persisted for the private link.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
    }
}
