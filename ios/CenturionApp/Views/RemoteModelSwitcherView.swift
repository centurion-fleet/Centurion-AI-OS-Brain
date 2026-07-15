import SwiftUI

struct RemoteModelSwitcherView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var catalog: RemoteModelCatalog?
    @State private var actionMessage: String?
    @State private var keyConnector: RemoteConnectorRow?
    @State private var apiKey = ""
    @State private var isAutoSelectEnabled = false
    @State private var isBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if connectionManager.thinkingCatalogUsedFallback {
                    fallbackNotice
                }
                if let catalog {
                    connectorSection(title: "Text models", rows: catalog.textModels, isCreative: false)
                    connectorSection(title: "Creative models", rows: catalog.creativeModels, isCreative: true)
                    routingSection
                } else {
                    ProgressView("Loading thinking services…")
                        .frame(maxWidth: .infinity)
                }
                if let actionMessage {
                    Text(actionMessage)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .padding()
        }
        .background(ColorTheme.background())
        .navigationTitle("Thinking Service")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCatalog() }
        .sheet(item: $keyConnector) { connector in
            apiKeySheet(for: connector)
        }
    }

    private var fallbackNotice: some View {
        AtmosphericSurface {
            Text("Showing the built-in model list. Key status may be outdated until your Centurion responds — restart centurion-remote on your Mac if this persists.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(3)
        }
    }

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Routing", icon: "arrow.triangle.branch")
            AtmosphericSurface {
                Toggle(isOn: $isAutoSelectEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-select model")
                            .font(.body.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText())
                        Text("Your Centurion picks an LLM from your message. This is not your Centurion's name.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .tint(ColorTheme.accent())
                .onChange(of: isAutoSelectEnabled) { _, enabled in
                    Task {
                        let mode = enabled ? "phoenix" : "manual"
                        _ = await connectionManager.setRoutingMode(mode)
                        connectionManager.routingMode = mode
                    }
                }
            }
        }
    }

    private func connectorSection(title: String, rows: [RemoteConnectorRow], isCreative: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: title, icon: isCreative ? "paintbrush" : "brain.head.profile")
            AtmosphericSurface {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(ColorTheme.border())
                                .frame(height: 0.5)
                        }
                        Button {
                            Task { await selectConnector(row, isCreative: isCreative) }
                        } label: {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.displayName)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(ColorTheme.primaryText())
                                    if !row.bestFor.isEmpty {
                                        Text(row.bestFor)
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.mutedText())
                                    }
                                }
                                Spacer()
                                Text(row.statusLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(row.active ? ColorTheme.accent() : ColorTheme.mutedText())
                            }
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)

                        if row.needsKey {
                            Button("Add API key on Centurion") {
                                keyConnector = row
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.accent())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, Spacing.sm)
                        }
                    }
                }
            }
        }
    }

    private func apiKeySheet(for connector: RemoteConnectorRow) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Keys stay on your Centurion — not on this iPhone.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save on Centurion") {
                    Task {
                        let result = await connectionManager.saveRemoteAPIKey(
                            connectorId: connector.id,
                            key: apiKey
                        )
                        actionMessage = result.message
                        apiKey = ""
                        keyConnector = nil
                        await loadCatalog()
                    }
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                Spacer()
            }
            .padding()
            .navigationTitle(connector.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { keyConnector = nil }
                }
            }
        }
    }

    private func loadCatalog() async {
        let loaded = await connectionManager.fetchRemoteModelCatalog()
        catalog = loaded
        isAutoSelectEnabled = loaded.routingMode == "phoenix"
    }

    private func selectConnector(_ row: RemoteConnectorRow, isCreative: Bool) async {
        isBusy = true
        defer { isBusy = false }
        if row.needsKey {
            keyConnector = row
            return
        }
        let result = await connectionManager.applyRemoteModel(connectorId: row.id)
        actionMessage = result.message
        if !isCreative {
            await connectionManager.setRoutingMode("manual")
            isAutoSelectEnabled = false
        }
        await loadCatalog()
    }
}

struct TelegramImportWizardView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @AppStorage("centurion.telegramImport.completed") private var importCompleted = false
    @Environment(\.dismiss) private var dismiss

    @State private var preview: TelegramImportBundle?
    @State private var loadError: String?
    @State private var importMessage: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Bring your Telegram bot conversation into Centurion.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())

                    if let loadError {
                        ErrorState(
                            title: "Couldn't preview import",
                            message: loadError,
                            retryTitle: "Try again",
                            onRetry: { Task { await loadPreview() } }
                        )
                    } else if let preview {
                        previewCard(preview)
                        if preview.ok {
                            Button(isImporting ? "Importing…" : "Import conversation") {
                                Task { await confirmImport() }
                            }
                            .buttonStyle(CenturionPrimaryButtonStyle())
                            .disabled(isImporting)
                        }
                    } else {
                        ProgressView("Checking Telegram history on your Centurion…")
                    }

                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .padding()
            }
            .background(ColorTheme.background())
            .navigationTitle("Telegram Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPreview() }
        }
    }

    private func previewCard(_ preview: TelegramImportBundle) -> some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(preview.conversation?.title ?? "Telegram with Centurion")
                    .font(.body.weight(.semibold))
                Text("\(preview.messageCount) messages · \(preview.fileCount) files")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                if preview.missingFileCount > 0 {
                    Text("\(preview.missingFileCount) attachments expired on your Centurion and will show as placeholders.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
                if preview.candidates.count > 1 {
                    Text("Using the most recent bot DM session.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadPreview() async {
        loadError = nil
        do {
            preview = try await connectionManager.previewTelegramImport()
            if preview?.ok == false {
                loadError = preview?.message ?? "No Telegram bot conversation was found."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func confirmImport() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let bundle = try await connectionManager.importTelegramBundle()
            guard bundle.ok else {
                importMessage = bundle.message ?? "Import failed."
                return
            }
            ConversationStore.shared.importTelegramBundle(bundle, into: messageService)
            importCompleted = true
            importMessage = "Imported \(bundle.messageCount) messages."
            dismiss()
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
