import SwiftUI

/// Typography tokens from `DESIGN.md`.
///
/// - Display (headlines, page titles, quotes): macOS native serif at weight 400 — never bold —
///   paired with negative tracking (see `ClaudeTracking`).
/// - UI (headings, labels, body, buttons): macOS humanist sans at `.regular` / `.medium`.
/// - Numbers (live timers, stats): `.monospacedDigit()`.
enum ClaudeTypography {

    // MARK: Display — serif, weight 400

    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// display-xl (scaled for desktop app chrome)
    static let displayXL = serif(48)
    /// display-lg
    static let displayLG = serif(40)
    /// display-md
    static let displayMD = serif(32)
    /// display-sm
    static let displaySM = serif(26)
    /// Small serif for quotes inside cards.
    static let quote = serif(20)

    // MARK: UI — humanist sans

    static let titleLG = Font.system(size: 20, weight: .medium)
    static let titleMD = Font.system(size: 16, weight: .medium)
    static let titleSM = Font.system(size: 14, weight: .medium)
    static let bodyMD = Font.system(size: 14, weight: .regular)
    static let bodySM = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .medium)
    static let captionUppercase = Font.system(size: 11, weight: .medium)
    static let button = Font.system(size: 14, weight: .medium)
    static let navLink = Font.system(size: 13.5, weight: .medium)

    // MARK: Numbers — monospaced digits

    static func number(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Hero live timer: light sans with tabular figures.
    static let heroTimer = Font.system(size: 64, weight: .light).monospacedDigit()
    static let statValue = Font.system(size: 26, weight: .regular).monospacedDigit()
}

/// Negative letter-spacing paired with display sizes (DESIGN.md: -0.3 to -1.5).
enum ClaudeTracking {
    static let displayXL: CGFloat = -1.2
    static let displayLG: CGFloat = -1.0
    static let displayMD: CGFloat = -0.6
    static let displaySM: CGFloat = -0.3
    static let quote: CGFloat = -0.3
    static let captionUppercase: CGFloat = 1.5
}

extension View {
    /// Serif display text at weight 400 with the matching negative tracking.
    func claudeDisplay(_ size: CGFloat, tracking: CGFloat? = nil) -> some View {
        let resolved = tracking ?? {
            switch size {
            case 44...: return ClaudeTracking.displayXL
            case 36..<44: return ClaudeTracking.displayLG
            case 30..<36: return ClaudeTracking.displayMD
            default: return ClaudeTracking.displaySM
            }
        }()
        return self.font(ClaudeTypography.serif(size)).tracking(resolved)
    }

    /// Uppercase caption (category tags, issue headers).
    func claudeEyebrow(_ color: Color = ClaudePalette.muted) -> some View {
        self.font(ClaudeTypography.captionUppercase)
            .tracking(ClaudeTracking.captionUppercase)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
