import SwiftUI

/// One message, rendered the way the page renders: the customer as a slab of ink,
/// the Centurion as typeset prose with a serif opening.
///
/// ⚠️ The serif lead is a device, not decoration. A Centurion answer opens with a
/// claim; setting that claim in serif and the evidence in sans is what makes a
/// phone screen read like something printed rather than a chat log. It is applied
/// only when the answer actually has two paragraphs — a single-line reply in
/// serif headline type would be a costume with nothing under it.
struct SignumMessageRow: View {
    let message: Message
    let centurionName: String
    var onCopy: (String) -> Void = { _ in }
    var onRetry: (() -> Void)?

    private var isUser: Bool { message.role == .user }

    var body: some View {
        Group {
            if isUser {
                userBubble
            } else {
                centurionBlock
            }
        }
        .contextMenu {
            Button {
                onCopy(message.content)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if let onRetry, !isUser {
                Button {
                    onRetry()
                } label: {
                    Label("Ask again", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Customer

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.content)
                .font(SignumTheme.ui(16))
                .foregroundStyle(SignumTheme.cream)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(SignumTheme.ink)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: SignumTheme.Metrics.bubbleRadius,
                        bottomLeadingRadius: SignumTheme.Metrics.bubbleRadius,
                        bottomTrailingRadius: 5,
                        topTrailingRadius: SignumTheme.Metrics.bubbleRadius,
                        style: .continuous
                    )
                )
                .textSelection(.enabled)
        }
    }

    // MARK: - Centurion

    private var centurionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(attributed(paragraph))
                    .font(index == 0 && paragraphs.count > 1
                          ? SignumTheme.serif(21)
                          : SignumTheme.ui(16))
                    .foregroundStyle(index == 0 && paragraphs.count > 1
                                     ? SignumTheme.ink
                                     : SignumTheme.ink.opacity(0.86))
                    .lineSpacing(index == 0 && paragraphs.count > 1 ? 2 : 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, index == 0 ? 0 : 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(centurionName) said: \(message.content)")
    }

    /// Split on blank lines. A one-paragraph answer stays in sans throughout.
    private var paragraphs: [String] {
        message.content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Inline markdown only — bold, italic, code, links. Block-level markdown
    /// (headings, tables, fences) is deliberately not attempted here: a chat
    /// bubble is not a document, and a half-rendered table is worse than the
    /// plain text. Documents open in the viewer where they are typeset properly.
    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// The live working line — what the Centurion is doing, not a spinner.
///
/// `turnActivityHint` is already published by `ConnectionManager` while a turn is
/// in flight ("Reading…", "Running a tool…"), so this is a rendering of real
/// state rather than a decorative animation. When there is no hint yet, the line
/// still appears with a neutral label — silence during a 40-second turn reads as
/// a frozen app.
struct SignumWorkLine: View {
    let hint: String?
    @State private var pulse = false

    private var label: String {
        let trimmed = (hint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Working" : trimmed
    }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(SignumTheme.gold)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 1 : 0.35)
                .scaleEffect(pulse ? 1 : 0.7)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )

            Text(label.uppercased())
                .font(SignumTheme.mono(10.5, .medium))
                .tracking(1.3)
                .foregroundStyle(SignumTheme.muted)
                .lineLimit(2)
        }
        .onAppear { pulse = true }
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 22) {
        SignumMessageRow(
            message: Message(
                conversationId: UUID(),
                content: "Draft a paragraph about the Italy decree.",
                role: .user
            ),
            centurionName: "Titus"
        )
        SignumMessageRow(
            message: Message(
                conversationId: UUID(),
                content: "Italy has given the AI literacy duty a shape, and a date.\n\nDecreto Legislativo 179/2026 came into force on 23 October. Article 47 puts AI literacy into the training that professional orders must deliver, and gives the national councils **six months, to 23 April 2027**, to amend their training regulations.",
                role: .centurion
            ),
            centurionName: "Titus"
        )
        SignumWorkLine(hint: "Reading Gazzetta Ufficiale · art. 47")
    }
    .padding(24)
    .background(SignumTheme.cream)
}
