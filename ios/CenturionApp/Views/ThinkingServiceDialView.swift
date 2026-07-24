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
            Text("Turn the dial to choose how your Centurion thinks.")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
            Text("Access codes stay on your Centurion — never on this iPhone.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
        }
    }

    private var fallbackNotice: some View {
        AtmosphericSurface {
            Text("Showing the built-in list. Status may be outdated until your Centurion responds — reopen Thinking Service in a moment if this persists.")
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragRotation: Double = 0
    @State private var baseRotation: Double = 0

    private var selectedIndex: Int {
        guard let selectedFamilyID else { return 0 }
        return families.firstIndex(where: { $0.id == selectedFamilyID }) ?? 0
    }

    private var stepDegrees: Double {
        guard !families.isEmpty else { return 360 }
        return 360.0 / Double(families.count)
    }

    var body: some View {
        Group {
            if reduceMotion || families.count <= 1 {
                listFallback
            } else {
                circularDial
            }
        }
    }

    private var listFallback: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(Array(families.enumerated()), id: \.element.id) { _, family in
                let isSelected = family.id == selectedFamilyID
                let status = family.status(isConnecting: connectingFamilyID == family.id)
                Button {
                    selectedFamilyID = family.id
                    onSelect(family)
                } label: {
                    HStack {
                        Circle()
                            .fill(status.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(family.displayName)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundColor(ColorTheme.primaryText())
                            Text(status.label)
                                .font(.caption)
                                .foregroundColor(status.color)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundColor(ColorTheme.accent())
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(isSelected ? ColorTheme.accent().opacity(0.08) : ColorTheme.surface())
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(family.displayName), \(status.label)")
            }
        }
    }

    private var circularDial: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(ColorTheme.border().opacity(0.55), lineWidth: 14)
                    .frame(width: 220, height: 220)

                Circle()
                    .fill(ColorTheme.surface())
                    .frame(width: 150, height: 150)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)

                // Tick marks + family labels around the ring
                ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                    let angle = Angle(degrees: Double(index) * stepDegrees + baseRotation + dragRotation - 90)
                    let isSelected = family.id == selectedFamilyID
                    let status = family.status(isConnecting: connectingFamilyID == family.id)
                    VStack(spacing: 4) {
                        Circle()
                            .fill(isSelected ? status.color : ColorTheme.mutedText().opacity(0.45))
                            .frame(width: isSelected ? 12 : 8, height: isSelected ? 12 : 8)
                        Text(shortLabel(family.displayName))
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? ColorTheme.primaryText() : ColorTheme.mutedText())
                            .lineLimit(1)
                            .frame(width: 64)
                    }
                    .offset(y: -98)
                    .rotationEffect(angle)
                }

                // Center readout
                VStack(spacing: 6) {
                    Image(systemName: "dial.low.fill")
                        .font(.title2)
                        .foregroundColor(ColorTheme.accent())
                    if let selected = families[safe: selectedIndex] {
                        Text(selected.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText())
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 120)
                        Text(selected.status(isConnecting: connectingFamilyID == selected.id).label)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(selected.status(isConnecting: connectingFamilyID == selected.id).color)
                    }
                }
            }
            .frame(height: 240)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let delta = Double(value.translation.width + value.translation.height) * 0.35
                        dragRotation = delta
                    }
                    .onEnded { _ in
                        let total = baseRotation + dragRotation
                        let snappedIndex = snappedFamilyIndex(for: total)
                        let target = -Double(snappedIndex) * stepDegrees
                        withAnimation(Motion.standard) {
                            baseRotation = target
                            dragRotation = 0
                        }
                        let family = families[snappedIndex]
                        if selectedFamilyID != family.id {
                            selectedFamilyID = family.id
                            Haptics.lightTap()
                            onSelect(family)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Thinking service dial")
            .accessibilityValue(families[safe: selectedIndex]?.displayName ?? "")
            .accessibilityAdjustableAction { direction in
                guard !families.isEmpty else { return }
                var idx = selectedIndex
                switch direction {
                case .increment: idx = (idx + 1) % families.count
                case .decrement: idx = (idx - 1 + families.count) % families.count
                @unknown default: break
                }
                selectedFamilyID = families[idx].id
                baseRotation = -Double(idx) * stepDegrees
                onSelect(families[idx])
                Haptics.lightTap()
            }
            .onAppear {
                baseRotation = -Double(selectedIndex) * stepDegrees
            }
            .onChange(of: selectedFamilyID) { _, _ in
                withAnimation(Motion.standard) {
                    baseRotation = -Double(selectedIndex) * stepDegrees
                    dragRotation = 0
                }
            }

            Text("Drag the dial — or use VoiceOver to step through services.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func snappedFamilyIndex(for rotation: Double) -> Int {
        guard !families.isEmpty else { return 0 }
        // Rotation maps family 0 to top when rotation == 0; dragging positive rotates labels.
        let normalized = ((-rotation / stepDegrees).rounded()
            .truncatingRemainder(dividingBy: Double(families.count)) + Double(families.count))
            .truncatingRemainder(dividingBy: Double(families.count))
        return Int(normalized)
    }

    private func shortLabel(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts.prefix(2).joined(separator: " "))
        }
        return name
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
                        .foregroundColor(ColorTheme.error())
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
