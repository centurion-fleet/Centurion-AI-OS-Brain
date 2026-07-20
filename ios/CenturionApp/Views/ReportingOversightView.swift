import SwiftUI

/// Reporting cadence, confirmation gates, and initiative ask preferences.
struct ReportingOversightView: View {
    @EnvironmentObject private var oversightStore: OversightStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                AtmosphericSurface(elevated: true, showRim: true) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        CenturionSectionHeader(title: "Oversight", icon: "eye")

                        Text("Reporting & Oversight")
                            .font(Typography.editorialTitle)
                            .foregroundColor(ColorTheme.primaryText())

                        Text("Control how often your Centurion reports back, what needs confirmation, and whether it asks before taking initiative.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AtmosphericSurface {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Report cadence")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(ColorTheme.primaryText())
                        Text(oversightStore.prefs.reportCadence.detail)
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                            .fixedSize(horizontal: false, vertical: true)
                        Picker("Report cadence", selection: Binding(
                            get: { oversightStore.prefs.reportCadence },
                            set: { cadence in
                                Haptics.lightTap()
                                Task {
                                    await oversightStore.updatePrefs(
                                        { $0.reportCadence = cadence },
                                        connectionManager: connectionManager
                                    )
                                }
                            }
                        )) {
                            ForEach(ReportCadence.allCases) { cadence in
                                Text(cadence.label).tag(cadence)
                            }
                        }
                        .labelsHidden()
                        .tint(ColorTheme.accent())
                    }
                }

                AtmosphericSurface {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Confirm before")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(ColorTheme.primaryText())

                        Toggle(isOn: Binding(
                            get: { oversightStore.prefs.confirmDangerousCommands },
                            set: { value in
                                Haptics.lightTap()
                                Task {
                                    await oversightStore.updatePrefs(
                                        { $0.confirmDangerousCommands = value },
                                        connectionManager: connectionManager
                                    )
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dangerous commands")
                                    .font(.subheadline)
                                Text("Hard-to-undo shell or system actions")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                        }
                        .tint(ColorTheme.accent())

                        Toggle(isOn: Binding(
                            get: { oversightStore.prefs.confirmExternalActions },
                            set: { value in
                                Haptics.lightTap()
                                Task {
                                    await oversightStore.updatePrefs(
                                        { $0.confirmExternalActions = value },
                                        connectionManager: connectionManager
                                    )
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("External actions")
                                    .font(.subheadline)
                                Text("Messages, spending, or contacting people")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                            }
                        }
                        .tint(ColorTheme.accent())
                    }
                }

                AtmosphericSurface {
                    Toggle(isOn: Binding(
                        get: { oversightStore.prefs.askBeforeInitiative },
                        set: { value in
                            Haptics.lightTap()
                            Task {
                                await oversightStore.updatePrefs(
                                    { $0.askBeforeInitiative = value },
                                    connectionManager: connectionManager
                                )
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask before taking initiative")
                                .font(.subheadline.weight(.medium))
                            Text("Prompt you before starting work you did not request")
                                .font(.caption)
                                .foregroundColor(ColorTheme.mutedText())
                        }
                    }
                    .tint(ColorTheme.accent())
                }

                Text("Changes apply on the next conversation.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let message = oversightStore.lastSavedMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(ColorTheme.dimAccent())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = oversightStore.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(secondaryBackground)
        .navigationTitle("Reporting & Oversight")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await oversightStore.refresh(from: connectionManager)
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()
        }
    }
}
