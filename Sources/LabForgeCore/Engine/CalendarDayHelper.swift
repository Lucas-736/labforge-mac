import Foundation

/// Calendar-day utilities. All functions are pure; inject `now` and `calendar` for testing.
///
/// Date keys use the `yyyy-MM-dd` format and are built from `Calendar.dateComponents`
/// (no shared `DateFormatter`), so they are thread-safe and locale-independent.
public enum CalendarDayHelper: Sendable {

    /// One slice of a session that falls within a single calendar day.
    public struct DaySegment: Sendable, Equatable, Hashable {
        public var dateKey: String
        public var dayStart: Date
        public var seconds: TimeInterval
    }

    // MARK: Keys

    public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parses `yyyy-MM-dd` into the start of that day in `calendar`. Returns nil for malformed or impossible dates.
    public static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        guard let date = calendar.date(from: comps) else { return nil }
        let start = calendar.startOfDay(for: date)
        // Reject overflowed values such as 2024-02-31.
        guard dateKey(for: start, calendar: calendar) == key else { return nil }
        return start
    }

    // MARK: Segmentation

    /// Splits a session into per-calendar-day slices. Active sessions run until `now`.
    /// A zero-length session yields a single zero-second segment on its start day.
    public static func daySegments(for session: LabSession, now: Date = Date(), calendar: Calendar = .current) -> [DaySegment] {
        let start = session.startTime
        let end = session.effectiveEnd(asOf: now)
        var dayStart = calendar.startOfDay(for: start)
        guard end > start else {
            return [DaySegment(dateKey: dateKey(for: start, calendar: calendar), dayStart: dayStart, seconds: 0)]
        }
        var result: [DaySegment] = []
        while dayStart < end {
            guard let next = calendar.dateInterval(of: .day, for: dayStart)?.end, next > dayStart else { break }
            let overlap = min(end, next).timeIntervalSince(max(start, dayStart))
            if overlap > 0 {
                result.append(DaySegment(dateKey: dateKey(for: dayStart, calendar: calendar), dayStart: dayStart, seconds: overlap))
            }
            dayStart = next
        }
        return result
    }

    /// Seconds per day key; sessions crossing midnight are split across each day they touch.
    public static func secondsByDay(for sessions: [LabSession], now: Date = Date(), calendar: Calendar = .current) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        for session in sessions {
            for seg in daySegments(for: session, now: now, calendar: calendar) {
                result[seg.dateKey, default: 0] += seg.seconds
            }
        }
        return result
    }

    /// Number of sessions touching each day (a midnight-spanning session counts on every day it touches).
    public static func sessionCountsByDay(for sessions: [LabSession], now: Date = Date(), calendar: Calendar = .current) -> [String: Int] {
        var result: [String: Int] = [:]
        for session in sessions {
            for key in Set(daySegments(for: session, now: now, calendar: calendar).map(\.dateKey)) {
                result[key, default: 0] += 1
            }
        }
        return result
    }

    public static func totalSeconds(on date: Date, sessions: [LabSession], now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        let key = dateKey(for: date, calendar: calendar)
        return sessions.reduce(0) { acc, s in
            acc + daySegments(for: s, now: now, calendar: calendar).filter { $0.dateKey == key }.reduce(0) { $0 + $1.seconds }
        }
    }

    public static func totalSeconds(sessions: [LabSession], now: Date = Date()) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration(asOf: now) }
    }

    /// Per-day summaries for every day that has a session or a non-empty goal, newest first.
    public static func dailySummaries(sessions: [LabSession], dailyGoals: [String: String], now: Date = Date(), calendar: Calendar = .current) -> [DailySummary] {
        var seconds: [String: TimeInterval] = [:]
        var daySessions: [String: [LabSession]] = [:]
        var dayStarts: [String: Date] = [:]
        for session in sessions {
            var seen = Set<String>()
            for seg in daySegments(for: session, now: now, calendar: calendar) {
                seconds[seg.dateKey, default: 0] += seg.seconds
                dayStarts[seg.dateKey] = seg.dayStart
                if seen.insert(seg.dateKey).inserted {
                    daySessions[seg.dateKey, default: []].append(session)
                }
            }
        }
        for (key, goal) in dailyGoals where !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if dayStarts[key] == nil, let d = date(fromKey: key, calendar: calendar) {
                dayStarts[key] = d
            }
        }
        return dayStarts.map { key, start in
            let list = (daySessions[key] ?? []).sorted { $0.startTime < $1.startTime }
            return DailySummary(dateKey: key, date: start, totalSeconds: seconds[key] ?? 0,
                                sessionCount: list.count, goal: dailyGoals[key] ?? "", sessions: list)
        }
        .sorted { $0.date > $1.date }
    }
}
