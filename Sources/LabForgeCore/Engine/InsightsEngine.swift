import Foundation

/// Calm, factual insights derived from sessions. All functions are pure; inject `now` and
/// `calendar` for testing.
///
/// Weeks follow `calendar` (its `firstWeekday` / `minimumDaysInFirstWeek`); pass an ISO 8601
/// calendar or one with `firstWeekday = 2` for Monday-first weeks.
public enum InsightsEngine: Sendable {

    /// Look-back window used by `calmObservations` for peak time / category / average.
    public static let observationWindowDays = 28

    // MARK: Types

    public struct WeeklyProgress: Sendable, Equatable, Hashable {
        /// Start of the week containing `now`.
        public var weekStart: Date
        /// Exclusive end of that week.
        public var weekEnd: Date
        /// Seconds attributed to days of this week (active sessions counted up to `now`).
        public var totalSeconds: TimeInterval
        public var targetSeconds: TimeInterval
        /// `totalSeconds / targetSeconds`, clamped to `0...1` (0 when the target is not positive).
        public var progress: Double
        /// Days of this week with more than zero seconds.
        public var activeDays: Int
        /// Sessions contributing time to this week (a session spanning two weeks counts in both).
        public var sessionCount: Int
        /// Full total of the previous calendar week.
        public var previousWeekSeconds: TimeInterval

        public init(weekStart: Date, weekEnd: Date, totalSeconds: TimeInterval, targetSeconds: TimeInterval,
                    progress: Double, activeDays: Int, sessionCount: Int, previousWeekSeconds: TimeInterval) {
            self.weekStart = weekStart
            self.weekEnd = weekEnd
            self.totalSeconds = totalSeconds
            self.targetSeconds = targetSeconds
            self.progress = progress
            self.activeDays = activeDays
            self.sessionCount = sessionCount
            self.previousWeekSeconds = previousWeekSeconds
        }

        /// Seconds still needed to reach the target (never negative).
        public var remainingSeconds: TimeInterval { max(0, targetSeconds - totalSeconds) }
    }

    public struct CategoryBreakdown: Sendable, Equatable, Hashable, Identifiable {
        public var id: SessionCategory { category }
        public var category: SessionCategory
        public var totalSeconds: TimeInterval
        /// Share of all counted seconds, `0...1`.
        public var percentage: Double
        public var sessionCount: Int

        public init(category: SessionCategory, totalSeconds: TimeInterval, percentage: Double, sessionCount: Int) {
            self.category = category
            self.totalSeconds = totalSeconds
            self.percentage = percentage
            self.sessionCount = sessionCount
        }
    }

    public struct CalmObservation: Sendable, Equatable, Hashable, Identifiable {
        /// Stable kind identifier: `starter`, `dormant`, `peak-window`, `weekly-pace`, `top-category`, `daily-average`.
        public var id: String
        public var title: String
        public var detail: String
        /// SF Symbol name.
        public var symbolName: String

        public init(id: String, title: String, detail: String, symbolName: String) {
            self.id = id
            self.title = title
            self.detail = detail
            self.symbolName = symbolName
        }
    }

    // MARK: Weekly progress

    public static func weeklyProgress(sessions: [LabSession], weeklyTargetSeconds: TimeInterval,
                                      now: Date = Date(), calendar: Calendar = .current) -> WeeklyProgress {
        let week = weekInterval(containing: now, calendar: calendar)
        let previous = weekInterval(containing: week.start.addingTimeInterval(-1), calendar: calendar)
        let byDay = CalendarDayHelper.secondsByDay(for: sessions, now: now, calendar: calendar)

        let keys = dayKeys(in: week, calendar: calendar)
        let keySet = Set(keys)
        let total = keys.reduce(0.0) { $0 + (byDay[$1] ?? 0) }
        let activeDays = keys.filter { (byDay[$0] ?? 0) > 0 }.count
        let previousTotal = dayKeys(in: previous, calendar: calendar).reduce(0.0) { $0 + (byDay[$1] ?? 0) }
        let sessionCount = sessions.filter { s in
            CalendarDayHelper.daySegments(for: s, now: now, calendar: calendar)
                .contains { $0.seconds > 0 && keySet.contains($0.dateKey) }
        }.count

        let target = weeklyTargetSeconds.isFinite ? max(0, weeklyTargetSeconds) : 0
        let progress = target > 0 ? min(1, max(0, total / target)) : 0
        return WeeklyProgress(weekStart: week.start, weekEnd: week.end, totalSeconds: total, targetSeconds: target,
                              progress: progress, activeDays: activeDays, sessionCount: sessionCount,
                              previousWeekSeconds: previousTotal)
    }

    // MARK: Categories

    /// Non-zero categories sorted by seconds (descending; ties follow `SessionCategory.allCases`).
    /// `withinLastDays: n` keeps only time on the last `n` calendar days including today
    /// (`n <= 0` yields `[]`); `nil` means all time. Midnight-spanning sessions are split per day.
    public static func categoryBreakdown(sessions: [LabSession], withinLastDays: Int? = nil,
                                         now: Date = Date(), calendar: Calendar = .current) -> [CategoryBreakdown] {
        var windowStart: Date?
        if let days = withinLastDays {
            guard days > 0 else { return [] }
            windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
        }
        var seconds: [SessionCategory: TimeInterval] = [:]
        var counts: [SessionCategory: Int] = [:]
        for session in sessions {
            let s = CalendarDayHelper.daySegments(for: session, now: now, calendar: calendar)
                .filter { seg in windowStart.map { seg.dayStart >= $0 && seg.dayStart <= now } ?? true }
                .reduce(0.0) { $0 + $1.seconds }
            guard s > 0 else { continue }
            seconds[session.category, default: 0] += s
            counts[session.category, default: 0] += 1
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }
        let order = Dictionary(uniqueKeysWithValues: SessionCategory.allCases.enumerated().map { ($1, $0) })
        return seconds
            .map { CategoryBreakdown(category: $0.key, totalSeconds: $0.value, percentage: $0.value / total, sessionCount: counts[$0.key] ?? 0) }
            .sorted { $0.totalSeconds != $1.totalSeconds ? $0.totalSeconds > $1.totalSeconds : order[$0.category]! < order[$1.category]! }
    }

    // MARK: Goals

    /// Up to `limit` unique, trimmed, non-empty goals, most recent first.
    ///
    /// Session goals are dated by `startTime` (ties broken by `updatedAt`); daily goals by the
    /// start of their `yyyy-MM-dd` day (malformed keys are skipped). The first occurrence wins.
    public static func recentGoals(sessions: [LabSession], dailyGoals: [String: String], limit: Int = 5,
                                   calendar: Calendar = .current) -> [String] {
        guard limit > 0 else { return [] }
        struct Entry { var text: String; var primary: Date; var secondary: Date }
        var entries: [Entry] = []
        for s in sessions {
            let text = s.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { entries.append(Entry(text: text, primary: s.startTime, secondary: s.updatedAt)) }
        }
        for (key, goal) in dailyGoals {
            let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let day = CalendarDayHelper.date(fromKey: key, calendar: calendar) else { continue }
            entries.append(Entry(text: text, primary: day, secondary: day))
        }
        entries.sort {
            if $0.primary != $1.primary { return $0.primary > $1.primary }
            if $0.secondary != $1.secondary { return $0.secondary > $1.secondary }
            return $0.text < $1.text
        }
        var seen = Set<String>()
        var result: [String] = []
        for e in entries where seen.insert(e.text).inserted {
            result.append(e.text)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: Observations

    /// 1–3 factual observations (never more than 3, never empty).
    ///
    /// Priority: peak time block (last 28 days) → this week vs the same point last week →
    /// dominant category (only when ≥ 2 categories) → average per active day.
    /// With no recorded time at all a single starter note is returned; with nothing in the last
    /// 28 days a single "dormant" note is returned.
    public static func calmObservations(sessions: [LabSession], dailyTargetSeconds: TimeInterval,
                                        weeklyTargetSeconds: TimeInterval, now: Date = Date(),
                                        calendar: Calendar = .current) -> [CalmObservation] {
        let recorded = sessions.filter { $0.duration(asOf: now) > 0 }
        guard !recorded.isEmpty else {
            return [CalmObservation(id: "starter", title: "从第一次记录开始",
                                    detail: "开始一次计时，研铸会在这里安静地记下你的科研节奏。",
                                    symbolName: "leaf")]
        }

        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(observationWindowDays - 1), to: today) ?? today
        let hourly = secondsByHourOfDay(sessions: recorded, from: windowStart, to: now, now: now, calendar: calendar)
        let windowTotal = hourly.values.reduce(0, +)
        guard windowTotal > 0 else {
            let last = recorded.map(\.startTime).max() ?? now
            let total = CalendarDayHelper.totalSeconds(sessions: recorded, now: now)
            return [CalmObservation(id: "dormant", title: "近 4 周暂无记录",
                                    detail: "上次记录在 \(CalendarDayHelper.dateKey(for: last, calendar: calendar))，累计已投入 \(DurationFormatter.humanReadable(total))。",
                                    symbolName: "leaf")]
        }

        var candidates: [CalmObservation?] = []

        // Peak time block.
        let blockSeconds = TimeBlock.all.map { block in (block, block.hours.reduce(0.0) { $0 + (hourly[$1] ?? 0) }) }
        if let (block, secs) = blockSeconds.max(by: { $0.1 < $1.1 }), secs > 0 {
            candidates.append(CalmObservation(
                id: "peak-window", title: "专注高峰：\(block.label)",
                detail: "近 4 周约 \(percent(secs / windowTotal)) 的科研时长落在这个时段。",
                symbolName: block.symbolName))
        }

        // Weekly pace vs the same point last week.
        let week = weeklyProgress(sessions: recorded, weeklyTargetSeconds: weeklyTargetSeconds, now: now, calendar: calendar)
        let lastWeekStart = weekInterval(containing: week.weekStart.addingTimeInterval(-1), calendar: calendar).start
        let lastWeekSamePoint = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        let samePeriod = secondsInRange(sessions: recorded, from: lastWeekStart, to: lastWeekSamePoint, now: now)
        candidates.append(weeklyObservation(week: week, samePeriodLastWeek: samePeriod))

        // Dominant category, or average per active day.
        let breakdown = categoryBreakdown(sessions: recorded, withinLastDays: observationWindowDays, now: now, calendar: calendar)
        if breakdown.count >= 2 {
            let top = breakdown[0], second = breakdown[1]
            candidates.append(CalmObservation(
                id: "top-category", title: "近 4 周以「\(top.category.title)」为主",
                detail: "占全部时长的 \(percent(top.percentage))，其次是「\(second.category.title)」（\(percent(second.percentage))）。",
                symbolName: top.category.symbolName))
        }
        let byDay = CalendarDayHelper.secondsByDay(for: recorded, now: now, calendar: calendar)
        let activeKeys = dayKeys(in: DateInterval(start: windowStart, end: max(windowStart, now)), calendar: calendar)
            .filter { (byDay[$0] ?? 0) > 0 }
        if !activeKeys.isEmpty {
            let avg = activeKeys.reduce(0.0) { $0 + (byDay[$1] ?? 0) } / Double(activeKeys.count)
            let target = dailyTargetSeconds.isFinite && dailyTargetSeconds > 0
                ? "，日目标为 \(DurationFormatter.humanReadable(dailyTargetSeconds))" : ""
            candidates.append(CalmObservation(
                id: "daily-average", title: "记录日平均 \(DurationFormatter.humanReadable(avg))",
                detail: "近 4 周有 \(activeKeys.count) 天留下记录\(target)。",
                symbolName: "clock"))
        }

        return Array(candidates.compactMap { $0 }.prefix(3))
    }

    // MARK: Helpers

    struct TimeBlock: Sendable {
        var name: String
        var startHour: Int
        var endHour: Int
        var symbolName: String

        var hours: [Int] {
            startHour < endHour ? Array(startHour..<endHour) : Array(startHour..<24) + Array(0..<endHour)
        }

        var label: String { "\(name) " + String(format: "%02d:00–%02d:00", startHour, endHour) }

        static let all: [TimeBlock] = [
            TimeBlock(name: "清晨", startHour: 6, endHour: 9, symbolName: "sunrise"),
            TimeBlock(name: "上午", startHour: 9, endHour: 12, symbolName: "sun.max"),
            TimeBlock(name: "午后", startHour: 12, endHour: 14, symbolName: "cup.and.saucer"),
            TimeBlock(name: "下午", startHour: 14, endHour: 18, symbolName: "sun.haze"),
            TimeBlock(name: "晚间", startHour: 18, endHour: 22, symbolName: "sunset"),
            TimeBlock(name: "深夜", startHour: 22, endHour: 6, symbolName: "moon.stars"),
        ]
    }

    static func weeklyObservation(week: WeeklyProgress, samePeriodLastWeek: TimeInterval) -> CalmObservation? {
        let goal = week.targetSeconds > 0 ? "已完成周目标的 \(percent(week.progress))。" : ""
        if week.totalSeconds <= 0 {
            guard week.previousWeekSeconds > 0 else { return nil }
            return CalmObservation(id: "weekly-pace", title: "本周尚未开始记录",
                                   detail: "上周共投入 \(DurationFormatter.humanReadable(week.previousWeekSeconds))。",
                                   symbolName: "calendar")
        }
        var detail: String
        if samePeriodLastWeek > 0 {
            let diff = week.totalSeconds - samePeriodLastWeek
            let comparison: String
            if abs(diff) < 60 {
                comparison = "与上周同期基本持平"
            } else if diff > 0 {
                comparison = "比上周同期多 \(DurationFormatter.humanReadable(diff))"
            } else {
                comparison = "比上周同期少 \(DurationFormatter.humanReadable(-diff))"
            }
            detail = "上周同期为 \(DurationFormatter.humanReadable(samePeriodLastWeek))，\(comparison)。"
        } else {
            detail = "上周同期暂无记录。"
        }
        detail += goal
        return CalmObservation(id: "weekly-pace", title: "本周已投入 \(DurationFormatter.humanReadable(week.totalSeconds))",
                               detail: detail, symbolName: "calendar")
    }

    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    /// Day keys for every calendar day starting within `interval`.
    static func dayKeys(in interval: DateInterval, calendar: Calendar) -> [String] {
        var keys: [String] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            keys.append(CalendarDayHelper.dateKey(for: day, calendar: calendar))
            guard let next = calendar.dateInterval(of: .day, for: day)?.end, next > day else { break }
            day = next
        }
        return keys
    }

    /// Session seconds overlapping `[from, to)`.
    static func secondsInRange(sessions: [LabSession], from: Date, to: Date, now: Date) -> TimeInterval {
        guard to > from else { return 0 }
        return sessions.reduce(0.0) { acc, s in
            acc + max(0, min(s.effectiveEnd(asOf: now), to).timeIntervalSince(max(s.startTime, from)))
        }
    }

    /// Seconds per hour of day (0...23) for session time overlapping `[from, to)`.
    static func secondsByHourOfDay(sessions: [LabSession], from: Date, to: Date, now: Date,
                                   calendar: Calendar) -> [Int: TimeInterval] {
        var result: [Int: TimeInterval] = [:]
        for s in sessions {
            let end = min(s.effectiveEnd(asOf: now), to)
            var cursor = max(s.startTime, from)
            while cursor < end {
                guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
                let next = min(hour.end, end)
                guard next > cursor else { break }
                result[calendar.component(.hour, from: cursor), default: 0] += next.timeIntervalSince(cursor)
                cursor = next
            }
        }
        return result
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }
}
