import SwiftUI

/// Unified support entry — Support Code generation and safe automatic recovery.
struct GetHelpView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var supportCode = ""
    @State private var supportSummary = ""
    @State private var statusMessage = ""
    @State private var isWorking = false
    @State private var didGenerateCode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    FullBrandHeader()

                    introSection

                    if !supportCode.isEmpty {
                        supportCodeSection
                    }

                    actionButtons

                    if !statusMessage.isEmpty {
                        statusSection
                    }

                    footerNote
                }
                .padding()
            }
            .background(secondaryBackground)
            .navigationTitle("Get Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()
        }
    }

    private var introSection: some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CenturionSectionHeader(title: "Support", icon: "lifepreserver")

                Text("Your Sovereign can prepare a short support code on your Sovereign brain.")
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText())

                Text("Share the code with your advisor — nothing leaves your network unless you choose to share it.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)

                Text("For step-by-step guides anytime, browse the Help Center or talk to Adrian from Connect or the You tab.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)

                HelpCenterLink()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private var supportCodeSection: some View {
        AtmosphericSurface(elevated: true, showRim: true) {
            VStack(spacing: Spacing.md) {
                CenturionSectionHeader(title: "Your Code", icon: "number")

                Text(supportCode)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(2)
                    .accessibilityLabel("Support code \(supportCode)")

                if !supportSummary.isEmpty {
                    Text(supportSummary)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button("Copy Support Code") {
                    UIPasteboard.general.string = supportCode
                    Haptics.success()
                    statusMessage = "Support code copied."
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .accessibilityHint("Copies the support code to the clipboard")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: Spacing.md) {
            Button {
                Task { await generateSupportCode() }
            } label: {
                Text(didGenerateCode ? "Create New Support Code" : "Send to Support")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .disabled(isWorking || connectionManager.connectionState != .connected)
            .accessibilityLabel("Send to Support")
            .accessibilityHint("Creates a support code on your Sovereign")

            Button {
                Task { await runAutoFix() }
            } label: {
                Text("Try to Fix Automatically")
            }
            .buttonStyle(CenturionSecondaryButtonStyle())
            .disabled(isWorking || connectionManager.connectionState != .connected)
            .accessibilityLabel("Try to Fix Automatically")
            .accessibilityHint("Restores your last working thinking service setup")

            Button {
                Task { await checkAgain() }
            } label: {
                Text("Check Again")
            }
            .buttonStyle(CenturionGhostButtonStyle())
            .disabled(isWorking || connectionManager.connectionState != .connected)
        }
    }

    private var statusSection: some View {
        AtmosphericSurface {
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(ColorTheme.primaryText())
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)
        }
    }

    private var footerNote: some View {
        Text("For deeper setup, use your Sovereign brain.")
            .font(.caption)
            .foregroundColor(ColorTheme.mutedText())
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private func generateSupportCode() async {
        isWorking = true
        defer { isWorking = false }
        let result = await connectionManager.requestSupportBundle()
        if result.ok {
            supportCode = result.code
            supportSummary = result.summary
            didGenerateCode = true
            statusMessage = result.message
            Haptics.success()
        } else {
            statusMessage = result.message
        }
    }

    private func runAutoFix() async {
        isWorking = true
        defer { isWorking = false }
        let result = await connectionManager.autoFixThinking()
        statusMessage = result.message
        if result.ok {
            Haptics.success()
        }
    }

    private func checkAgain() async {
        isWorking = true
        defer { isWorking = false }
        let result = await connectionManager.runHealthCheck()
        statusMessage = result.summary
        await connectionManager.refreshThinkingStatus()
    }
}
