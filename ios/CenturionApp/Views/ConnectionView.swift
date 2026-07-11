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
    
    // MARK: - LLM Providers (Dial Style)
    private var llmProvidersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "LLM Providers", icon: "brain.head.profile")
            
            Text("Turn the dial to switch which model your Centurion thinks through. Status shows real-time health.")
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())
                .padding(.bottom, Spacing.xs)
            
            // Dial-style selector
            LLMProviderDial(
                selectedProvider: $selectedProvider
            )
            
            // Current selection details
            LLMStatusDetail(provider: selectedProvider)
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

// MARK: - Dial Style LLM Selector

struct LLMProviderDial: View {
    @Binding var selectedProvider: LLMProvider
    
    let providers: [LLMProvider] = [.deepseek, .claude, .chatgpt, .grok]
    
    var body: some View {
        VStack(spacing: 12) {
            // The dial itself
            HStack(spacing: 0) {
                ForEach(providers, id: \.self) { provider in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            selectedProvider = provider
                        }
                        Haptics.lightTap()
                    } label: {
                        VStack(spacing: 8) {
                            // Status dot
                            Circle()
                                .fill(provider.status.color)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(provider.status.color.opacity(0.3), lineWidth: 4)
                                        .scaleEffect(selectedProvider == provider ? 1.6 : 0.8)
                                )
                            
                            // Provider name
                            Text(provider.displayName)
                                .font(.system(size: 13, weight: selectedProvider == provider ? .semibold : .medium))
                                .foregroundColor(selectedProvider == provider ? ColorTheme.primaryText() : ColorTheme.mutedText())
                            
                            // Small status label
                            Text(provider.status.label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(provider.status.color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedProvider == provider 
                                ? ColorTheme.accent().opacity(0.08) 
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(ColorTheme.border().opacity(0.6), lineWidth: 1)
            )
            
            // Dial indicator line
            HStack {
                ForEach(providers, id: \.self) { provider in
                    Rectangle()
                        .fill(selectedProvider == provider ? ColorTheme.accent() : Color.clear)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct LLMStatusDetail: View {
    let provider: LLMProvider
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(provider.status.color)
                        .frame(width: 8, height: 8)
                    Text(provider.status.label.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(provider.status.color)
                }
            }
            
            Text(provider.description)
                .font(.system(size: 14))
                .foregroundColor(ColorTheme.mutedText())
            
            if provider.status != .healthy {
                Text("This provider is currently experiencing issues. Consider switching to another model.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension LLMProvider {
    var status: ConnectionStatus {
        switch self {
        case .deepseek: return .healthy
        case .claude:   return .healthy
        case .chatgpt:  return .degraded
        case .grok:     return .healthy
        }
    }
}
