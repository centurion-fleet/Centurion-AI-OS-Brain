import SwiftUI

/// Chat with Adrian — the online presence of Centurion's creator.
struct AdrianView: View {
    @EnvironmentObject private var adrianService: AdrianService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @Environment(\.dismiss) private var dismiss

    var onAction: (AdrianAction) -> Void = { _ in }

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !adrianService.hasAcceptedPrivacy {
                    privacyGate
                } else {
                    messageList
                    if !adrianService.suggestedActions.isEmpty {
                        actionChips
                    }
                    if let error = adrianService.lastError {
                        errorBanner(error)
                    }
                    inputBar
                }
            }
            .background(secondaryBackground)
            .navigationTitle("Adrian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
            .onAppear {
                adrianService.seedWelcomeIfNeeded()
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

    private var privacyGate: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                AtmosphericSurface(elevated: true) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        CenturionSectionHeader(title: "Meet Adrian", icon: "person.crop.circle")

                        Text(
                            "Adrian online is Adrian who created Centurion. His passion is helping you live "
                                + "your mission — lift daily pressure, free your thinking, and deepen your "
                                + "1:1 relationship with your private Centurion. Missions evolve; that's expected."
                        )
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText())
                        .lineSpacing(4)

                        Text(
                            "Adrian listens first, then helps one step at a time. He works over the internet, "
                                + "separate from your private Centurion link, and sees only what helps — link status, "
                                + "thinking health in plain words, and a short mission summary if you've set one. "
                                + "Never your chat history or secrets."
                        )
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(4)
                    }
                }

                Button("Continue with Adrian") {
                    Haptics.lightTap()
                    adrianService.acceptPrivacy()
                    adrianService.seedWelcomeIfNeeded()
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
            }
            .padding()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(adrianService.messages) { message in
                        adrianRow(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: adrianService.messages.count) { _, _ in
                if let last = adrianService.messages.last {
                    withAnimation(Motion.standard) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func adrianRow(_ message: AdrianMessage) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            if message.role == .user { Spacer(minLength: 48) }

            if message.role == .adrian {
                Image(systemName: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                    .padding(6)
                    .background(ColorTheme.accent().opacity(0.12))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                if message.role == .adrian {
                    Text("Adrian")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())
                }

                Group {
                    if message.role == .user {
                        Text(message.content)
                            .font(.body)
                            .foregroundColor(ColorTheme.primaryText())
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(ColorTheme.accent().opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    } else {
                        AtmosphericSurface {
                            Text(message.content)
                                .font(.body)
                                .foregroundColor(ColorTheme.primaryText())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineSpacing(3)
                        }
                    }
                }
            }

            if message.role == .adrian { Spacer(minLength: 48) }
        }
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(adrianService.suggestedActions) { action in
                    Button(action.label) {
                        Haptics.lightTap()
                        handleAction(action.id)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(ColorTheme.accent().opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(ColorTheme.accent().opacity(0.25), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        AtmosphericSurface {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(ColorTheme.error())
                Text(message)
                    .font(.caption)
                    .foregroundColor(ColorTheme.primaryText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xxs)
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask Adrian for help…", text: $draft)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(ColorTheme.chatInput())
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            if adrianService.isSending {
                ProgressView()
                    .tint(ColorTheme.accent())
                    .frame(width: 36, height: 36)
            } else {
                Button {
                    let text = draft
                    draft = ""
                    Task {
                        await adrianService.send(
                            text,
                            connectionManager: connectionManager,
                            missionStore: missionStore
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? ColorTheme.mutedText()
                                : ColorTheme.accent()
                        )
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    private func handleAction(_ id: String) {
        switch id {
        case "open_connect":
            onAction(.openConnect)
        case "try_auto_fix":
            onAction(.tryAutoFix)
        case "open_get_help":
            onAction(.openGetHelp)
        case "open_mission":
            onAction(.openMission)
        default:
            break
        }
    }
}
