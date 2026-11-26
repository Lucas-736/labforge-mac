import Foundation
import Testing
@testable import LabForgeCore

@Suite struct CalendarDayHelperTests {
    @Test func midnightDSTDoesNotShiftTheFollowingDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let start = try #require(calendar.date(from: DateComponents(year: 2018, month: 11, day: 3, hour: 23)))
        let end = try #require(calendar.date(from: DateComponents(year: 2018, month: 11, day: 5, hour: 2)))
        let segments = CalendarDayHelper.daySegments(for: session(start, end), calendar: calendar)
        #expect(segments.map(\.dateKey) == ["2018-11-03", "2018-11-04", "2018-11-05"])
        #expect(segments.map(\.seconds) == [3600.0, 23.0 * 3600.0, 2.0 * 3600.0])
    }

    @Test func keys() {
        #expect(CalendarDayHelper.dateKey(for: d(2026, 3, 7, 23, 59), calendar: cal) == "2026-03-07")
        #expect(CalendarDayHelper.date(fromKey: "2026-03-07", calendar: cal) == d(2026, 3, 7))
        #expect(CalendarDayHelper.date(fromKey: "2024-02-29", calendar: cal) == d(2024, 2, 29))
        #expect(CalendarDayHelper.date(fromKey: "2023-02-29", calendar: cal) == nil)
        #expect(CalendarDayHelper.date(fromKey: "2026-3-7", calendar: cal) == nil)
        #expect(CalendarDayHelper.date(fromKey: "garbage", calendar: cal) == nil)
    }

    @Test func keyIsLocaleIndependent() {
        var buddhist = Calendar(identifier: .gregorian)
        buddhist.timeZone = cal.timeZone
        buddhist.locale = Locale(identifier: "th_TH")
        #expect(CalendarDayHelper.dateKey(for: d(2026, 3, 7, 12), calendar: buddhist) == "2026-03-07")
    }

    @Test func midnightSplitTwoDays() {
        let s = session(d(2026, 1, 1, 22), d(2026, 1, 2, 1, 30))
        let byDay = CalendarDayHelper.secondsByDay(for: [s], now: d(2026, 1, 3), calendar: cal)
        #expect(byDay == ["2026-01-01": 7200.0, "2026-01-02": 5400.0])
        #expect(CalendarDayHelper.sessionCountsByDay(for: [s], now: d(2026, 1, 3), calendar: cal) == ["2026-01-01": 1, "2026-01-02": 1])
    }

    @Test func midnightSplitThreeDays() {
        let s = session(d(2026, 1, 31, 20), d(2026, 2, 2, 2))
        let byDay = CalendarDayHelper.secondsByDay(for: [s], now: d(2026, 2, 3), calendar: cal)
        #expect(byDay == ["2026-01-31": 4.0 * 3600.0, "2026-02-01": 24.0 * 3600.0, "2026-02-02": 2.0 * 3600.0])
        #expect(byDay.values.reduce(0, +) == s.duration())
    }

    @Test func activeSessionCountsUntilNow() {
        let s = session(d(2026, 1, 1, 23), nil)
        let now = d(2026, 1, 2, 0, 30)
        #expect(CalendarDayHelper.secondsByDay(for: [s], now: now, calendar: cal) == ["2026-01-01": 3600.0, "2026-01-02": 1800.0])
        #expect(CalendarDayHelper.totalSeconds(on: now, sessions: [s], now: now, calendar: cal) == 1800.0)
        #expect(CalendarDayHelper.totalSeconds(sessions: [s], now: now) == 5400.0)
        #expect(CalendarDayHelper.sessionCountsByDay(for: [s], now: now, calendar: cal)["2026-01-02"] == 1)
    }

    @Test func dstDaySplit() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-03-08 is a 23-hour day in New York.
        let s = session(d(2026, 3, 7, 23, calendar: ny), d(2026, 3, 9, 1, calendar: ny))
        let byDay = CalendarDayHelper.secondsByDay(for: [s], now: d(2026, 3, 10, calendar: ny), calendar: ny)
        #expect(byDay == ["2026-03-07": 3600.0, "2026-03-08": 23.0 * 3600.0, "2026-03-09": 3600.0])
    }

    @Test func dailySummaries() {
        let a = session(d(2026, 1, 1, 9), d(2026, 1, 1, 10), goal: "PCR")
        let b = session(d(2026, 1, 1, 23), d(2026, 1, 2, 1), goal: "WB")
        let summaries = CalendarDayHelper.dailySummaries(sessions: [b, a], dailyGoals: ["2026-01-01": "跑胶", "2026-01-05": "读文献", "2026-01-06": "  "],
                                                         now: d(2026, 1, 6), calendar: cal)
        #expect(summaries.map(\.dateKey) == ["2026-01-05", "2026-01-02", "2026-01-01"])
        let jan1 = summaries[2]
        #expect(jan1.id == "2026-01-01" && jan1.goal == "跑胶" && jan1.sessionCount == 2 && jan1.totalSeconds == 7200.0)
        #expect(jan1.sessions.map(\.id) == [a.id, b.id])
        #expect(jan1.date == d(2026, 1, 1))
        #expect(summaries[1].totalSeconds == 3600.0 && summaries[1].sessionCount == 1)
        #expect(summaries[0].sessionCount == 0 && summaries[0].goal == "读文献")
    }
}

@Suite struct StreakTests {
    let now = d(2026, 1, 10, 15)

    @Test func empty() {
        #expect(StreakCalculator.compute(sessions: [], now: now, calendar: cal) == .empty)
    }

    @Test func activeSessionCountsToday() {
        let s = StreakCalculator.compute(sessions: [session(d(2026, 1, 10, 14, 59), nil)], now: now, calendar: cal)
        #expect(s == StreakSummary(currentStreak: 1, longestStreak: 1, isCheckedInToday: true, totalActiveDays: 1))
    }

    @Test func yesterdayPreserved() {
        let sessions = [hourOn(2026, 1, 7), hourOn(2026, 1, 8), hourOn(2026, 1, 9)]
        let s = StreakCalculator.compute(sessions: sessions, now: now, calendar: cal)
        #expect(s.currentStreak == 3 && !s.isCheckedInToday && s.longestStreak == 3)
    }

    @Test func todayExtends() {
        let sessions = [hourOn(2026, 1, 8), hourOn(2026, 1, 9), hourOn(2026, 1, 10), hourOn(2026, 1, 10)]
        let s = StreakCalculator.compute(sessions: sessions, now: now, calendar: cal)
        #expect(s.currentStreak == 3 && s.isCheckedInToday && s.totalActiveDays == 3)
    }

    @Test func broken() {
        let s = StreakCalculator.compute(sessions: [hourOn(2026, 1, 7), hourOn(2026, 1, 8)], now: now, calendar: cal)
        #expect(s.currentStreak == 0 && !s.isCheckedInToday && s.longestStreak == 2)
    }

    @Test func longestAcrossGaps() {
        var sessions = (1...5).map { hourOn(2025, 12, $0) }        // 5
        sessions += (20...31).map { hourOn(2025, 12, $0) }         // 12 + Jan 1–2 = 14
        sessions += [hourOn(2026, 1, 1), hourOn(2026, 1, 2)]
        sessions += [hourOn(2026, 1, 9), hourOn(2026, 1, 10)]      // current 2
        let s = StreakCalculator.compute(sessions: sessions, now: now, calendar: cal)
        #expect(s.longestStreak == 14 && s.currentStreak == 2 && s.totalActiveDays == 21)
    }

    @Test func midnightSessionBridgesDays() {
        let s = StreakCalculator.compute(sessions: [session(d(2026, 1, 8, 22), d(2026, 1, 9, 2))], now: now, calendar: cal)
        #expect(s.currentStreak == 2 && s.longestStreak == 2)
    }

    @Test func futureDaysIgnored() {
        let s = StreakCalculator.compute(sessions: [hourOn(2026, 2, 1)], now: now, calendar: cal)
        #expect(s == .empty)
    }
}
