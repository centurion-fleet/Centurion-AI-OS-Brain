import SwiftUI

/// The conversation drawer.
///
/// Deliberately a sheet, not a tab: the thread is the product, and history is
/// something you reach for rather than something that shares the screen with it.
///
/// Rows are ordered by `lastActive` — most recent first — because the only
/// question a drawer answers is "where was I".
struct SignumConversationList: View {
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    let selectedId: UUID?
    let onSelect: (Conversation) -> Void
    let onNew: () -> Void
    let onDelete: (Conversation) -> Void

    private var ordered: [Conversation] {
        messageService.conversations
            .filter { !$0.isDemoSeed }
            .sorted { $0.lastActive > $1.lastActive }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SignumTheme.cream.ignoresSafeArea()

                if ordered.isEmpty {
                    VStack(spacing: 10) {
                        SignumMark(size: 40, starOpacity: 0.14)
                        Text("No conversations yet")
                            .font(SignumTheme.serif(20))
                            .foregroundStyle(SignumTheme.ink)
                        Text("Anything you ask will be here tomorrow.")
                            .font(SignumTheme.ui(14))
                            .foregroundStyle(SignumTheme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(ordered) { conversation in
                                Button {
                                    onSelect(conversation)
                                } label: {
                                    row(conversation)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(conversation)
                                    } label: {
                                        Label("Delete conversation", systemImage: "trash")
                                    }
                                }

                                Divider().overlay(SignumTheme.hair)
                            }
                        }
                        .padding(.horizontal, SignumTheme.Metrics.screenPadding)
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New") { onNew() }
                        .font(SignumTheme.ui(14, .medium))
                        .foregroundStyle(SignumTheme.goldDeep)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(SignumTheme.ui(14, .medium))
                        .foregroundStyle(SignumTheme.ink.opacity(0.6))
                }
            }
            .toolbarBackground(SignumTheme.cream, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ conversation: Conversation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayTitle)
                    .font(SignumTheme.ui(15.5, conversation.id == selectedId ? .semibold : .regular))
                    .foregroundStyle(SignumTheme.ink)
                    .lineLimit(1)

                if !conversation.context.isStandalone {
                    Text(conversation.contextPath.uppercased())
                        .font(SignumTheme.mono(9))
                        .tracking(1)
                        .foregroundStyle(SignumTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(Self.relative(conversation.lastActive))
                .font(SignumTheme.mono(9.5))
                .tracking(0.8)
                .foregroundStyle(SignumTheme.muted)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private static func relative(_ date: Date) -> String {
        let now = Date()
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "NOW" }
        if seconds < 3600 { return "\(Int(seconds / 60))M" }
        if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) { return "YESTERDAY" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).uppercased()
    }
}
