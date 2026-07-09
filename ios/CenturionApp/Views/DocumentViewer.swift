import SwiftUI

/// A beautiful document viewer for Centurion-created content.
/// Renders markdown-style content with warm typography matching the app's aesthetic.
/// Every document the Centurion creates can be read, shared, and saved from here.
struct DocumentViewer: View {
    let output: CenturionOutput
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    // Type badge
                    HStack(spacing: 6) {
                        Image(systemName: output.type.icon)
                            .font(.system(size: 10))
                        Text(output.type.rawValue.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(ColorTheme.accent())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ColorTheme.accent().opacity(0.1))
                    .clipShape(Capsule())

                    // Title
                    Text(output.title)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundColor(ColorTheme.primaryText())
                        .lineSpacing(4)

                    // Meta row
                    HStack(spacing: 12) {
                        if let mission = output.relatedMission {
                            Text(mission)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(ColorTheme.accent())
                        }
                        Text("\(output.wordCount) words")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ColorTheme.mutedText())
                        Text(output.sourceLoop)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    // Source path
                    Text(output.filePath)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ColorTheme.mutedText())

                    // Divider
                    Rectangle()
                        .fill(ColorTheme.accent().opacity(0.15))
                        .frame(height: 1)
                        .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.top)

                // Body — rendered as markdown-like styled text
                VStack(alignment: .leading, spacing: 16) {
                    let blocks = parseContent(output.content)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        renderedBlock(block)
                    }
                }
                .padding()
            }
            .frame(maxWidth: 428)
            .frame(maxWidth: .infinity)
        }
        .background(ColorTheme.background())
        .navigationTitle(output.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.lightTap()
                    showShare = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
        .sheet(isPresented: $showShare) {
            shareSheet
        }
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
            .padding()
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )
        }
    }

    private func styledText(_ text: String) -> String {
        text
    }

    // MARK: - Share

    private var shareSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: output.type.icon)
                    .font(.system(size: 36))
                    .foregroundColor(ColorTheme.accent())

                Text(output.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("\(output.wordCount) words • \(output.sourceLoop)")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())

                Button(action: {
                    UIPasteboard.general.string = output.content
                    Haptics.success()
                }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
                .padding()
                .background(ColorTheme.accent().opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: {
                    let activityVC = UIActivityViewController(
                        activityItems: [output.title, output.content],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = windowScene.windows.first?.rootViewController {
                        root.present(activityVC, animated: true)
                    }
                }) {
                    Label("Share...", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showShare = false }
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
        .presentationDetents([.medium])
    }
}
