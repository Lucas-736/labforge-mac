import Foundation

/// Locale-independent duration strings. Negative / non-finite input is treated as 0.
public enum DurationFormatter: Sendable {

    static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(exactly: seconds.rounded(.down)) ?? Int.max
    }

    /// `HH:MM`, e.g. `02:18`. Hours may exceed two digits.
    public static func menuBarDuration(_ seconds: TimeInterval) -> String {
        let s = wholeSeconds(seconds)
        return String(format: "%02lld:%02lld", s / 3600, (s % 3600) / 60)
    }

    /// `HH:MM:SS`, e.g. `02:18:05`.
    public static func liveTimer(_ seconds: TimeInterval) -> String {
        let s = wholeSeconds(seconds)
        return String(format: "%02lld:%02lld:%02lld", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// e.g. `2 小时 18 分`, `3 小时`, `45 分钟`, `不足 1 分钟`.
    public static func humanReadable(_ seconds: TimeInterval) -> String {
        let s = wholeSeconds(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h == 0 && m == 0 { return "不足 1 分钟" }
        if h == 0 { return "\(m) 分钟" }
        if m == 0 { return "\(h) 小时" }
        return "\(h) 小时 \(m) 分"
    }

    /// One-decimal hours, e.g. `2.3h`, `0.0h`.
    public static func shortHours(_ seconds: TimeInterval) -> String {
        let s = (seconds.isFinite && seconds > 0) ? seconds : 0
        return String(format: "%.1fh", s / 3600)
    }
}
