import SwiftUI

/// Reusable comment sheet for any mission level (program, target, task).
/// Shows full comment history + new comment input.
/// The Centurion sees exactly what context the comment came from.
struct MissionCommentSheet: View {
    let title: String
    let contextPath: String
    @Binding var comments: [MissionComment]
    @State private var newCommentText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    /// Callback when a new comment is submitted (wires to Centurion)
    var onSend: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Context header
                contextHeader
                
                // Comments list
                ScrollView {
                    VStack(spacing: Spacing.sm) {
                        if comments.isEmpty {
                            emptyState
                        } else {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Input bar
                inputBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Context Header
    
    private var contextHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
            Text(contextPath)
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
                .lineLimit(1)
            Spacer()
            Text("\(comments.count)")
                .font(.caption2)
                .foregroundColor(ColorTheme.mutedText())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ColorTheme.border())
                .clipShape(Capsule())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorTheme.accent().opacity(0.05))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer().frame(height: 40)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundColor(ColorTheme.mutedText())
            Text("No comments yet")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())
            Text("Leave a comment for your Centurion. They'll see the full context.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Comment Row
    
    private func commentRow(_ comment: MissionComment) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Author avatar
            ZStack {
                Circle()
                    .fill(comment.author == .centurion
                          ? ColorTheme.accent().opacity(0.15)
                          : ColorTheme.mutedText().opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: comment.author == .centurion ? "cpu" : "person.fill")
                    .font(.system(size: 11))
                    .foregroundColor(comment.author == .centurion
                                     ? ColorTheme.accent() : ColorTheme.mutedText())
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(comment.author == .centurion
                                         ? ColorTheme.accent() : ColorTheme.primaryText())
                    Text(comment.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.mutedText())
                }
                
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.primaryText())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(comment.author == .centurion
                    ? ColorTheme.accent().opacity(0.03)
                    : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Write a comment…", text: $newCommentText)
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
            
            Button(action: sendComment) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? ColorTheme.mutedText() : ColorTheme.accent()
                    )
            }
            .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }
    
    private func sendComment() {
        let text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        Haptics.messageSent()
        
        let comment = MissionComment(
            id: UUID(),
            parentId: UUID(),
            parentType: .program,
            text: text,
            author: .human,
            timestamp: Date()
        )
        
        withAnimation(Motion.appear) {
            comments.append(comment)
        }
        
        onSend?(text)
        newCommentText = ""
    }
}
