import Foundation
import Testing
@testable import LabForgeCore

@Suite struct BadgeTests {
    let now = d(2026, 6, 30, 12)

    func badges(_ sessions: [LabSession], goals: [String: String] = [:]) -> [BadgeID: AchievementBadge] {
        Dictionary(uniqueKeysWithValues: BadgeEngine.evaluate(sessions: sessions, dailyGoals: goals, now: now, calendar: cal).map { ($0.id, $0) })
    }

    @Test func allNineLockedWhenEmpty() {
        let list = BadgeEngine.evaluate(sessions: [], dailyGoals: [:], now: now, calendar: cal)
        #expect(list.map(\.id) == BadgeID.allCases)
        #expect(list.count == 9)
        #expect(list.allSatisfy { !$0.isUnlocked && $0.progress == 0 && $0.unlockedDate == nil && !$0.title.isEmpty })
        #expect(list.map(\.title) == ["初入研途", "早鸟进组", "连续 7 天", "连续 30 天", "深夜奋战", "单日 8 小时", "百小时达人", "五百小时传说", "日理万机"])
    }

    @Test func firstSpark() {
        let s = session(d(2026, 6, 1, 14), d(2026, 6, 1, 15))
        let b = badges([s])[.firstSpark]!
        #expect(b.isUnlocked && b.progress == 1 && b.unlockedDate == s.startTime)
    }

    @Test(arguments: [
        (4, 0, true), (6, 30, true), (8, 29, true), (8, 30, false), (3, 59, false), (0, 0, false), (14, 0, false),
    ])
    func earlyBirdWindow(hour: Int, minute: Int, expected: Bool) {
        let s = session(d(2026, 6, 1, hour, minute), d(2026, 6, 1, hour, minute).addingTimeInterval(1800))
        #expect(badges([s])[.earlyBird]!.isUnlocked == expected)
    }

    @Test(arguments: [
        // (startH, startM, endH, endM, endDayOffset, expected)
        (0, 0, 1, 0, 0, true),     // starts 00:00
        (3, 59, 5, 0, 0, true),    // starts 03:59
        (4, 0, 5, 0, 0, false),    // early bird, not midnight
        (23, 0, 23, 30, 0, true),  // starts at 23:00
        (21, 0, 23, 1, 0, true),   // ends after 23:00
        (21, 0, 23, 0, 0, false),  // ends exactly 23:00
        (22, 0, 1, 0, 1, true),    // spans midnight
        (9, 0, 18, 0, 0, false),
    ])
    func midnightRules(sh: Int, sm: Int, eh: Int, em: Int, offset: Int, expected: Bool) {
        let s = session(d(2026, 6, 1, sh, sm), d(2026, 6, 1 + offset, eh, em))
        #expect(badges([s])[.midnightGrinder]!.isUnlocked == expected)
    }

    @Test func midnightActiveSession() {
        let s = session(d(2026, 6, 29, 22), nil)
        let late = BadgeEngine.evaluate(sessions: [s], dailyGoals: [:], now: d(2026, 6, 29, 23, 5), calendar: cal)
        #expect(late.first { $0.id == .midnightGrinder }!.isUnlocked)
        let early = BadgeEngine.evaluate(sessions: [s], dailyGoals: [:], now: d(2026, 6, 29, 22, 30), calendar: cal)
        #expect(!early.first { $0.id == .midnightGrinder }!.isUnlocked)
    }

    @Test func earlyBirdIsNotMidnightAndViceVersa() {
        let b = badges([session(d(2026, 6, 1, 2), d(2026, 6, 1, 3))])
        #expect(b[.midnightGrinder]!.isUnlocked && !b[.earlyBird]!.isUnlocked)
    }

    @Test func streaks() {
        let six = badges((1...6).map { hourOn(2026, 5, $0) })
        #expect(!six[.streak7]!.isUnlocked && six[.streak7]!.progressText == "6/7 天")
        #expect(abs(six[.streak7]!.progress - 6.0 / 7.0) < 1e-9)

        let seven = badges((1...7).map { hourOn(2026, 5, $0) })
        #expect(seven[.streak7]!.isUnlocked && seven[.streak7]!.unlockedDate == d(2026, 5, 7))
        #expect(!seven[.streak30]!.isUnlocked)

        let thirty = badges((1...30).map { hourOn(2026, 4, $0) })
        #expect(thirty[.streak30]!.isUnlocked && thirty[.streak7]!.isUnlocked)
    }

    @Test func eightHourDay() {
        let almost = badges([session(d(2026, 6, 1, 9), d(2026, 6, 1, 16, 59))])
        #expect(!almost[.eightHourDay]!.isUnlocked)
        let exact = badges([session(d(2026, 6, 1, 9), d(2026, 6, 1, 13)), session(d(2026, 6, 1, 14), d(2026, 6, 1, 18))])
        #expect(exact[.eightHourDay]!.isUnlocked && exact[.eightHourDay]!.unlockedDate == d(2026, 6, 1))
        // 10h split across midnight (5h + 5h) does not count as an 8h day.
        let split = badges([session(d(2026, 6, 1, 19), d(2026, 6, 2, 5))])
        #expect(!split[.eightHourDay]!.isUnlocked)
    }

    @Test func hourThresholds() {
        // 50 sessions × 2h = 100h
        let sessions = (0..<50).map { i -> LabSession in
            let start = d(2026, 1, 1, 9).addingTimeInterval(Double(i) * 86400)
            return session(start, start.addingTimeInterval(7200))
        }
        let b = badges(sessions)
        #expect(b[.centurion100]!.isUnlocked)
        #expect(b[.centurion100]!.unlockedDate == sessions.last!.endTime)
        #expect(!b[.legend500]!.isUnlocked && abs(b[.legend500]!.progress - 0.2) < 1e-9)
        #expect(b[.legend500]!.progressText == "100.0/500 小时")
        #expect(!badges(Array(sessions.dropLast()))[.centurion100]!.isUnlocked)

        let marathon = badges([session(d(2026, 1, 1), d(2026, 1, 1).addingTimeInterval(500 * 3600))])
        #expect(marathon[.legend500]!.isUnlocked)
    }

    @Test func logKeeper() {
        let nine = (1...9).map { hourOn(2026, 5, $0, notes: "记录 \($0)") }
        let extras = [hourOn(2026, 5, 1, notes: "same day"), hourOn(2026, 5, 20, notes: "   \n")]
        let b9 = badges(nine + extras)
        #expect(!b9[.logKeeper10]!.isUnlocked && b9[.logKeeper10]!.progressText == "9/10 天")
        let b10 = badges(nine + extras + [hourOn(2026, 5, 15, notes: "第十天")])
        #expect(b10[.logKeeper10]!.isUnlocked && b10[.logKeeper10]!.unlockedDate == d(2026, 5, 15, 10))
    }
}
