import SwiftUI

/// Design system — the physics, rhythm, and soul of the Sovereign app.
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

// MARK: - Deferred Tab Content

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
            Image(systemName: "eye.slash")
                .font(.subheadline)
                .foregroundColor(ColorTheme.accent())
            VStack(alignment: .leading, spacing: 2) {
                Text("Not linked to a Brain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Any layout below is demo only — not live Crypto Chat. Open You → Connect to pair.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(ColorTheme.accent().opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(ColorTheme.accent().opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not linked to a Brain. Demo only — open You, Connect to pair.")
    }
}

// MARK: - Orb Design System

/// Living orb vocabulary — collaborations (Swarm) and Life Mission (Mission).
/// Motion states are locked; materials and atmosphere enhance emotional read.
enum OrbDesign {
    // MARK: Colors

    static let humanGold = ColorTheme.accent()
    static let atmosphereTeal = ColorTheme.atmosphereTeal()
    static let agedBronze = ColorTheme.accent()
    static let pearlHighlight = ColorTheme.pearlHighlight()

    static func centurionAccent(index: Int) -> Color {
        let palette = [
            ColorTheme.accent(),
            ColorTheme.accent().opacity(0.72),
            ColorTheme.mutedText(),
        ]
        return palette[index % palette.count]
    }

    // MARK: Motion durations (paired with existing pulse triggers)

    enum Duration {
        static let idleBreath: Double = 3.5
        static let activeBreath: Double = 3.0
        static let activeOrbit: Double = 10.0
        static let attentionBeacon: Double = 0.8
        static let waitingBeacon: Double = 1.2
        static let blockedThrob: Double = 2.5
        static let mistDrift: Double = 5.5
        static let missionBreath: Double = 6.0
        static let invitationRipple: Double = 2.4
    }

    // MARK: Materials

    static func coreGradient(accent: Color, intensity: Double = 1.0) -> RadialGradient {
        RadialGradient(
            colors: [
                pearlHighlight.opacity(0.95 * intensity),
                accent.opacity(0.92 * intensity),
                accent.opacity(0.55 * intensity),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 24
        )
    }

    static func atmosphereGradient(accent: Color) -> RadialGradient {
        RadialGradient(
            colors: [
                accent.opacity(0.22),
                atmosphereTeal.opacity(0.08),
                Color.clear,
            ],
            center: .center,
            startRadius: 8,
            endRadius: 80
        )
    }

    static func metallicRimGradient(accent: Color) -> AngularGradient {
        AngularGradient(
            colors: [
                accent.opacity(0.65),
                agedBronze.opacity(0.45),
                accent.opacity(0.15),
                pearlHighlight.opacity(0.35),
                accent.opacity(0.65),
            ],
            center: .center
        )
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

// MARK: - Section Header (see CenturionSectionHeader in CenturionComponents.swift)
typealias SectionHeader = CenturionSectionHeader

// MARK: - Premium Button Styles

typealias AmberButtonStyle = CenturionPrimaryButtonStyle

// MARK: - Connection Status Dot

/// Connection status chip — green when linked, amber when linked but thinking needs attention.
struct StatusDot: View {
    let isConnected: Bool
    var isEncrypted: Bool = false
    /// When linked but the thinking service is unhealthy / unknown.
    var needsAttention: Bool = false

    @State private var isPulsing = false

    private var dotColor: Color {
        if !isConnected { return ColorTheme.mutedText() }
        if needsAttention { return ColorTheme.warning() }
        return ColorTheme.success()
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(isConnected ? dotColor : Color.clear, lineWidth: 2)
                        .scaleEffect(isPulsing ? 1.6 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                )
            if isConnected && isEncrypted {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(dotColor)
                    .accessibilityLabel("Crypto Chat encrypted")
            }
        }
        .accessibilityLabel(
            isConnected
                ? (needsAttention
                    ? "Linked, but thinking needs attention"
                    : "Linked and ready")
                : "Not linked"
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

/// Crypto Chat status — the private encrypted conversation channel public AIs do not offer.
struct EncryptionStatusBadge: View {
    let isEncrypted: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: isEncrypted ? "lock.shield.fill" : "lock.open")
                .font(.caption.weight(.semibold))
            Text(isEncrypted ? "Crypto Chat" : "Crypto Chat off")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(isEncrypted ? ColorTheme.success() : ColorTheme.mutedText())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isEncrypted
                      ? ColorTheme.success().opacity(0.12)
                      : ColorTheme.mutedText().opacity(0.08))
        )
        .accessibilityLabel(
            isEncrypted
                ? "Crypto Chat on — private encrypted conversation with your Sovereign"
                : "Crypto Chat off"
        )
    }
}

// MARK: - App Icon

/// The same mark shown on the Home Screen and simulator — used for in-app branding.
struct CenturionAppMark: View {
    var size: CGFloat = 64

    private var cornerRadius: CGFloat { size * 0.223 }

    var body: some View {
        Image("AppMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel("Sovereign app icon")
    }
}

// MARK: - App Brand Header (legacy — prefer FullBrandHeader)

/// @deprecated Use `FullBrandHeader` for secondary screens.
struct BrandHeader: View {
    var body: some View {
        FullBrandHeader()
    }
}
