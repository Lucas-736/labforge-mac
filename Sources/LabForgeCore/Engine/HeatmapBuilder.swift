import Foundation

public enum HeatmapBuilder: Sendable {

    /// 0 = none, 1 = (0, 2h), 2 = [2h, 4h), 3 = [4h, 7h), 4 = >= 7h.
    public static func intensityLevel(forSeconds seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        switch seconds {
        case ..<(2 * 3600): return 1
        case ..<(4 * 3600): return 2
        case ..<(7 * 3600): return 3
        default: return 4
        }
    }

    /// 365 consecutive days (oldest first), the last one being `startOfDay(for: now)`.
    public static func build365Days(sessions: [LabSession], dailyGoals: [String: String], now: Date = Date(), calendar: Calendar = .current) -> [HeatmapDay] {
        let seconds = CalendarDayHelper.secondsByDay(for: sessions, now: now, calendar: calendar)
        let counts = CalendarDayHelper.sessionCountsByDay(for: sessions, now: now, calendar: calendar)
        var sessionGoals: [String: [String]] = [:]
        for s in sessions.sorted(by: { $0.startTime < $1.startTime }) {
            let g = s.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !g.isEmpty else { continue }
            let key = CalendarDayHelper.dateKey(for: s.startTime, calendar: calendar)
            if !(sessionGoals[key]?.contains(g) ?? false) { sessionGoals[key, default: []].append(g) }
        }

        let today = calendar.startOfDay(for: now)
        return (0..<365).reversed().compactMap { offset -> HeatmapDay? in
            guard let raw = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let day = calendar.startOfDay(for: raw)
            let key = CalendarDayHelper.dateKey(for: day, calendar: calendar)
            let total = seconds[key] ?? 0
            let dailyGoal = (dailyGoals[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = dailyGoal.isEmpty ? (sessionGoals[key] ?? []).joined(separator: " · ") : dailyGoal
            return HeatmapDay(id: key, date: day, totalSeconds: total, sessionCount: counts[key] ?? 0,
                              goalSummary: summary, intensityLevel: intensityLevel(forSeconds: total))
        }
    }

    /// Arranges days into week columns (oldest column first). Each column has exactly 7 rows.
    ///
    /// Row order follows `calendar.firstWeekday`: with `firstWeekday == 1` rows are
    /// Sunday…Saturday; with `firstWeekday == 2` rows are Monday…Sunday. Slots before the first
    /// day and after the last day (or for missing dates) are `nil`.
    public static func buildWeeksGrid(days: [HeatmapDay], calendar: Calendar = .current) -> [[HeatmapDay?]] {
        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        let firstColumnStart = calendar.date(byAdding: .day, value: -rowIndex(for: first.date, calendar: calendar),
                                             to: calendar.startOfDay(for: first.date)) ?? first.date
        var grid: [[HeatmapDay?]] = []
        for day in sorted {
            let offset = calendar.dateComponents([.day], from: firstColumnStart, to: calendar.startOfDay(for: day.date)).day ?? 0
            let column = offset / 7
            let row = rowIndex(for: day.date, calendar: calendar)
            while grid.count <= column { grid.append(Array(repeating: nil, count: 7)) }
            grid[column][row] = day
        }
        return grid
    }

    /// 0-based row of `date` given `calendar.firstWeekday`.
    public static func rowIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}
