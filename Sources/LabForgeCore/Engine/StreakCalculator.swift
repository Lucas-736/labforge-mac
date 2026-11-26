import Foundation

/// Computes consecutive check-in days. A day counts as checked in when any session
/// (including the active one) overlaps it.
public enum StreakCalculator: Sendable {

    public static func compute(sessions: [LabSession], now: Date = Date(), calendar: Calendar = .current) -> StreakSummary {
        let todayStart = calendar.startOfDay(for: now)
        let todayKey = CalendarDayHelper.dateKey(for: todayStart, calendar: calendar)
        // Ignore days in the future (e.g. bad clock data). yyyy-MM-dd keys compare lexicographically.
        let activeKeys = Set(CalendarDayHelper.sessionCountsByDay(for: sessions, now: now, calendar: calendar).keys)
            .filter { $0 <= todayKey }
        guard !activeKeys.isEmpty else { return .empty }

        let isToday = activeKeys.contains(todayKey)
        var current = 0
        var cursor: Date? = isToday ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)
        while let day = cursor, activeKeys.contains(CalendarDayHelper.dateKey(for: day, calendar: calendar)) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }

        return StreakSummary(currentStreak: current,
                             longestStreak: longestRun(keys: activeKeys, calendar: calendar),
                             isCheckedInToday: isToday,
                             totalActiveDays: activeKeys.count)
    }

    /// Longest run of consecutive day keys.
    static func longestRun(keys: Set<String>, calendar: Calendar) -> Int {
        runs(keys: keys, calendar: calendar).map(\.length).max() ?? 0
    }

    /// Consecutive runs, chronological; `endDate` is the start of the last day of each run.
    static func runs(keys: Set<String>, calendar: Calendar) -> [(length: Int, startDate: Date, endDate: Date)] {
        let dates = keys.compactMap { CalendarDayHelper.date(fromKey: $0, calendar: calendar) }.sorted()
        var result: [(length: Int, startDate: Date, endDate: Date)] = []
        for date in dates {
            if let last = result.last,
               let expected = calendar.date(byAdding: .day, value: 1, to: last.endDate),
               calendar.isDate(expected, inSameDayAs: date) {
                result[result.count - 1] = (last.length + 1, last.startDate, date)
            } else {
                result.append((1, date, date))
            }
        }
        return result
    }
}
