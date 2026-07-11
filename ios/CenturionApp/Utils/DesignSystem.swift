import SwiftUI

/// Design system — the physics, rhythm, and soul of the Centurion app.
/// Every number, curve, and gesture is intentional. Nothing is default.

// MARK: - Motion Design

/// Spring-driven motion that gives UI elements physical weight.
/// Inspired by the Not Boring suite and Things 3.
enum Motion {
    /// Standard spring for most interactions — responsive with natural overshoot
    static let standard: Animation = .spring(response: 0.45, dampingFraction: 0.70, blendDuration: 0.1)
    
    /// For elements that enter the screen (bubbles, cards appearing)
    static let appear: Animation = .spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.15)
    
    /// For heavy elements (sheets, transitions)
    static let heavy: Animation = .spring(response: 0.65, dampingFraction: 0.60, blendDuration: 0.2)
    
    /// For light elements (badges, indicators) — snappy
    static let light: Animation = .spring(response: 0.30, dampingFraction: 0.75, blendDuration: 0.05)
    
    /// Celebratory bouncy spring
    static let celebratory: Animation = .spring(response: 0.50, dampingFraction: 0.50, blendDuration: 0.1)
}

// MARK: - Haptic Design

/// Physics-grounded haptic feedback for every meaningful interaction.
/// From the Not Boring philosophy: every touch should feel physical.
enum Haptics {
    static func lightTap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    static func mediumTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    static func heavyTap() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    static func connectionEstablished() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    static func messageSent() {
        // Light + medium cascade for send
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Spacing Scale

/// Consistent visual rhythm — every space is a multiple of 4.
/// No magic numbers. No guessing.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Card Style

/// Reusable card modifier — every surface card in the app uses this.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Tab Page Chrome

/// Uniform layout for main tabs: inline nav title, optional header row, no app branding.
struct TabPageChrome<Header: View, Content: View>: View {
    let title: String
    let header: Header
    let content: Content

    init(
        title: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.header = header()
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(ColorTheme.background())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension TabPageChrome where Header == EmptyView {
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.header = EmptyView()
        self.content = content()
    }
}

/// Defers heavy tab content until first visit, then preserves state when switching tabs.
struct DeferredTabContent<Content: View>: View {
    let tag: Int
    @Binding var selection: Int
    @Binding var loadedTabs: Set<Int>
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if loadedTabs.contains(tag) {
                content()
                    .opacity(selection == tag ? 1 : 0)
                    .allowsHitTesting(selection == tag)
                    .accessibilityHidden(selection != tag)
            } else {
                Color.clear
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == tag {
                loadedTabs.insert(tag)
            }
        }
        .onAppear {
            if selection == tag {
                loadedTabs.insert(tag)
            }
        }
    }
}

// MARK: - Demo Data Banner

/// Labels sample content so users are never misled while disconnected.
struct DemoDataBanner: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundColor(ColorTheme.accent())
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample activity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Connect your Centurion to see live updates.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(ColorTheme.accent().opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.accent().opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample activity. Connect your Centurion to see live updates.")
    }
}

// MARK: - Reduce Motion

extension View {
    @ViewBuilder
    func centurionAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Section Header

/// Premium section header with amber accent line
struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ColorTheme.accent())
            
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .textCase(.uppercase)
                .foregroundColor(ColorTheme.mutedText())
            
            Spacer()
            
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 1)
                .frame(maxWidth: 60)
        }
    }
}

// MARK: - Premium Button Styles

struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(ColorTheme.accent())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Motion.light, value: configuration.isPressed)
    }
}

// MARK: - Connection Status Dot

/// Animated connection indicator — glowing amber pulse
struct StatusDot: View {
    let isConnected: Bool
    
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(isConnected ? ColorTheme.success() : ColorTheme.mutedText())
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(isConnected ? ColorTheme.success() : Color.clear, lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
            )
            .onAppear {
                if isConnected {
                    withAnimation(Motion.heavy.repeatForever(autoreverses: false)) {
                        isPulsing = true
                    }
                }
            }
    }
}

// MARK: - App Brand Header

/// Consistent brand header for every page — Icon + name + version.
/// Replaces all toolbar principals and page titles with one unified layout.
struct BrandHeader: View {
    var body: some View {
        VStack(spacing: 8) {
            // Architectural icon with warm glow — Frank Lloyd Wright inspired
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.08))
                    .frame(width: 52, height: 52)
                
                Image(systemName: "app.connected.to.app.below.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(ColorTheme.accent())
            }
            
            VStack(spacing: 2) {
                Text("PERSONAL-CENTURION")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(4)
                
                Text("AI REMOTE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(ColorTheme.accent())
                    .tracking(4)
            }
            
            // Prairie-style horizontal accent line — organic, warm, timeless
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            ColorTheme.accent().opacity(0.2),
                            ColorTheme.accent(),
                            ColorTheme.accent().opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 120, height: 1)
                .padding(.vertical, 2)
            
            Text("MISSION HORIZON  ·  v3.0.0")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(ColorTheme.dimAccent())
                .tracking(2)
            
            // The emotional promise — your lifelong companion
            Text("Your AI. Your mission. For life.")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundColor(ColorTheme.mutedText().opacity(0.7))
                .italic()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
