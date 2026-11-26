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

/// How the menu bar item renders while a session is running.
/// Unknown raw values decode as `.full`.
public enum MenuBarDisplayStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case full
    case compact
    case iconOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .full: return "完整：火焰与时长"
        case .compact: return "极简：仅时长"
        case .iconOnly: return "纯图标：省空间"
        }
    }

    public static let `default`: MenuBarDisplayStyle = .full

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MenuBarDisplayStyle(rawValue: raw) ?? .default
    }
}

/// User preferences. Decoding is resilient: missing or invalid keys fall back to defaults,
/// so v1 files (without the v1.1 profile / preference keys) load cleanly.
public struct LabSettings: Codable, Sendable, Equatable, Hashable {
    public static let dailyTargetRange: ClosedRange<Double> = 1.0...16.0
    public static let weeklyTargetRange: ClosedRange<Double> = 5.0...112.0
    public static let sleepPromptThresholdRange: ClosedRange<Int> = 0...240
    public static let availableSoundNames: [String] = ["Glass", "Hero", "Pop", "Tink", "Submarine", "Purr"]
    public static let defaultSoundName = "Glass"
    public static let defaultResearcherName = "研究者"

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

    // MARK: v1.1 profile

    public var researcherName: String
    public var labName: String
    public var researchFocus: String

    // MARK: v1.1 preferences

    /// Weekly target in hours, always clamped to `5.0...112.0`.
    public var weeklyTargetHours: Double {
        didSet { weeklyTargetHours = Self.clampWeeklyTarget(weeklyTargetHours) }
    }
    public var menuBarStyle: MenuBarDisplayStyle
    public var soundEnabled: Bool
    /// A macOS system sound name; see `availableSoundNames` and `effectiveSoundName`.
    public var soundName: String
    public var globalShortcutEnabled: Bool
    /// Idle/sleep minutes before asking whether to keep the time; `0` disables. Clamped to `0...240`.
    public var sleepPromptThresholdMinutes: Int {
        didSet { sleepPromptThresholdMinutes = Self.clamp(sleepPromptThresholdMinutes, Self.sleepPromptThresholdRange) }
    }

    public init(
        appearanceMode: AppearanceMode = .light,
        dailyTargetHours: Double = 8.0,
        reminderEnabled: Bool = false,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        launchAtLogin: Bool = false,
        researcherName: String = "",
        labName: String = "",
        researchFocus: String = "",
        weeklyTargetHours: Double = 40.0,
        menuBarStyle: MenuBarDisplayStyle = .full,
        soundEnabled: Bool = true,
        soundName: String = LabSettings.defaultSoundName,
        globalShortcutEnabled: Bool = true,
        sleepPromptThresholdMinutes: Int = 30
    ) {
        self.appearanceMode = appearanceMode
        self.dailyTargetHours = Self.clampTarget(dailyTargetHours)
        self.reminderEnabled = reminderEnabled
        self.reminderHour = Self.clamp(reminderHour, 0...23)
        self.reminderMinute = Self.clamp(reminderMinute, 0...59)
        self.launchAtLogin = launchAtLogin
        self.researcherName = researcherName
        self.labName = labName
        self.researchFocus = researchFocus
        self.weeklyTargetHours = Self.clampWeeklyTarget(weeklyTargetHours)
        self.menuBarStyle = menuBarStyle
        self.soundEnabled = soundEnabled
        self.soundName = soundName
        self.globalShortcutEnabled = globalShortcutEnabled
        self.sleepPromptThresholdMinutes = Self.clamp(sleepPromptThresholdMinutes, Self.sleepPromptThresholdRange)
    }

    /// Daily target expressed in seconds.
    public var dailyTargetSeconds: TimeInterval { dailyTargetHours * 3600 }

    /// Weekly target expressed in seconds.
    public var weeklyTargetSeconds: TimeInterval { weeklyTargetHours * 3600 }

    /// Trimmed `researcherName`, or `"研究者"` when blank.
    public var effectiveResearcherName: String {
        trimmedResearcherName.isEmpty ? Self.defaultResearcherName : trimmedResearcherName
    }

    private var trimmedResearcherName: String { researcherName.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var trimmedLabName: String { labName.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var trimmedResearchFocus: String { researchFocus.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `soundName` if it is one of `availableSoundNames`, otherwise `"Glass"`.
    public var effectiveSoundName: String {
        Self.availableSoundNames.contains(soundName) ? soundName : Self.defaultSoundName
    }

    /// `true` when the sleep/idle prompt is enabled (threshold > 0).
    public var sleepPromptEnabled: Bool { sleepPromptThresholdMinutes > 0 }

    private enum CodingKeys: String, CodingKey {
        case appearanceMode, dailyTargetHours, reminderEnabled, reminderHour, reminderMinute, launchAtLogin
        case researcherName, labName, researchFocus, weeklyTargetHours, menuBarStyle
        case soundEnabled, soundName, globalShortcutEnabled, sleepPromptThresholdMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LabSettings()
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(type, forKey: key)) ?? fallback
        }
        self.init(
            appearanceMode: value(AppearanceMode.self, .appearanceMode, defaults.appearanceMode),
            dailyTargetHours: value(Double.self, .dailyTargetHours, defaults.dailyTargetHours),
            reminderEnabled: value(Bool.self, .reminderEnabled, defaults.reminderEnabled),
            reminderHour: value(Int.self, .reminderHour, defaults.reminderHour),
            reminderMinute: value(Int.self, .reminderMinute, defaults.reminderMinute),
            launchAtLogin: value(Bool.self, .launchAtLogin, defaults.launchAtLogin),
            researcherName: value(String.self, .researcherName, defaults.researcherName),
            labName: value(String.self, .labName, defaults.labName),
            researchFocus: value(String.self, .researchFocus, defaults.researchFocus),
            weeklyTargetHours: value(Double.self, .weeklyTargetHours, defaults.weeklyTargetHours),
            menuBarStyle: value(MenuBarDisplayStyle.self, .menuBarStyle, defaults.menuBarStyle),
            soundEnabled: value(Bool.self, .soundEnabled, defaults.soundEnabled),
            soundName: value(String.self, .soundName, defaults.soundName),
            globalShortcutEnabled: value(Bool.self, .globalShortcutEnabled, defaults.globalShortcutEnabled),
            sleepPromptThresholdMinutes: value(Int.self, .sleepPromptThresholdMinutes, defaults.sleepPromptThresholdMinutes)
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
        try c.encode(trimmedResearcherName, forKey: .researcherName)
        try c.encode(trimmedLabName, forKey: .labName)
        try c.encode(trimmedResearchFocus, forKey: .researchFocus)
        try c.encode(weeklyTargetHours, forKey: .weeklyTargetHours)
        try c.encode(menuBarStyle, forKey: .menuBarStyle)
        try c.encode(soundEnabled, forKey: .soundEnabled)
        try c.encode(soundName, forKey: .soundName)
        try c.encode(globalShortcutEnabled, forKey: .globalShortcutEnabled)
        try c.encode(sleepPromptThresholdMinutes, forKey: .sleepPromptThresholdMinutes)
    }

    static func clampTarget(_ value: Double) -> Double {
        guard value.isFinite else { return 8.0 }
        return min(max(value, dailyTargetRange.lowerBound), dailyTargetRange.upperBound)
    }

    static func clampWeeklyTarget(_ value: Double) -> Double {
        guard value.isFinite else { return 40.0 }
        return min(max(value, weeklyTargetRange.lowerBound), weeklyTargetRange.upperBound)
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
