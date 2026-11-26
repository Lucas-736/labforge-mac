import Foundation

public struct HeatmapDay: Sendable, Equatable, Hashable, Identifiable {
    /// `yyyy-MM-dd`
    public var id: String
    /// Start of the calendar day.
    public var date: Date
    public var totalSeconds: TimeInterval
    public var sessionCount: Int
    public var goalSummary: String
    /// 0...4, see `HeatmapBuilder.intensityLevel(forSeconds:)`.
    public var intensityLevel: Int

    public init(id: String, date: Date, totalSeconds: TimeInterval, sessionCount: Int, goalSummary: String, intensityLevel: Int) {
        self.id = id
        self.date = date
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.goalSummary = goalSummary
        self.intensityLevel = intensityLevel
    }
}

public struct ResearchQuote: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var author: String
    public var tag: String

    public init(id: String, text: String, author: String, tag: String) {
        self.id = id
        self.text = text
        self.author = author
        self.tag = tag
    }
}

public struct StreakSummary: Sendable, Equatable, Hashable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var isCheckedInToday: Bool
    public var totalActiveDays: Int

    public init(currentStreak: Int, longestStreak: Int, isCheckedInToday: Bool, totalActiveDays: Int) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.isCheckedInToday = isCheckedInToday
        self.totalActiveDays = totalActiveDays
    }

    public static let empty = StreakSummary(currentStreak: 0, longestStreak: 0, isCheckedInToday: false, totalActiveDays: 0)
}

public struct DailySummary: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { dateKey }
    public var dateKey: String
    /// Start of the calendar day.
    public var date: Date
    /// Seconds attributed to this day (midnight-spanning sessions are split).
    public var totalSeconds: TimeInterval
    public var sessionCount: Int
    public var goal: String
    /// Sessions overlapping this day, sorted by start time ascending.
    public var sessions: [LabSession]

    public init(dateKey: String, date: Date, totalSeconds: TimeInterval, sessionCount: Int, goal: String, sessions: [LabSession]) {
        self.dateKey = dateKey
        self.date = date
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.goal = goal
        self.sessions = sessions
    }
}
