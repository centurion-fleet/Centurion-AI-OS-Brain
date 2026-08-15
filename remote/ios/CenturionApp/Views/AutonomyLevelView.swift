import SwiftUI

/// Autonomy Level detail — four clear levels with live descriptions.
struct AutonomyLevelView: View {
    @EnvironmentObject private var oversightStore: OversightStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                AtmosphericSurface(elevated: true, showRim: true) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        CenturionSectionHeader(title: "Autonomy", icon: "slider.horizontal.3")

                        Text("Autonomy Level")
                            .font(Typography.editorialTitle)
                            .foregroundColor(ColorTheme.primaryText())

                        Text("How much freedom your Centurion has when carrying out work.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .fixedSize(horizontal: false, vertical: true)

                        Picker("Autonomy Level", selection: Binding(
                            get: { oversightStore.prefs.autonomyLevel },
                            set: { level in
                                Haptics.lightTap()
                                Task {
                                    await oversightStore.setAutonomyLevel(
                                        level,
                                        connectionManager: connectionManager
                                    )
                                }
                            }
                        )) {
                            ForEach(AutonomyLevel.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(oversightStore.prefs.autonomyLevel.detail)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.dimAccent())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.xs)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(AutonomyLevel.allCases) { level in
                        AtmosphericSurface {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text(level.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.primaryText())
                                    Spacer()
                                    if level == oversightStore.prefs.autonomyLevel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(ColorTheme.accent())
                                    }
                                }
                                Text(level.detail)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.mutedText())
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.lightTap()
                            Task {
                                await oversightStore.setAutonomyLevel(
                                    level,
                                    connectionManager: connectionManager
                                )
                            }
                        }
                    }
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
                        .foregroundColor(ColorTheme.error().opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(secondaryBackground)
        .navigationTitle("Autonomy Level")
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
