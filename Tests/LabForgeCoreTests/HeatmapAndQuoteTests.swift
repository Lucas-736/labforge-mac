import Foundation
import Testing
@testable import LabForgeCore

@Suite struct HeatmapTests {
    let now = d(2026, 1, 10, 15)

    @Test(arguments: [
        (0.0, 0), (-5, 0), (1, 1), (7199, 1), (7200, 2), (14399, 2), (14400, 3), (25199, 3), (25200, 4), (90000, 4),
    ])
    func intensity(seconds: Double, level: Int) {
        #expect(HeatmapBuilder.intensityLevel(forSeconds: seconds) == level)
    }

    @Test func build365() {
        let sessions = [
            session(d(2026, 1, 9, 22), d(2026, 1, 10, 3), goal: "测序"),
            session(d(2026, 1, 10, 9), nil, goal: "建库"),
            session(d(2025, 1, 10, 9), d(2025, 1, 10, 18)), // outside window
        ]
        let days = HeatmapBuilder.build365Days(sessions: sessions, dailyGoals: ["2026-01-09": "整理数据"], now: now, calendar: cal)
        #expect(days.count == 365)
        #expect(days.first!.id == "2025-01-11" && days.last!.id == "2026-01-10")
        #expect(days.last!.date == cal.startOfDay(for: now))
        #expect(Set(days.map(\.id)).count == 365)
        let today = days.last!
        #expect(today.totalSeconds == 3.0 * 3600.0 + 6.0 * 3600.0)
        #expect(today.sessionCount == 2 && today.intensityLevel == 4)
        #expect(today.goalSummary == "建库")
        let yesterday = days[363]
        #expect(yesterday.totalSeconds == 7200 && yesterday.intensityLevel == 2 && yesterday.goalSummary == "整理数据")
        #expect(days.dropLast(2).allSatisfy { $0.totalSeconds == 0 && $0.intensityLevel == 0 })
    }

    @Test(arguments: [1, 2])
    func weeksGrid(firstWeekday: Int) {
        var c = cal
        c.firstWeekday = firstWeekday
        let days = HeatmapBuilder.build365Days(sessions: [], dailyGoals: [:], now: now, calendar: c)
        let grid = HeatmapBuilder.buildWeeksGrid(days: days, calendar: c)
        #expect(grid.allSatisfy { $0.count == 7 })
        #expect(grid.count == 53)
        let flat = grid.flatMap { $0 }.compactMap { $0 }
        #expect(flat.map(\.id) == days.map(\.id)) // column-major order preserved
        for column in grid {
            for (row, day) in column.enumerated() {
                if let day {
                    let weekday = c.component(.weekday, from: day.date)
                    #expect((weekday - firstWeekday + 7) % 7 == row)
                }
            }
        }
        // 2025-01-11 is a Saturday, 2026-01-10 is a Saturday.
        if firstWeekday == 1 {
            #expect(grid[0].prefix(6).allSatisfy { $0 == nil } && grid[0][6]?.id == "2025-01-11")
            #expect(grid[52][6]?.id == "2026-01-10")
        } else {
            #expect(grid[0].prefix(5).allSatisfy { $0 == nil } && grid[0][5]?.id == "2025-01-11")
            #expect(grid[52][5]?.id == "2026-01-10" && grid[52][6] == nil)
        }
        #expect(HeatmapBuilder.buildWeeksGrid(days: [], calendar: c).isEmpty)
    }
}

@Suite struct QuoteTests {
    @Test func library() {
        let all = QuoteLibrary.allQuotes
        #expect(all.count >= 30)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.allSatisfy { !$0.text.isEmpty && !$0.author.isEmpty && !$0.tag.isEmpty })
    }

    @Test func dailyDeterminism() {
        let morning = QuoteLibrary.dailyQuote(for: d(2026, 5, 1, 0, 0, 1), calendar: cal)
        let night = QuoteLibrary.dailyQuote(for: d(2026, 5, 1, 23, 59, 59), calendar: cal)
        #expect(morning == night)
        let next = QuoteLibrary.dailyQuote(for: d(2026, 5, 2, 8), calendar: cal)
        #expect(next == QuoteLibrary.nextQuote(after: morning.id))
        // Full cycle returns to the same quote; dates before the reference work too.
        let n = QuoteLibrary.allQuotes.count
        #expect(QuoteLibrary.dailyQuote(for: cal.date(byAdding: .day, value: n, to: d(2026, 5, 1))!, calendar: cal) == morning)
        _ = QuoteLibrary.dailyQuote(for: d(1999, 1, 1), calendar: cal)
    }

    @Test func cycling() {
        let all = QuoteLibrary.allQuotes
        #expect(QuoteLibrary.nextQuote(after: all[0].id) == all[1])
        #expect(QuoteLibrary.nextQuote(after: all.last!.id) == all[0])
        #expect(QuoteLibrary.nextQuote(after: "unknown") == all[0])
        var id = all[0].id
        var seen = Set<String>()
        for _ in all { seen.insert(id); id = QuoteLibrary.nextQuote(after: id).id }
        #expect(seen.count == all.count && id == all[0].id)
    }
}
