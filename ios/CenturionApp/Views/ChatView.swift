import SwiftUI

/// Simplified chat view — minimal render to avoid launch freeze.
/// Shows empty state + input bar only.
struct ChatView: View {
    let conversation: Conversation?
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var messageText = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollView {
                VStack(spacing: Spacing.md) {
                    Spacer().frame(height: Spacing.lg)

                    Image(systemName: "message.fill")
                        .font(.system(size: 40))
                        .foregroundColor(ColorTheme.mutedText())

                    Text("No messages yet")
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())

                    Text("Start a conversation from Mission Control or send a message below.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }

            // Input bar
            VStack(spacing: 0) {
                Rectangle()
                    .fill(ColorTheme.border())
                    .frame(height: 0.5)

                HStack(spacing: Spacing.sm) {
                    TextField("Message your Centurion…", text: $messageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(ColorTheme.chatInput())
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(ColorTheme.border(), lineWidth: 1)
                        )

                    Button(action: {}) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(ColorTheme.mutedText())
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.ultraThinMaterial)
            }
            .padding(.bottom, Spacing.lg)
        }
    }
}
