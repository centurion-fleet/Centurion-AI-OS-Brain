import SwiftUI

struct ThinkingRecoverySheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var statusMessage = ""
    @State private var isWorking = false
    @State private var showGetHelp = false

    let initialMessage: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(CenturionGhostButtonStyle())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Fix Thinking Service",
                        subtitle: "We'll get your Centurion thinking again"
                    )

                    ErrorState(
                        title: "Something needs attention",
                        message: plainStatusMessage
                    )

                    if connectionManager.thinkingStatus?.lastGoodAvailable == true {
                        Button {
                            Task { await restoreLastGood() }
                        } label: {
                            if isWorking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Restore last working setup")
                            }
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())
                        .disabled(isWorking)
                        .padding(.horizontal, Spacing.md)
                        .accessibilityLabel("Restore last working setup")
                    }

                    Button("Get Help") {
                        showGetHelp = true
                    }
                    .buttonStyle(CenturionSecondaryButtonStyle())
                    .padding(.horizontal, Spacing.md)
                    .accessibilityLabel("Get Help")

                    Text("API keys and deeper changes are made on your Centurion computer, not on this iPhone.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, Spacing.lg)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.primaryText())
                            .multilineTextAlignment(.center)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity)
                            .centurionCard()
                            .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .task {
            await connectionManager.refreshThinkingStatus()
        }
        .sheet(isPresented: $showGetHelp) {
            GetHelpView()
                .environmentObject(connectionManager)
        }
    }

    private var plainStatusMessage: String {
        if let status = connectionManager.thinkingStatus, !status.healthMessage.isEmpty {
            return status.healthMessage
        }
        return initialMessage
    }

    private func restoreLastGood() async {
        isWorking = true
        defer { isWorking = false }
        let result = await connectionManager.restoreLastThinkingSetup()
        statusMessage = result.message
        if result.ok {
            Haptics.success()
            dismiss()
        }
    }
}
