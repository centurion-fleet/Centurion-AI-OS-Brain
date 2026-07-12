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
                    introSection

                    if !supportCode.isEmpty {
                        supportCodeSection
                    }

                    actionButtons

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.primaryText())
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ColorTheme.surface())
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    footerNote
                }
                .padding()
            }
            .background(ColorTheme.background())
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

    private var introSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your Centurion can prepare a short support code on your computer.")
                .font(.body)
                .foregroundColor(ColorTheme.primaryText())

            Text("Share the code with your advisor — nothing leaves your network unless you choose to share it.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())

            Text("For step-by-step help anytime, open Adrian from Connect or the You tab.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
        }
    }

    private var supportCodeSection: some View {
        VStack(spacing: Spacing.md) {
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
            }

            Button("Copy Support Code") {
                UIPasteboard.general.string = supportCode
                Haptics.success()
                statusMessage = "Support code copied."
            }
            .buttonStyle(AmberButtonStyle())
            .accessibilityHint("Copies the support code to the clipboard")
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.border(), lineWidth: 0.5)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: Spacing.md) {
            Button {
                Task { await generateSupportCode() }
            } label: {
                Text(didGenerateCode ? "Create New Support Code" : "Send to Support")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AmberButtonStyle())
            .disabled(isWorking || connectionManager.connectionState != .connected)
            .accessibilityLabel("Send to Support")
            .accessibilityHint("Creates a support code on your Centurion")

            Button {
                Task { await runAutoFix() }
            } label: {
                Text("Try to Fix Automatically")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(ColorTheme.accent())
            .disabled(isWorking || connectionManager.connectionState != .connected)
            .accessibilityLabel("Try to Fix Automatically")
            .accessibilityHint("Restores your last working thinking service setup")

            Button {
                Task { await checkAgain() }
            } label: {
                Text("Check Again")
                    .frame(maxWidth: .infinity)
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(ColorTheme.accent())
            .disabled(isWorking || connectionManager.connectionState != .connected)
        }
    }

    private var footerNote: some View {
        Text("For deeper changes, use Centurion on your computer.")
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
