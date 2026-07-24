import SwiftUI

/// Fullscreen thinking-service dial + access-code wizard (You → Settings).
struct ThinkingServiceDialView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: RemoteModelCatalog?
    @State private var selectedFamilyID: String?
    @State private var connectingFamilyID: String?
    @State private var actionMessage: String?
    @State private var isAutoSelectEnabled = false
    @State private var isBusy = false
    @State private var wizardLaunch: ThinkingServiceWizardLaunch?
    @State private var pendingServicePick: ThinkingServiceFamily?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    introCopy

                    if connectionManager.thinkingCatalogUsedFallback {
                        fallbackNotice
                    }

                    if let catalog {
                        let families = ThinkingServiceFamily.families(from: catalog, category: "text")
                        ThinkingServiceFamilyDial(
                            families: families,
                            selectedFamilyID: selectedFamilyBinding(families),
                            connectingFamilyID: connectingFamilyID
                        ) { family in
                            Task { await handleFamilyTap(family) }
                        }

                        if let selected = families.first(where: { $0.id == selectedFamilyID }) {
                            familyStatusPanel(selected)
                        }

                        creativeSection(catalog)

                        routingSection
                    } else {
                        ProgressView("Loading thinking services…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xl)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        wizardLaunch = ThinkingServiceWizardLaunch(mode: .add, family: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add thinking service")
                }
            }
            .task { await loadCatalog() }
            .sheet(item: $wizardLaunch) { launch in
                ThinkingServiceWizardView(
                    launch: launch,
                    catalog: catalog ?? .bundled(),
                    onFinished: { message in
                        actionMessage = message
                        wizardLaunch = nil
                        Task { await loadCatalog() }
                    },
                    onConnecting: { familyID in
                        connectingFamilyID = familyID
                    },
                    onConnectingEnded: {
                        connectingFamilyID = nil
                    }
                )
                .environmentObject(connectionManager)
            }
            .sheet(item: $pendingServicePick) { family in
                servicePickerSheet(family)
            }
        }
    }

    private var introCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn the dial to choose how your Sovereign thinks.")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
            Text("Access codes stay on your Sovereign — never on this iPhone.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
        }
    }

    private var fallbackNotice: some View {
        AtmosphericSurface {
            Text("Showing the built-in list. Status may be outdated until your Sovereign responds — restart centurion-remote on your Mac if this persists.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .lineSpacing(3)
        }
    }

    private func familyStatusPanel(_ family: ThinkingServiceFamily) -> some View {
        let status = family.status(isConnecting: connectingFamilyID == family.id)
        return AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(family.displayName)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                            .overlay {
                                if status == .connecting {
                                    Circle()
                                        .stroke(status.color.opacity(0.35), lineWidth: 3)
                                        .scaleEffect(1.8)
                                        .opacity(0.8)
                                }
                            }
                        Text(status.label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(status.color)
                    }
                }

                Text(family.summary)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())

                if let active = family.activeConnector {
                    Text("Using \(active.displayName)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.accent())
                }

                HStack(spacing: Spacing.sm) {
                    if family.needsAccess {
                        Button("Add access code") {
                            wizardLaunch = ThinkingServiceWizardLaunch(mode: .add, family: family)
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())
                    } else {
                        Button("Update access code") {
                            wizardLaunch = ThinkingServiceWizardLaunch(mode: .update, family: family)
                        }
                        .buttonStyle(CenturionSecondaryButtonStyle())

                        if family.connectors.count > 1 {
                            Button("Choose service") {
                                pendingServicePick = family
                            }
                            .buttonStyle(CenturionSecondaryButtonStyle())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func creativeSection(_ catalog: RemoteModelCatalog) -> some View {
        let creative = ThinkingServiceFamily.families(from: catalog, category: "creative")
        if !creative.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CenturionSectionHeader(title: "Creative services", icon: "paintbrush")
                AtmosphericSurface {
                    VStack(spacing: 0) {
                        ForEach(Array(creative.enumerated()), id: \.element.id) { index, family in
                            if index > 0 {
                                Rectangle()
                                    .fill(ColorTheme.border())
                                    .frame(height: 0.5)
                            }
                            Button {
                                Task { await handleFamilyTap(family) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(family.displayName)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(ColorTheme.primaryText())
                                        Text(family.summary)
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.mutedText())
                                    }
                                    Spacer()
                                    Text(family.status(isConnecting: connectingFamilyID == family.id).label)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(ColorTheme.mutedText())
                                }
                                .padding(.vertical, Spacing.sm)
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
    }

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Automatic choice", icon: "arrow.triangle.branch")
            AtmosphericSurface {
                Toggle(isOn: $isAutoSelectEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Let Sovereign choose")
                            .font(.body.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText())
                        Text("Your Sovereign picks a thinking service from your message. This is not your Sovereign’s name.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .tint(ColorTheme.accent())
                .onChange(of: isAutoSelectEnabled) { _, enabled in
                    Task {
                        let mode = enabled ? "phoenix" : "manual"
                        let ok = await connectionManager.setRoutingMode(mode)
                        if ok {
                            connectionManager.routingMode = mode
                        } else {
                            // Revert toggle to host truth on failure.
                            isAutoSelectEnabled = connectionManager.routingMode == "phoenix"
                            actionMessage = "Could not update automatic choice. Check your link and try again."
                        }
                    }
                }
            }
        }
    }

    private func servicePickerSheet(_ family: ThinkingServiceFamily) -> some View {
        NavigationStack {
            List {
                ForEach(family.connectors) { row in
                    Button {
                        Task {
                            pendingServicePick = nil
                            await applyConnector(row, familyID: family.id, isCreative: family.category == "creative")
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.displayName)
                                    .foregroundColor(ColorTheme.primaryText())
                                if !row.bestFor.isEmpty {
                                    Text(row.bestFor)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.mutedText())
                                }
                            }
                            Spacer()
                            if row.active {
                                Text("Active")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(ColorTheme.accent())
                            }
                        }
                    }
                    .disabled(isBusy || row.needsKey)
                }
            }
            .navigationTitle(family.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingServicePick = nil }
                }
            }
        }
    }

    private func selectedFamilyBinding(_ families: [ThinkingServiceFamily]) -> Binding<String?> {
        Binding(
            get: {
                if let selectedFamilyID { return selectedFamilyID }
                if let active = families.first(where: \.isActive)?.id { return active }
                return families.first?.id
            },
            set: { selectedFamilyID = $0 }
        )
    }

    private func handleFamilyTap(_ family: ThinkingServiceFamily) async {
        selectedFamilyID = family.id
        Haptics.lightTap()
        if family.needsAccess {
            wizardLaunch = ThinkingServiceWizardLaunch(mode: .add, family: family)
            return
        }
        if family.connectors.count == 1 {
            await applyConnector(family.preferredConnector, familyID: family.id, isCreative: family.category == "creative")
            return
        }
        if family.activeConnector != nil {
            // Already active — keep selection; offer update via panel
            return
        }
        pendingServicePick = family
    }

    private func applyConnector(_ row: RemoteConnectorRow, familyID: String, isCreative: Bool) async {
        isBusy = true
        connectingFamilyID = familyID
        defer {
            isBusy = false
            connectingFamilyID = nil
        }
        let result = await connectionManager.applyRemoteModel(connectorId: row.id)
        actionMessage = result.message
        if result.ok {
            Haptics.success()
            if !isCreative {
                _ = await connectionManager.setRoutingMode("manual")
                isAutoSelectEnabled = false
            }
        } else {
            Haptics.error()
        }
        await loadCatalog()
    }

    private func loadCatalog() async {
        let loaded = await connectionManager.fetchRemoteModelCatalog()
        catalog = loaded
        isAutoSelectEnabled = loaded.routingMode == "phoenix"
        if selectedFamilyID == nil {
            selectedFamilyID = ThinkingServiceFamily.families(from: loaded).first(where: \.isActive)?.id
                ?? ThinkingServiceFamily.families(from: loaded).first?.id
        }
    }
}

// MARK: - Dial chrome

struct ThinkingServiceFamilyDial: View {
    let families: [ThinkingServiceFamily]
    @Binding var selectedFamilyID: String?
    let connectingFamilyID: String?
    let onSelect: (ThinkingServiceFamily) -> Void

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(families) { family in
                        let isSelected = family.id == selectedFamilyID
                        let status = family.status(isConnecting: connectingFamilyID == family.id)
                        Button {
                            withAnimation(Motion.standard) {
                                selectedFamilyID = family.id
                            }
                            onSelect(family)
                        } label: {
                            VStack(spacing: Spacing.xs) {
                                ZStack {
                                    Circle()
                                        .fill(status.color)
                                        .frame(width: 10, height: 10)
                                    if isSelected || status == .connecting {
                                        Circle()
                                            .stroke(status.color.opacity(0.35), lineWidth: 3)
                                            .frame(width: 18, height: 18)
                                    }
                                }
                                .frame(height: 22)

                                Text(family.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(isSelected ? ColorTheme.primaryText() : ColorTheme.mutedText())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(status.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(status.color)
                                    .lineLimit(1)
                            }
                            .frame(width: 88)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                isSelected
                                    ? ColorTheme.accent().opacity(0.08)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(family.displayName), \(status.label)")
                    }
                }
                .padding(4)
            }
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(ColorTheme.border().opacity(0.6), lineWidth: 1)
            )

            HStack(spacing: 0) {
                ForEach(families) { family in
                    Rectangle()
                        .fill(family.id == selectedFamilyID ? ColorTheme.accent() : Color.clear)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }
}

// MARK: - Wizard launch

struct ThinkingServiceWizardLaunch: Identifiable, Equatable {
    enum Mode: Equatable {
        case add
        case update
    }

    let mode: Mode
    let family: ThinkingServiceFamily?

    var id: String {
        "\(mode)-\(family?.id ?? "pick")"
    }
}

// MARK: - Access-code wizard

struct ThinkingServiceWizardView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    let launch: ThinkingServiceWizardLaunch
    let catalog: RemoteModelCatalog
    let onFinished: (String) -> Void
    let onConnecting: (String) -> Void
    let onConnectingEnded: () -> Void

    @State private var step: WizardStep
    @State private var selectedFamily: ThinkingServiceFamily?
    @State private var selectedConnector: RemoteConnectorRow?
    @State private var accessCode = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum WizardStep {
        case pickFamily
        case enterCode
        case pickService
        case connecting
    }

    init(
        launch: ThinkingServiceWizardLaunch,
        catalog: RemoteModelCatalog,
        onFinished: @escaping (String) -> Void,
        onConnecting: @escaping (String) -> Void,
        onConnectingEnded: @escaping () -> Void
    ) {
        self.launch = launch
        self.catalog = catalog
        self.onFinished = onFinished
        self.onConnecting = onConnecting
        self.onConnectingEnded = onConnectingEnded
        let family = launch.family
        _selectedFamily = State(initialValue: family)
        if family == nil {
            _step = State(initialValue: .pickFamily)
        } else {
            _step = State(initialValue: .enterCode)
        }
    }

    private var textFamilies: [ThinkingServiceFamily] {
        ThinkingServiceFamily.families(from: catalog, category: "text")
            + ThinkingServiceFamily.families(from: catalog, category: "creative")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                stepHeader
                stepContent
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(Color(red: 0.75, green: 0.35, blue: 0.28))
                }
                Spacer(minLength: 0)
                bottomActions
            }
            .padding()
            .background(ColorTheme.background())
            .navigationTitle(launch.mode == .update ? "Update access" : "Add thinking service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBusy && step == .connecting)
                }
            }
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stepTitle)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
            Text(stepSubtitle)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
        }
    }

    private var stepTitle: String {
        switch step {
        case .pickFamily: return "Which service?"
        case .enterCode: return "Access code"
        case .pickService: return "Which option?"
        case .connecting: return "Connecting"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .pickFamily:
            return "Pick the thinking service family you want to use."
        case .enterCode:
            return "Paste the access code from your thinking-service account. It is saved only on your Sovereign — not kept on this iPhone."
        case .pickService:
            return "Choose the exact thinking service for this family."
        case .connecting:
            return "Your Sovereign is verifying the connection."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .pickFamily:
            VStack(spacing: 0) {
                ForEach(textFamilies) { family in
                    Button {
                        selectedFamily = family
                        Haptics.lightTap()
                        step = .enterCode
                    } label: {
                        HStack {
                            Text(family.displayName)
                                .foregroundColor(ColorTheme.primaryText())
                            Spacer()
                            Text(family.status(isConnecting: false).label)
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(.horizontal, Spacing.xs)
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

        case .enterCode:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let selectedFamily {
                    Text(selectedFamily.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())
                }
                SecureField("Access code", text: $accessCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }

        case .pickService:
            if let selectedFamily {
                VStack(spacing: 0) {
                    ForEach(selectedFamily.connectors) { row in
                        Button {
                            selectedConnector = row
                            Haptics.lightTap()
                            Task { await finishWithConnector(row) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.displayName)
                                        .foregroundColor(ColorTheme.primaryText())
                                    if !row.bestFor.isEmpty {
                                        Text(row.bestFor)
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.mutedText())
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        Divider()
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .background(ColorTheme.surface())
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

        case .connecting:
            VStack(spacing: Spacing.md) {
                ProgressView()
                Text(selectedFamily?.displayName ?? "Thinking service")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        switch step {
        case .enterCode:
            Button(launch.mode == .update ? "Save and continue" : "Save on Sovereign") {
                Task { await saveCodeAndContinue() }
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .disabled(accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)

        case .pickFamily, .pickService, .connecting:
            EmptyView()
        }
    }

    private func saveCodeAndContinue() async {
        guard let family = selectedFamily else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let connector = family.preferredConnector
        let result = await connectionManager.saveRemoteAPIKey(
            connectorId: connector.id,
            key: accessCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard result.ok else {
            errorMessage = result.message
            Haptics.error()
            return
        }

        accessCode = ""
        // Refresh family connectors from latest catalog
        let refreshed = await connectionManager.fetchRemoteModelCatalog()
        let families = ThinkingServiceFamily.families(from: refreshed, category: family.category)
        if let updated = families.first(where: { $0.id == family.id }) {
            selectedFamily = updated
            if updated.connectors.count > 1, launch.mode == .add || updated.activeConnector == nil {
                step = .pickService
                return
            }
            await finishWithConnector(updated.preferredConnector)
        } else {
            await finishWithConnector(connector)
        }
    }

    private func finishWithConnector(_ row: RemoteConnectorRow) async {
        guard let family = selectedFamily else { return }
        isBusy = true
        step = .connecting
        onConnecting(family.id)
        defer {
            isBusy = false
            onConnectingEnded()
        }

        let result = await connectionManager.applyRemoteModel(connectorId: row.id)
        if result.ok, family.category != "creative" {
            _ = await connectionManager.setRoutingMode("manual")
        }
        if result.ok {
            Haptics.success()
            onFinished(result.message)
            dismiss()
        } else {
            Haptics.error()
            errorMessage = result.message
            step = family.connectors.count > 1 ? .pickService : .enterCode
        }
    }
}
