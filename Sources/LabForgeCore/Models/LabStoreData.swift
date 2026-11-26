import Foundation

/// Root document persisted to `records.json`.
public struct LabStoreData: Codable, Sendable, Equatable, Hashable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var sessions: [LabSession]
    /// Daily goals keyed by `yyyy-MM-dd` (see `CalendarDayHelper.dateKey`).
    public var dailyGoals: [String: String]
    public var settings: LabSettings

    public init(
        schemaVersion: Int = LabStoreData.currentSchemaVersion,
        sessions: [LabSession] = [],
        dailyGoals: [String: String] = [:],
        settings: LabSettings = LabSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
        self.dailyGoals = dailyGoals
        self.settings = settings
    }

    /// The currently running session (newest by `startTime` if, unexpectedly, several exist).
    public var activeSession: LabSession? {
        sessions.filter(\.isActive).max { $0.startTime < $1.startTime }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sessions, dailyGoals, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? LabStoreData.currentSchemaVersion
        self.sessions = try c.decodeIfPresent([LabSession].self, forKey: .sessions) ?? []
        self.dailyGoals = try c.decodeIfPresent([String: String].self, forKey: .dailyGoals) ?? [:]
        self.settings = (try? c.decodeIfPresent(LabSettings.self, forKey: .settings)) ?? LabSettings()
    }
}
