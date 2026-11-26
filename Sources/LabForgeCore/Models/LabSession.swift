import Foundation

/// A single lab check-in session. `endTime == nil` means the session is still running.
public struct LabSession: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var goal: String
    public var notes: String
    public var isManualEntry: Bool
    /// Kind of work. Missing / unknown values in older files decode as `.experiment`.
    public var category: SessionCategory
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        goal: String = "",
        notes: String = "",
        isManualEntry: Bool = false,
        category: SessionCategory = .experiment,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.goal = goal
        self.notes = notes
        self.isManualEntry = isManualEntry
        self.category = category
        let created = createdAt ?? startTime
        self.createdAt = created
        self.updatedAt = updatedAt ?? created
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, goal, notes, isManualEntry, category, createdAt, updatedAt
    }

    /// v1 fields keep their original strictness; `category` (added in v1.1) is optional and
    /// falls back to `.experiment` when missing or malformed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.startTime = try c.decode(Date.self, forKey: .startTime)
        self.endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        self.goal = try c.decode(String.self, forKey: .goal)
        self.notes = try c.decode(String.self, forKey: .notes)
        self.isManualEntry = try c.decode(Bool.self, forKey: .isManualEntry)
        self.category = (try? c.decodeIfPresent(SessionCategory.self, forKey: .category)) ?? .experiment
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// `true` while the session has no end time.
    public var isActive: Bool { endTime == nil }

    /// Elapsed seconds; active sessions are measured up to `now`. Never negative.
    public func duration(asOf now: Date = Date()) -> TimeInterval {
        max(0, (endTime ?? now).timeIntervalSince(startTime))
    }

    /// The effective end used for calculations (`endTime` or `now` when active).
    public func effectiveEnd(asOf now: Date = Date()) -> Date {
        endTime ?? max(now, startTime)
    }
}
