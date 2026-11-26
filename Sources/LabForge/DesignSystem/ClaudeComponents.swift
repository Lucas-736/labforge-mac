import SwiftUI

// MARK: - Spacing & radii (DESIGN.md)

enum ClaudeSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum ClaudeRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

// MARK: - Brand mark

/// LabForge mark: an editorial 8-spoke spark — four long tapered spokes on the axes and four
/// shorter diagonals — echoing Claude's radial spike glyph, read as a spark struck off an anvil.
struct SparkMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let isLong = i % 2 == 0
            let length = r * (isLong ? 1.0 : 0.62)
            let halfWidth = r * (isLong ? 0.13 : 0.11)
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -dir.y, y: dir.x)
            let base = r * 0.10
            let tip = CGPoint(x: c.x + dir.x * length, y: c.y + dir.y * length)
            let b1 = CGPoint(x: c.x + dir.x * base + normal.x * halfWidth, y: c.y + dir.y * base + normal.y * halfWidth)
            let b2 = CGPoint(x: c.x + dir.x * base - normal.x * halfWidth, y: c.y + dir.y * base - normal.y * halfWidth)
            path.move(to: c)
            path.addLine(to: b1)
            path.addQuadCurve(to: tip, control: CGPoint(x: c.x + dir.x * length * 0.55 + normal.x * halfWidth * 0.55,
                                                        y: c.y + dir.y * length * 0.55 + normal.y * halfWidth * 0.55))
            path.addQuadCurve(to: b2, control: CGPoint(x: c.x + dir.x * length * 0.55 - normal.x * halfWidth * 0.55,
                                                       y: c.y + dir.y * length * 0.55 - normal.y * halfWidth * 0.55))
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(x: c.x - r * 0.16, y: c.y - r * 0.16, width: r * 0.32, height: r * 0.32))
        return path
    }
}

struct LabForgeMarkView: View {
    var size: CGFloat = 22
    var color: Color = ClaudePalette.primary

    var body: some View {
        SparkMarkShape()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityLabel("LabForge")
    }
}

/// Mark + serif wordmark.
struct LabForgeWordmark: View {
    var markSize: CGFloat = 22
    var fontSize: CGFloat = 20
    var color: Color = ClaudePalette.ink

    var body: some View {
        HStack(spacing: 8) {
            LabForgeMarkView(size: markSize)
            Text("LabForge")
                .claudeDisplay(fontSize, tracking: -0.4)
                .foregroundStyle(color)
            Text("研铸")
                .font(ClaudeTypography.serif(fontSize * 0.72))
                .foregroundStyle(ClaudePalette.muted)
        }
    }
}

// MARK: - Buttons

/// `button-primary`: coral fill, white text, 8pt radius, 40pt height; darkens on press.
struct ClaudePrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var height: CGFloat = 40
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClaudeTypography.button)
            .foregroundStyle(isEnabled ? ClaudePalette.onPrimary : ClaudePalette.muted)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                    .fill(isEnabled
                          ? (configuration.isPressed ? ClaudePalette.primaryActive : ClaudePalette.primary)
                          : ClaudePalette.primaryDisabled)
            )
            .contentShape(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous))
    }
}

/// `button-secondary`: canvas fill, ink text, 1px hairline border.
struct ClaudeSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var height: CGFloat = 40
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? ClaudeTypography.caption : ClaudeTypography.button)
            .foregroundStyle(isEnabled ? ClaudePalette.ink : ClaudePalette.mutedSoft)
            .padding(.horizontal, compact ? 12 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 30 : height)
            .background(
                RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                    .fill(configuration.isPressed ? ClaudePalette.surfaceCard : ClaudePalette.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                    .strokeBorder(ClaudePalette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous))
    }
}

/// `button-secondary-on-dark`: elevated dark fill, on-dark text. Never inverts to light.
struct ClaudeSecondaryOnDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClaudeTypography.button)
            .foregroundStyle(ClaudePalette.onDark)
            .padding(.horizontal, 20)
            .frame(minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                    .fill(configuration.isPressed ? ClaudePalette.surfaceDarkSoft : ClaudePalette.surfaceDarkElevated)
            )
            .contentShape(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous))
    }
}

/// `button-text-link` / small inline icon actions.
struct ClaudeTextButtonStyle: ButtonStyle {
    var color: Color = ClaudePalette.muted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClaudeTypography.caption)
            .foregroundStyle(configuration.isPressed ? ClaudePalette.ink : color)
            .contentShape(Rectangle())
    }
}

/// `button-icon-circular`: 30–36pt circle, canvas fill, hairline border.
struct ClaudeIconButtonStyle: ButtonStyle {
    var size: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(ClaudePalette.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(configuration.isPressed ? ClaudePalette.surfaceCard : ClaudePalette.canvas))
            .overlay(Circle().strokeBorder(ClaudePalette.hairline, lineWidth: 1))
            .contentShape(Circle())
    }
}

// MARK: - Cards

enum ClaudeCardSurface {
    case card      // surface-card, no border (feature-card)
    case canvas    // canvas + hairline (model-comparison / connector tile)
    case soft      // surface-soft + hairline
    case dark      // fixed surface-dark (product-mockup-card-dark)
}

struct ClaudeCardModifier: ViewModifier {
    var surface: ClaudeCardSurface = .canvas
    var padding: CGFloat = 24
    var radius: CGFloat = ClaudeRadius.lg

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    private var fill: Color {
        switch surface {
        case .card: return ClaudePalette.surfaceCard
        case .canvas: return ClaudePalette.canvas
        case .soft: return ClaudePalette.surfaceSoft
        case .dark: return ClaudePalette.surfaceDark
        }
    }

    private var border: Color {
        switch surface {
        case .card: return ClaudePalette.hairline.opacity(0.6)
        case .canvas, .soft: return ClaudePalette.hairline
        case .dark: return Color.clear
        }
    }
}

extension View {
    func claudeCard(_ surface: ClaudeCardSurface = .canvas, padding: CGFloat = 24, radius: CGFloat = ClaudeRadius.lg) -> some View {
        modifier(ClaudeCardModifier(surface: surface, padding: padding, radius: radius))
    }
}

/// Container form of `claudeCard`.
struct ClaudeCard<Content: View>: View {
    var surface: ClaudeCardSurface = .canvas
    var padding: CGFloat = 24
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .claudeCard(surface, padding: padding)
    }
}

/// Card title row: sans title + optional muted trailing caption.
struct ClaudeCardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClaudeTypography.titleMD)
                    .foregroundStyle(ClaudePalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.muted)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension ClaudeCardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Serif page header used by every workbench tab.
struct ClaudePageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow).claudeEyebrow(ClaudePalette.primary)
                Text(title)
                    .claudeDisplay(34)
                    .foregroundStyle(ClaudePalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(ClaudeTypography.bodyMD)
                        .foregroundStyle(ClaudePalette.muted)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
    }
}

extension ClaudePageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Badges

/// `badge-pill` (surface-card) or `badge-coral` (primary fill, uppercase caption).
struct ClaudeBadgePill: View {
    enum Style { case neutral, coral, amber, outline, onDark }

    let text: String
    var systemImage: String? = nil
    var style: Style = .neutral

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10.5, weight: .medium))
            }
            Text(text)
                .font(style == .coral ? ClaudeTypography.captionUppercase : ClaudeTypography.caption)
                .tracking(style == .coral ? 1.0 : 0)
        }
        .lineLimit(1)
        .foregroundStyle(foreground)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(style == .outline ? ClaudePalette.hairline : Color.clear, lineWidth: 1))
    }

    private var foreground: Color {
        switch style {
        case .neutral, .outline: return ClaudePalette.ink
        case .coral: return ClaudePalette.onPrimary
        case .amber: return ClaudePalette.adaptive(0x6B4513, 0xF3D09E)
        case .onDark: return ClaudePalette.onDark
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return ClaudePalette.surfaceCard
        case .coral: return ClaudePalette.primary
        case .amber: return ClaudePalette.accentAmber.opacity(0.28)
        case .outline: return Color.clear
        case .onDark: return ClaudePalette.surfaceDarkElevated
        }
    }
}

/// Streak flame badge.
struct StreakFlameBadge: View {
    let streak: Int
    var lit: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(lit ? ClaudePalette.primary : ClaudePalette.mutedSoft)
            Text("\(streak) 天")
                .font(ClaudeTypography.number(12, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(ClaudePalette.surfaceCard))
    }
}

/// Small live status dot (teal when running, muted when idle).
struct StatusDot: View {
    let active: Bool
    var body: some View {
        Circle()
            .fill(active ? ClaudePalette.accentTeal : ClaudePalette.mutedSoft)
            .frame(width: 7, height: 7)
    }
}

// MARK: - Inputs

/// Draws the `text-input` chrome: canvas fill, 1px hairline → coral when focused + 3px coral ring at 15%.
struct ClaudeFieldChrome: ViewModifier {
    let isFocused: Bool
    var radius: CGFloat = ClaudeRadius.md

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(shape.fill(ClaudePalette.canvas))
            .overlay(shape.strokeBorder(isFocused ? ClaudePalette.primary : ClaudePalette.hairline, lineWidth: 1))
            .background(
                shape.inset(by: -3)
                    .strokeBorder(isFocused ? ClaudePalette.focusRing : Color.clear, lineWidth: 3)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    /// DESIGN.md text-input and focused-state chrome.
    func claudeTextField(height: CGFloat = 40) -> some View {
        modifier(ClaudeFocusableFieldModifier(height: height))
    }
}

private struct ClaudeFocusableFieldModifier: ViewModifier {
    nonisolated let height: CGFloat
    @FocusState private var focused: Bool

    nonisolated init(height: CGFloat) {
        self.height = height
    }

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(ClaudeTypography.bodyMD)
            .foregroundStyle(ClaudePalette.ink)
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .modifier(ClaudeFieldChrome(isFocused: focused))
    }
}

/// Multiline editor with the same hairline / coral-focus chrome.
struct ClaudeTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 96
    var isDisabled = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(ClaudeTypography.bodyMD)
                .foregroundStyle(ClaudePalette.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .disabled(isDisabled)
            if text.isEmpty {
                Text(placeholder)
                    .font(ClaudeTypography.bodyMD)
                    .foregroundStyle(ClaudePalette.mutedSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .modifier(ClaudeFieldChrome(isFocused: focused))
        .opacity(isDisabled ? 0.6 : 1)
    }
}

// MARK: - Progress

/// Warm coral fill on a `surface-cream-strong` track.
struct ClaudeProgressBar: View {
    var value: Double
    var height: CGFloat = 8
    var fill: Color = ClaudePalette.primary
    var track: Color = ClaudePalette.surfaceCreamStrong

    var body: some View {
        GeometryReader { geo in
            let v = value.isFinite ? min(max(value, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: v > 0 ? max(height, geo.size.width * v) : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: value)
        .accessibilityValue("\(Int((value.isFinite ? value : 0) * 100))%")
    }
}

// MARK: - Misc

struct ClaudeDivider: View {
    var color: Color = ClaudePalette.hairline
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// KPI tile: muted label, monospaced value, optional caption.
struct ClaudeStatTile: View {
    let label: String
    let value: String
    var caption: String? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ClaudePalette.primary)
                }
                Text(label)
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.muted)
            }
            Text(value)
                .font(ClaudeTypography.statValue)
                .foregroundStyle(ClaudePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.mutedSoft)
                    .lineLimit(1)
            }
        }
        .claudeCard(.card, padding: 20)
    }
}
