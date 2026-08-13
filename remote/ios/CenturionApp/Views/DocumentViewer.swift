import SwiftUI

/// A beautiful document viewer for Centurion-created content.
/// Renders markdown-style content with warm typography matching the app's aesthetic.
/// Every document the Sovereign creates can be read, shared, and saved from here.
struct DocumentViewer: View {
    let output: CenturionOutput
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                documentHeader

                VStack(alignment: .leading, spacing: Spacing.md) {
                    let blocks = parseContent(output.content)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        renderedBlock(block)
                    }
                }
                .padding(Spacing.md)
            }
            .frame(maxWidth: 428)
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.lightTap()
                    showShare = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .foregroundColor(ColorTheme.accent())
                }
                .accessibilityLabel("Share document")
            }
        }
        .sheet(isPresented: $showShare) {
            shareSheet
        }
    }

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: output.type.icon)
                    .font(.caption.weight(.semibold))
                Text(output.type.rawValue.uppercased())
                    .font(Typography.sectionLabel)
                    .tracking(1.5)
            }
            .foregroundColor(ColorTheme.accent())
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(ColorTheme.accent().opacity(0.1))
            .clipShape(Capsule())

            Text(output.title)
                .font(Typography.editorialTitle)
                .foregroundColor(ColorTheme.primaryText())
                .lineSpacing(4)

            HStack(spacing: Spacing.sm) {
                if let mission = output.relatedMission {
                    Text(mission)
                        .font(.caption.weight(.medium))
                        .foregroundColor(ColorTheme.accent())
                }
                Text("\(output.wordCount) words")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                Text(output.sourceLoop)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }

            Text(output.filePath)
                .font(.caption2.monospaced())
                .foregroundColor(ColorTheme.mutedText())

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [ColorTheme.accent().opacity(0.15), ColorTheme.border()],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
    }

    // MARK: - Content Rendering

    private struct ContentBlock {
        let type: BlockType
        let text: String
        let level: Int  // For headings

        enum BlockType {
            case h1, h2, h3
            case paragraph
            case bullet
            case numbered(Int)
            case divider
            case code
        }
    }

    private func parseContent(_ content: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var codeBuffer: [String] = []
        var inCode = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    if !codeBuffer.isEmpty {
                        blocks.append(ContentBlock(type: .code, text: codeBuffer.joined(separator: "\n"), level: 0))
                        codeBuffer = []
                    }
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }

            if inCode {
                codeBuffer.append(line)
                continue
            }

            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("### ") {
                blocks.append(ContentBlock(type: .h3, text: String(trimmed.dropFirst(4)), level: 3))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(ContentBlock(type: .h2, text: String(trimmed.dropFirst(3)), level: 2))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(ContentBlock(type: .h1, text: String(trimmed.dropFirst(2)), level: 1))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(ContentBlock(type: .bullet, text: text, level: 0))
            } else if trimmed.allSatisfy({ $0 == "-" || $0 == "=" || $0 == "*" }) {
                blocks.append(ContentBlock(type: .divider, text: "", level: 0))
            } else if let match = trimmed.firstMatch(of: try! Regex("^(\\d+)\\.\\s+(.*)")) {
                let num = Int(trimmed.prefix(while: { $0.isNumber })) ?? 0
                let text = String(trimmed.dropFirst("\(num). ".count))
                blocks.append(ContentBlock(type: .numbered(num), text: text, level: 0))
            } else {
                blocks.append(ContentBlock(type: .paragraph, text: trimmed, level: 0))
            }
        }

        if !codeBuffer.isEmpty {
            blocks.append(ContentBlock(type: .code, text: codeBuffer.joined(separator: "\n"), level: 0))
        }

        return blocks
    }

    @ViewBuilder
    private func renderedBlock(_ block: ContentBlock) -> some View {
        switch block.type {
        case .h1:
            Text(block.text)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .padding(.top, 8)

        case .h2:
            Text(block.text)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .padding(.top, 6)

        case .h3:
            Text(block.text)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .padding(.top, 4)

        case .paragraph:
            Text(styledText(block.text))
                .font(.system(size: 14, design: .default))
                .foregroundColor(ColorTheme.primaryText())
                .lineSpacing(6)

        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(ColorTheme.accent())
                    .font(.system(size: 14, weight: .bold))
                Text(styledText(block.text))
                    .font(.system(size: 14, design: .default))
                    .foregroundColor(ColorTheme.primaryText())
                    .lineSpacing(6)
            }
            .padding(.leading, 4)

        case .numbered(let num):
            HStack(alignment: .top, spacing: 8) {
                Text("\(num).")
                    .foregroundColor(ColorTheme.accent())
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 24, alignment: .leading)
                Text(styledText(block.text))
                    .font(.system(size: 14, design: .default))
                    .foregroundColor(ColorTheme.primaryText())
                    .lineSpacing(6)
            }
            .padding(.leading, 4)

        case .divider:
            Rectangle()
                .fill(ColorTheme.accent().opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .lineSpacing(4)
            }
            .centurionCard()
        }
    }

    private func styledText(_ text: String) -> String {
        text
    }

    // MARK: - Share

    private var shareSheet: some View {
        VStack(spacing: Spacing.lg) {
            SheetHeader(title: "Share", subtitle: output.title)

            Image(systemName: output.type.icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(ColorTheme.accent().opacity(0.7))

            Text("\(output.wordCount) words · \(output.sourceLoop)")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())

            Button {
                UIPasteboard.general.string = output.content
                Haptics.success()
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            .buttonStyle(CenturionSecondaryButtonStyle())
            .padding(.horizontal, Spacing.md)

            Button {
                let activityVC = UIActivityViewController(
                    activityItems: [output.title, output.content],
                    applicationActivities: nil
                )
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = windowScene.windows.first?.rootViewController {
                    root.present(activityVC, animated: true)
                }
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .padding(.horizontal, Spacing.md)

            Spacer()
        }
        .padding(.top, Spacing.lg)
        .background(ColorTheme.background())
        .presentationDetents([.medium])
    }
}
