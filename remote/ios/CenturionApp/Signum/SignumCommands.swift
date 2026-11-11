import SwiftUI

/// The command surface — what used to live in Telegram.
///
/// Two rules shape this file:
///
/// 1. **The Brain decides what may run.** The catalogue below is what the app *offers*;
///    `command_run` on the Brain enforces its own allowlist and refuses the rest with a
///    reason. A phone that quietly thought it knew better than the machine would be a
///    second source of truth, and there is only one.
/// 2. **Commands are not chat.** Their output renders as a system row — mono type, a gold
///    rule, muted ink — so a thread that is half command output stays readable. Bubbles
///    are for words a person said.
enum SignumCommandCategory: String, CaseIterable {
    case session = "SESSION"
    case intelligence = "INTELLIGENCE"
    case tools = "TOOLS"
}

/// What a selected command does when it has no argument to collect.
enum SignumCommandAction {
    /// Handled entirely on the phone.
    case newConversation
    case stopTurn
    case retryTurn
    case openConversations
    case showHelp
    /// Runs on the Brain through `command_run`.
    case brain(String)
}

struct SignumCommand: Identifiable {
    let name: String          // without the leading slash
    let summary: String
    let category: SignumCommandCategory
    let takesArgument: Bool
    let action: SignumCommandAction

    var id: String { name }
    var display: String { "/" + name }

    /// Ordered so the palette reads top-down as most-used to least.
    static let catalogue: [SignumCommand] = [
        .init(name: "new", summary: "Start a new conversation", category: .session,
              takesArgument: false, action: .newConversation),
        .init(name: "stop", summary: "Stop the current turn", category: .session,
              takesArgument: false, action: .stopTurn),
        .init(name: "retry", summary: "Resend the last question", category: .session,
              takesArgument: false, action: .retryTurn),
        .init(name: "history", summary: "All conversations", category: .session,
              takesArgument: false, action: .openConversations),
        .init(name: "status", summary: "Model, relay, uptime", category: .intelligence,
              takesArgument: false, action: .brain("status")),
        .init(name: "relay", summary: "Chat-from-anywhere state", category: .intelligence,
              takesArgument: false, action: .brain("relay")),
        .init(name: "whoami", summary: "Identity and licence", category: .intelligence,
              takesArgument: false, action: .brain("whoami")),
        .init(name: "tools", summary: "What this Centurion can do", category: .tools,
              takesArgument: false, action: .brain("tools")),
        .init(name: "skills", summary: "Skills loaded", category: .tools,
              takesArgument: false, action: .brain("skills")),
        .init(name: "cron", summary: "Scheduled jobs", category: .tools,
              takesArgument: false, action: .brain("cron")),
        .init(name: "version", summary: "Build number", category: .tools,
              takesArgument: false, action: .brain("version")),
        .init(name: "help", summary: "This list", category: .tools,
              takesArgument: false, action: .showHelp),
    ]

    static func matches(_ query: String) -> [SignumCommand] {
        let needle = query.hasPrefix("/") ? String(query.dropFirst()) : query
        let trimmed = needle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return catalogue }
        let lowered = trimmed.lowercased()

        // Dedupe by name rather than by value: `contains(_:)` on an array of structs would
        // require Equatable conformance, and command identity is the name anyway.
        var seen: Set<String> = []
        var ordered: [SignumCommand] = []
        func take(_ candidates: [SignumCommand]) {
            for command in candidates where !seen.contains(command.name) {
                seen.insert(command.name)
                ordered.append(command)
            }
        }

        // Name first, then summary — typing "relay" and typing "anywhere" should both land.
        take(catalogue.filter { $0.name.lowercased().hasPrefix(lowered) })
        take(catalogue.filter { $0.name.lowercased().contains(lowered) })
        take(catalogue.filter { $0.summary.lowercased().contains(lowered) })
        return ordered
    }
}

/// One rendered command result. Deliberately not a `Message`: it is not part of the
/// conversation, it must not be sent to the model, and it must not survive a relaunch as
/// if the owner had said it.
struct SignumSystemEntry: Identifiable, Equatable {
    let id = UUID()
    let command: String
    let lines: [String]
    let failed: Bool
}

// MARK: - Palette

/// The floating list that appears above the composer once a `/` starts the draft.
struct SignumCommandPalette: View {
    let query: String
    let onPick: (SignumCommand) -> Void

    private var results: [SignumCommand] { SignumCommand.matches(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text("No command matches “\(query)”")
                    .font(SignumTheme.ui(13))
                    .foregroundStyle(SignumTheme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(SignumCommandCategory.allCases, id: \.self) { category in
                            let rows = results.filter { $0.category == category }
                            if !rows.isEmpty {
                                Text(category.rawValue)
                                    .font(SignumTheme.mono(9, .semibold))
                                    .tracking(1.3)
                                    .foregroundStyle(SignumTheme.goldDeep)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)

                                ForEach(rows) { command in
                                    Button {
                                        Haptics.lightTap()
                                        onPick(command)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Text(command.display)
                                                .font(SignumTheme.mono(13, .medium))
                                                .foregroundStyle(SignumTheme.ink)
                                                .frame(width: 82, alignment: .leading)

                                            Text(command.summary)
                                                .font(SignumTheme.ui(12.5))
                                                .foregroundStyle(SignumTheme.muted)
                                                .lineLimit(1)

                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(command.display), \(command.summary)")
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 260)
            }
        }
        .background(SignumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SignumTheme.hair, lineWidth: 1)
        )
        .shadow(color: SignumTheme.ink.opacity(0.08), radius: 18, y: 8)
        .padding(.horizontal, SignumTheme.Metrics.screenPadding)
    }
}

// MARK: - System row

/// Command output in the thread. Mono, ruled, quiet — the opposite of a bubble.
struct SignumSystemRow: View {
    let entry: SignumSystemEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.command.uppercased())
                .font(SignumTheme.mono(8.5, .semibold))
                .tracking(1.3)
                .foregroundStyle(entry.failed ? SignumTheme.ink : SignumTheme.goldDeep)

            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(SignumTheme.mono(11.5))
                    .foregroundStyle(entry.failed ? SignumTheme.ink : SignumTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(entry.failed ? SignumTheme.muted.opacity(0.5) : SignumTheme.gold)
                .frame(width: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}
