import SwiftUI

struct ThinkingRecoverySheet: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var statusMessage = ""
    @State private var isWorking = false
    @State private var showGetHelp = false

    let initialMessage: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(plainStatusMessage)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                } header: {
                    Text("What we found")
                }

                if connectionManager.thinkingStatus?.lastGoodAvailable == true {
                    Section {
                        Button("Restore last working setup") {
                            Task { await restoreLastGood() }
                        }
                        .disabled(isWorking)
                        .accessibilityLabel("Restore last working setup")
                    }
                }

                Section {
                    Button("Get Help") {
                        showGetHelp = true
                    }
                    .accessibilityLabel("Get Help")

                    Text("API keys and deeper changes are made on your Centurion computer, not on this iPhone.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .navigationTitle("Fix Thinking Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await connectionManager.refreshThinkingStatus()
            }
            .sheet(isPresented: $showGetHelp) {
                GetHelpView()
                    .environmentObject(connectionManager)
            }
            .overlay(alignment: .bottom) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(ColorTheme.primaryText())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(ColorTheme.surface())
                }
            }
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
