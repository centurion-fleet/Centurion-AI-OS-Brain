import SwiftUI

/// Chat sheet for Herald — Centurion's cloud support guide.
struct HeraldView: View {
    @EnvironmentObject private var heraldService: HeraldService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var missionStore: MissionStore
    @Environment(\.dismiss) private var dismiss

    var onAction: (HeraldAction) -> Void = { _ in }

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !heraldService.hasAcceptedPrivacy {
                    privacyGate
                } else {
                    messageList
                    if !heraldService.suggestedActions.isEmpty {
                        actionChips
                    }
                    if let error = heraldService.lastError {
                        errorBanner(error)
                    }
                    inputBar
                }
            }
            .background(ColorTheme.background())
            .navigationTitle("Herald")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
            .onAppear {
                heraldService.seedWelcomeIfNeeded()
            }
        }
    }

    private var privacyGate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 44))
                    .foregroundColor(ColorTheme.accent())
                    .frame(maxWidth: .infinity)

                Text("Meet Herald")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())

                Text(
                    "Herald is Centurion's support guide — powered by Centurion so you never need an API key. "
                        + "Herald works over the internet, separate from your private Centurion link."
                )
                .font(.body)
                .foregroundColor(ColorTheme.primaryText())

                Text(
                    "Herald sees only what helps troubleshooting: whether you're linked, thinking health in plain words, "
                        + "and a short mission summary if you've set one. Herald never sees your Centurion chat history "
                        + "or secrets."
                )
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())

                Button("Continue with Herald") {
                    Haptics.lightTap()
                    heraldService.acceptPrivacy()
                    heraldService.seedWelcomeIfNeeded()
                }
                .buttonStyle(AmberButtonStyle())
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(heraldService.messages) { message in
                        heraldRow(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: heraldService.messages.count) { _, _ in
                if let last = heraldService.messages.last {
                    withAnimation(Motion.standard) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func heraldRow(_ message: HeraldMessage) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            if message.role == .user { Spacer(minLength: 48) }

            if message.role == .herald {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                    .padding(6)
                    .background(ColorTheme.accent().opacity(0.12))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                if message.role == .herald {
                    Text("Herald")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())
                }

                Text(message.content)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText())
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        message.role == .user
                            ? ColorTheme.accent().opacity(0.15)
                            : ColorTheme.surface()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if message.role == .herald { Spacer(minLength: 48) }
        }
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(heraldService.suggestedActions) { action in
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
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(ColorTheme.primaryText())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorTheme.error().opacity(0.08))
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask Herald for help…", text: $draft)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(ColorTheme.chatInput())
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if heraldService.isSending {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else {
                Button {
                    let text = draft
                    draft = ""
                    Task {
                        await heraldService.send(
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
