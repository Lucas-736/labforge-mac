import Foundation

/// A single lab check-in session. `endTime == nil` means the session is still running.
public struct LabSession: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var goal: String
    public var notes: String
    public var isManualEntry: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        goal: String = "",
        notes: String = "",
        isManualEntry: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.goal = goal
        self.notes = notes
        self.isManualEntry = isManualEntry
        let created = createdAt ?? startTime
        self.createdAt = created
        self.updatedAt = updatedAt ?? created
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
