import Foundation

/// UI appearance preference.
public enum AppearanceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .light: return "Claude 暖浅色"
        case .dark: return "暖炭黑"
        case .system: return "跟随系统"
        }
    }

    public static let `default`: AppearanceMode = .light
}

/// User preferences. Decoding is resilient: missing or invalid keys fall back to defaults.
public struct LabSettings: Codable, Sendable, Equatable, Hashable {
    public static let dailyTargetRange: ClosedRange<Double> = 1.0...16.0

    public var appearanceMode: AppearanceMode
    /// Daily target in hours, always clamped to `1.0...16.0`.
    public var dailyTargetHours: Double {
        didSet { dailyTargetHours = Self.clampTarget(dailyTargetHours) }
    }
    public var reminderEnabled: Bool
    /// 0...23
    public var reminderHour: Int {
        didSet { reminderHour = Self.clamp(reminderHour, 0...23) }
    }
    /// 0...59
    public var reminderMinute: Int {
        didSet { reminderMinute = Self.clamp(reminderMinute, 0...59) }
    }
    public var launchAtLogin: Bool

    public init(
        appearanceMode: AppearanceMode = .light,
        dailyTargetHours: Double = 8.0,
        reminderEnabled: Bool = false,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        launchAtLogin: Bool = false
    ) {
        self.appearanceMode = appearanceMode
        self.dailyTargetHours = Self.clampTarget(dailyTargetHours)
        self.reminderEnabled = reminderEnabled
        self.reminderHour = Self.clamp(reminderHour, 0...23)
        self.reminderMinute = Self.clamp(reminderMinute, 0...59)
        self.launchAtLogin = launchAtLogin
    }

    /// Daily target expressed in seconds.
    public var dailyTargetSeconds: TimeInterval { dailyTargetHours * 3600 }

    private enum CodingKeys: String, CodingKey {
        case appearanceMode, dailyTargetHours, reminderEnabled, reminderHour, reminderMinute, launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LabSettings()
        self.init(
            appearanceMode: (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)) ?? defaults.appearanceMode,
            dailyTargetHours: (try? c.decodeIfPresent(Double.self, forKey: .dailyTargetHours)) ?? defaults.dailyTargetHours,
            reminderEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .reminderEnabled)) ?? defaults.reminderEnabled,
            reminderHour: (try? c.decodeIfPresent(Int.self, forKey: .reminderHour)) ?? defaults.reminderHour,
            reminderMinute: (try? c.decodeIfPresent(Int.self, forKey: .reminderMinute)) ?? defaults.reminderMinute,
            launchAtLogin: (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appearanceMode, forKey: .appearanceMode)
        try c.encode(dailyTargetHours, forKey: .dailyTargetHours)
        try c.encode(reminderEnabled, forKey: .reminderEnabled)
        try c.encode(reminderHour, forKey: .reminderHour)
        try c.encode(reminderMinute, forKey: .reminderMinute)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
    }

    static func clampTarget(_ value: Double) -> Double {
        guard value.isFinite else { return 8.0 }
        return min(max(value, dailyTargetRange.lowerBound), dailyTargetRange.upperBound)
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
