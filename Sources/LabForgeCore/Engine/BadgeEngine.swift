import Foundation

public enum BadgeEngine: Sendable {

    /// Evaluates all badges in `BadgeID.allCases` order.
    public static func evaluate(sessions: [LabSession], dailyGoals: [String: String], now: Date = Date(), calendar: Calendar = .current) -> [AchievementBadge] {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }
        let streak = StreakCalculator.compute(sessions: sessions, now: now, calendar: calendar)
        let todayKey = CalendarDayHelper.dateKey(for: now, calendar: calendar)
        let dayKeys = Set(CalendarDayHelper.sessionCountsByDay(for: sessions, now: now, calendar: calendar).keys).filter { $0 <= todayKey }
        let runs = StreakCalculator.runs(keys: dayKeys, calendar: calendar)
        let byDay = CalendarDayHelper.secondsByDay(for: sessions, now: now, calendar: calendar)
        let totalSeconds = CalendarDayHelper.totalSeconds(sessions: sessions, now: now)

        return BadgeID.allCases.map { id in
            switch id {
            case .firstSpark:
                let n = sessions.count
                return badge(id, unlocked: n >= 1, progress: Double(min(n, 1)), text: "\(min(n, 1))/1 次", date: sorted.first?.startTime)

            case .earlyBird:
                let hit = sorted.first { isEarlyBirdStart($0.startTime, calendar: calendar) }
                return badge(id, unlocked: hit != nil, progress: hit == nil ? 0 : 1,
                             text: hit == nil ? "尚未在 04:00–08:29 开始" : "已达成", date: hit?.startTime)

            case .streak7, .streak30:
                let target = id == .streak7 ? 7 : 30
                let longest = streak.longestStreak
                let run = runs.first { $0.length >= target }
                let date = run.flatMap { calendar.date(byAdding: .day, value: target - 1, to: $0.startDate) }
                return badge(id, unlocked: longest >= target, progress: Double(longest) / Double(target),
                             text: "\(min(longest, target))/\(target) 天", date: date)

            case .midnightGrinder:
                let hit = sorted.first { isMidnightSession($0, now: now, calendar: calendar) }
                return badge(id, unlocked: hit != nil, progress: hit == nil ? 0 : 1,
                             text: hit == nil ? "尚未在深夜打卡" : "已达成", date: hit?.startTime)

            case .eightHourDay:
                let target: TimeInterval = 8 * 3600
                let best = byDay.values.max() ?? 0
                let firstKey = byDay.filter { $0.value >= target }.keys.min()
                return badge(id, unlocked: best >= target, progress: best / target,
                             text: "\(DurationFormatter.shortHours(min(best, target)))/8h",
                             date: firstKey.flatMap { CalendarDayHelper.date(fromKey: $0, calendar: calendar) })

            case .centurion100, .legend500:
                let hours: Double = id == .centurion100 ? 100 : 500
                let target = hours * 3600
                return badge(id, unlocked: totalSeconds >= target, progress: totalSeconds / target,
                             text: String(format: "%.1f/%.0f 小时", min(totalSeconds, target) / 3600, hours),
                             date: dateReaching(target, sorted: sorted, now: now))

            case .logKeeper10:
                var noteDays: [String: Date] = [:]
                for s in sorted where !s.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let key = CalendarDayHelper.dateKey(for: s.startTime, calendar: calendar)
                    if noteDays[key] == nil { noteDays[key] = s.startTime }
                }
                let n = noteDays.count
                let date = n >= 10 ? noteDays.values.sorted()[9] : nil
                return badge(id, unlocked: n >= 10, progress: Double(n) / 10, text: "\(min(n, 10))/10 天", date: date)
            }
        }
    }

    // MARK: Rules

    /// Start time within 04:00–08:29 local time (inclusive).
    public static func isEarlyBirdStart(_ date: Date, calendar: Calendar = .current) -> Bool {
        let m = minuteOfDay(date, calendar: calendar)
        return m >= 4 * 60 && m <= 8 * 60 + 29
    }

    /// Session starts at/after 23:00, starts 00:00–03:59, ends (or is still running) after 23:00, or spans midnight.
    public static func isMidnightSession(_ session: LabSession, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let start = session.startTime
        if minuteOfDay(start, calendar: calendar) < 4 * 60 { return true }
        let dayStart = calendar.startOfDay(for: start)
        guard let elevenPM = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: dayStart) else { return false }
        if start >= elevenPM { return true }
        // Ending after 23:00 also covers sessions spanning midnight.
        return session.effectiveEnd(asOf: now) > elevenPM
    }

    // MARK: Helpers

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Moment cumulative time (sessions in start order) first reaches `target` seconds.
    static func dateReaching(_ target: TimeInterval, sorted: [LabSession], now: Date) -> Date? {
        var acc: TimeInterval = 0
        for s in sorted {
            let d = s.duration(asOf: now)
            if acc + d >= target { return s.startTime.addingTimeInterval(target - acc) }
            acc += d
        }
        return nil
    }

    static func badge(_ id: BadgeID, unlocked: Bool, progress: Double, text: String, date: Date?) -> AchievementBadge {
        let meta = metadata(id)
        return AchievementBadge(id: id, title: meta.title, subtitle: meta.subtitle, requirement: meta.requirement,
                                symbolName: meta.symbol, isUnlocked: unlocked, progress: unlocked ? 1 : progress,
                                progressText: text, unlockedDate: unlocked ? date : nil)
    }

    public static func metadata(_ id: BadgeID) -> (title: String, subtitle: String, requirement: String, symbol: String) {
        switch id {
        case .firstSpark: return ("初入研途", "First Spark", "完成第一次实验打卡", "sparkles")
        case .earlyBird: return ("早鸟进组", "Early Bird", "在 04:00–08:29 之间开始一次打卡", "sunrise")
        case .streak7: return ("连续 7 天", "Weekly Rhythm", "最长连续打卡达到 7 天", "flame")
        case .streak30: return ("连续 30 天", "Monthly Momentum", "最长连续打卡达到 30 天", "calendar")
        case .midnightGrinder: return ("深夜奋战", "Midnight Grinder", "在 23:00 之后仍在实验，或于 00:00–03:59 开始", "moon.zzz")
        case .eightHourDay: return ("单日 8 小时", "Eight-Hour Day", "单个自然日累计 8 小时", "clock.badge.checkmark")
        case .centurion100: return ("百小时达人", "Centurion", "累计实验时长 100 小时", "hourglass")
        case .legend500: return ("五百小时传说", "Five-Hundred Legend", "累计实验时长 500 小时", "star.circle")
        case .logKeeper10: return ("日理万机", "Log Keeper", "在 10 个不同日期写下实验笔记", "book.closed")
        }
    }
}
