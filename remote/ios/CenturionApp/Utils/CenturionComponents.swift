import SwiftUI

// MARK: - Radius

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let pill: CGFloat = 999
}

// MARK: - Elevation

enum Elevation {
    static func cardShadow(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : ColorTheme.agedBronze().opacity(0.12)
    }

    static let cardRadius: CGFloat = 8
    static let cardYOffset: CGFloat = 4
}

// MARK: - Typography

enum Typography {
    static var brandWordmark: Font {
        .system(size: 11, weight: .semibold, design: .default)
    }

    static var editorialTitle: Font {
        .system(.title2, design: .serif).weight(.bold)
    }

    static var screenTitle: Font {
        .title3.weight(.semibold)
    }

    static var sectionLabel: Font {
        .caption.weight(.semibold)
    }
}

// MARK: - Compact Brand Header

/// Main tab header — mark + Sovereign AI Remote product wordmark.
struct CompactBrandHeader: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            CenturionAppMark(size: 28)
            Text("SOVEREIGN AI REMOTE")
                .font(Typography.brandWordmark)
                .foregroundColor(ColorTheme.mutedText())
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sovereign AI Remote")
    }
}

// MARK: - Full Brand Header

/// Secondary screens — product name, company, tagline.
struct FullBrandHeader: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.08))
                    .frame(width: 72, height: 72)
                CenturionAppMark(size: 56)
            }
            VStack(spacing: 4) {
                Text("Sovereign AI Remote")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("by Centurion")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.mutedText())
                Text("1 Human 1 AI")
                    .font(.caption)
                    .foregroundColor(ColorTheme.dimAccent())
                    .tracking(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sovereign AI Remote by Centurion. 1 Human 1 AI.")
    }
}

// MARK: - Sheet Header

struct SheetHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Typography.screenTitle)
                .foregroundColor(ColorTheme.primaryText())
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Main Tab Chrome

/// Award-level main tab layout: compact brand + optional chrome + content.
struct MainTabChrome<Header: View, Content: View>: View {
    let screenTitle: String?
    let header: Header
    let content: Content

    init(
        screenTitle: String? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.screenTitle = screenTitle
        self.header = header()
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CompactBrandHeader()
                if let screenTitle {
                    Text(screenTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.mutedText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                }
                header
                content
            }
            .background(
                ZStack {
                    ColorTheme.background()
                    ColorTheme.atmosphericVeil()
                        .ignoresSafeArea()
                }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

extension MainTabChrome where Header == EmptyView {
    init(
        screenTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.screenTitle = screenTitle
        self.header = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(screenTitle: title, content: content)
    }
}

extension MainTabChrome {
    init(
        title: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.init(screenTitle: title, header: header, content: content)
    }
}

/// Back-compat alias.
typealias TabPageChrome = MainTabChrome

// MARK: - Secondary Screen Chrome

struct SecondaryScreenChrome<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()
                content
            }
            .padding()
        }
        .background(ColorTheme.background())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Metallic Rim

struct MetallicRim: View {
    var diameter: CGFloat = 120
    var opacity: Double = 0.55

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.04, to: 0.2)
                    .stroke(
                        OrbDesign.metallicRimGradient(accent: ColorTheme.accent()),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(Double(index) * 120))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Atmospheric Surface

struct AtmosphericSurface<Content: View>: View {
    var elevated: Bool = false
    var showRim: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Spacing.md)
            .background(
                ZStack {
                    (elevated ? ColorTheme.surfaceElevated() : ColorTheme.surface())
                    RadialGradient(
                        colors: [
                            ColorTheme.atmosphereTeal().opacity(0.06),
                            Color.clear,
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )
            .overlay {
                if showRim {
                    MetallicRim(diameter: 80, opacity: 0.25)
                }
            }
    }
}

// MARK: - Card modifier v2

struct CenturionCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(elevated ? ColorTheme.surfaceElevated() : ColorTheme.surface())
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(ColorTheme.border(), lineWidth: 0.5)
            )
            .shadow(
                color: Elevation.cardShadow(colorScheme: colorScheme),
                radius: Elevation.cardRadius,
                x: 0,
                y: Elevation.cardYOffset
            )
    }
}

extension View {
    func centurionCard(elevated: Bool = false) -> some View {
        modifier(CenturionCardModifier(elevated: elevated))
    }

    /// Legacy alias
    func cardStyle() -> some View {
        centurionCard()
    }
}

// MARK: - Buttons

struct CenturionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(ColorTheme.onAccent())
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm + 2)
            .padding(.horizontal, Spacing.lg)
            .background(ColorTheme.accent().opacity(isEnabled ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(Motion.light, value: configuration.isPressed)
    }
}

struct CenturionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundColor(ColorTheme.accent())
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm + 2)
            .padding(.horizontal, Spacing.lg)
            .background(ColorTheme.accent().opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(ColorTheme.accent().opacity(0.25), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.light, value: configuration.isPressed)
    }
}

struct CenturionGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(ColorTheme.accent())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.light, value: configuration.isPressed)
    }
}

// MARK: - Section Header (v2)

struct CenturionSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.accent())
            Text(title)
                .font(Typography.sectionLabel)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundColor(ColorTheme.mutedText())
            Spacer()
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [ColorTheme.border(), ColorTheme.accent().opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .frame(maxWidth: 48)
        }
    }
}

// MARK: - Status Card (Connect)

struct CenturionStatusCard: View {
    let title: String
    let icon: String
    let headline: String
    let detail: String
    let isPositive: Bool
    var accessibilityLabel: String

    var body: some View {
        AtmosphericSurface(elevated: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())
                    Text(title.uppercased())
                        .font(Typography.sectionLabel)
                        .tracking(1.5)
                        .foregroundColor(ColorTheme.mutedText())
                    Spacer()
                    StatusDot(isConnected: isPositive)
                }
                Text(headline)
                    .font(Typography.screenTitle)
                    .foregroundColor(ColorTheme.primaryText())
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .lineSpacing(3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - List Row

struct CenturionListRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(ColorTheme.accent())
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText())
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(2)
                }
            }
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - Pill Nav

struct CenturionPillNav<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    var badge: (Item) -> Int = { _ in 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(items, id: \.self) { item in
                    pillButton(for: item)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func pillButton(for item: Item) -> some View {
        let isSelected = selection == item
        let count = badge(item)
        return Button {
            Haptics.lightTap()
            withAnimation(Motion.standard) { selection = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(item))
                    .font(.caption.weight(.semibold))
                Text(title(item))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ColorTheme.onAccent())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ColorTheme.accent())
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? ColorTheme.onAccent() : ColorTheme.primaryText())
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Group {
                    if isSelected {
                        ColorTheme.accent()
                    } else {
                        ColorTheme.surface()
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : ColorTheme.border(), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(item))\(count > 0 ? ", \(count) new" : "")")
    }
}

// MARK: - State Components

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(ColorTheme.accent().opacity(0.6))
            Text(title)
                .font(Typography.editorialTitle)
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct LoadingState: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .tint(ColorTheme.accent())
                .scaleEffect(1.1)
            Text(message)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct ErrorState: View {
    let title: String
    let message: String
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36))
                .foregroundColor(ColorTheme.mutedText())
            Text(title)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())
            Text(message)
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(CenturionSecondaryButtonStyle())
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct SuccessMoment: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(ColorTheme.success())
            Text(title)
                .font(Typography.screenTitle)
                .foregroundColor(ColorTheme.primaryText())
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .onAppear { Haptics.success() }
    }
}

// MARK: - Reassurance Row

struct CenturionReassuranceRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        CenturionListRow(
            icon: icon,
            title: title,
            subtitle: detail,
            showChevron: false
        )
    }
}
