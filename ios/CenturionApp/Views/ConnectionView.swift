import SwiftUI

/// Connection Hub — the trust layer of the app.
/// 
/// This screen exists to protect the relationship between user and Centurion.
/// When LLM connections or Telegram break, users previously blamed Centurion.
/// This view makes the real state of both connections visible and actionable.
struct ConnectionView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var selectedProvider: LLMProvider = .deepseek
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    BrandHeader()
                        .padding(.bottom, Spacing.sm)
                    
                    // Purpose statement
                    VStack(spacing: 6) {
                        Text("Your Centurion stays reliable when its connections are clear.")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundColor(ColorTheme.primaryText())
                            .multilineTextAlignment(.center)
                        
                        Text("This screen shows the health of both links so you always know what’s happening.")
                            .font(.system(size: 13))
                            .foregroundColor(ColorTheme.mutedText())
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    // Remote Connection Section
                    remoteConnectionSection
                    
                    // LLM Providers Section
                    llmProvidersSection
                }
                .padding()
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Remote Connection
    private var remoteConnectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Remote Connection", icon: "antenna.radiowaves.left.and.right")
            
            Text("The link between this iPhone and your Centurion.")
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())
            
            // Status card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionManager.connectionState == .connected ? "Connected" : "Disconnected")
                        .font(.headline)
                        .foregroundColor(connectionManager.connectionState == .connected ? .green : ColorTheme.mutedText())
                    
                    Text(connectionManager.connectionState == .connected 
                         ? "Your iPhone is securely linked to your Centurion"
                         : "Tap below to connect your Centurion")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
                
                Spacer()
                
                Button {
                    // Trigger connection flow
                } label: {
                    Text(connectionManager.connectionState == .connected ? "Manage" : "Connect")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ColorTheme.accent())
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - LLM Providers
    private var llmProvidersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "LLM Providers", icon: "brain.head.profile")
            
            Text("Your Centurion thinks through these models. When one has issues, switch here instead of blaming your Centurion.")
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())
                .padding(.bottom, Spacing.xs)
            
            // DeepSeek - Primary
            LLMProviderCard(
                provider: .deepseek,
                isSelected: selectedProvider == .deepseek,
                status: .healthy,
                onSelect: { selectedProvider = .deepseek }
            )
            
            // Claude
            LLMProviderCard(
                provider: .claude,
                isSelected: selectedProvider == .claude,
                status: .healthy,
                onSelect: { selectedProvider = .claude }
            )
            
            // ChatGPT
            LLMProviderCard(
                provider: .chatgpt,
                isSelected: selectedProvider == .chatgpt,
                status: .degraded,
                onSelect: { selectedProvider = .chatgpt }
            )
            
            // Grok
            LLMProviderCard(
                provider: .grok,
                isSelected: selectedProvider == .grok,
                status: .healthy,
                onSelect: { selectedProvider = .grok }
            )
            
            Text("We recommend DeepSeek for most people. It’s fast, capable, and reliable.")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.accent().opacity(0.8))
                .italic()
                .padding(.top, Spacing.xs)
        }
    }
}

// MARK: - Supporting Views

struct LLMProviderCard: View {
    let provider: LLMProvider
    let isSelected: Bool
    let status: ConnectionStatus
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(provider.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(ColorTheme.primaryText())
                        
                        if provider == .deepseek {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ColorTheme.accent())
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(provider.description)
                        .font(.system(size: 13))
                        .foregroundColor(ColorTheme.mutedText())
                }
                
                Spacer()
                
                // Status indicator
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                        
                        Text(status.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(status.color)
                    }
                    
                    if isSelected {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ColorTheme.accent())
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? ColorTheme.accent().opacity(0.06) : ColorTheme.surface())
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? ColorTheme.accent().opacity(0.4) : ColorTheme.border(), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

enum LLMProvider {
    case deepseek, claude, chatgpt, grok
    
    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .claude:   return "Claude"
        case .chatgpt:  return "ChatGPT"
        case .grok:     return "Grok"
        }
    }
    
    var description: String {
        switch self {
        case .deepseek: return "Fast, powerful, and cost-effective. Our primary recommendation."
        case .claude:   return "Excellent reasoning and long context. Great for complex tasks."
        case .chatgpt:  return "Widely capable with strong general knowledge."
        case .grok:     return "Real-time knowledge with a helpful, maximum-truth-seeking personality."
        }
    }
}

enum ConnectionStatus {
    case healthy, degraded, broken
    
    var label: String {
        switch self {
        case .healthy:  return "Healthy"
        case .degraded: return "Degraded"
        case .broken:   return "Issue"
        }
    }
    
    var color: Color {
        switch self {
        case .healthy:  return .green
        case .degraded: return .orange
        case .broken:   return .red
        }
    }
}
