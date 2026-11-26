import Foundation

public enum BadgeID: String, Codable, Sendable, CaseIterable, Identifiable {
    case firstSpark
    case earlyBird
    case streak7
    case streak30
    case midnightGrinder
    case eightHourDay
    case centurion100
    case legend500
    case logKeeper10

    public var id: String { rawValue }
}

public struct AchievementBadge: Sendable, Equatable, Hashable, Identifiable {
    public var id: BadgeID
    public var title: String
    public var subtitle: String
    public var requirement: String
    public var symbolName: String
    public var isUnlocked: Bool
    /// 0...1
    public var progress: Double
    public var progressText: String
    /// Best-effort date at which the badge criterion was first met (nil if locked or unknown).
    public var unlockedDate: Date?

    public init(id: BadgeID, title: String, subtitle: String, requirement: String, symbolName: String,
                isUnlocked: Bool, progress: Double, progressText: String, unlockedDate: Date? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.requirement = requirement
        self.symbolName = symbolName
        self.isUnlocked = isUnlocked
        self.progress = min(max(progress, 0), 1)
        self.progressText = progressText
        self.unlockedDate = unlockedDate
    }
}
