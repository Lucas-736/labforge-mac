import Foundation
import Testing
@testable import LabForgeCore

func cs(_ start: Date, _ end: Date?, _ category: SessionCategory = .experiment, goal: String = "", notes: String = "",
        manual: Bool = false) -> LabSession {
    LabSession(startTime: start, endTime: end, goal: goal, notes: notes, isManualEntry: manual, category: category)
}

/// Thursday 2026-11-26 15:00 (Asia/Shanghai). Sunday-first week: 11-22 ..< 11-29.
let insightsNow = d(2026, 11, 26, 15)

@Suite struct WeeklyProgressTests {
    var sessions: [LabSession] {
        [
            cs(d(2026, 11, 21, 22), d(2026, 11, 22, 2)),   // spans week boundary: 2h prev + 2h this
            cs(d(2026, 11, 23, 9), d(2026, 11, 23, 12)),   // 3h
            cs(d(2026, 11, 25, 23), d(2026, 11, 26, 1)),   // 2h across midnight
            cs(d(2026, 11, 26, 14), nil),                  // active: 1h until now
            cs(d(2026, 11, 16, 10), d(2026, 11, 16, 11)),  // prev week 1h
            cs(d(2026, 11, 8, 10), d(2026, 11, 8, 15)),    // two weeks ago, ignored
        ]
    }

    @Test func sundayFirstWeek() {
        let p = InsightsEngine.weeklyProgress(sessions: sessions, weeklyTargetSeconds: 10.0 * 3600.0, now: insightsNow, calendar: cal)
        #expect(p.weekStart == d(2026, 11, 22) && p.weekEnd == d(2026, 11, 29))
        #expect(p.totalSeconds == 8.0 * 3600.0)
        #expect(p.targetSeconds == 10.0 * 3600.0)
        #expect(abs(p.progress - 0.8) < 1e-9)
        #expect(p.activeDays == 4)
        #expect(p.sessionCount == 4)
        #expect(p.previousWeekSeconds == 3.0 * 3600.0)
        #expect(p.remainingSeconds == 2.0 * 3600.0)
    }

    @Test func mondayFirstWeek() {
        var monday = cal
        monday.firstWeekday = 2
        let p = InsightsEngine.weeklyProgress(sessions: sessions, weeklyTargetSeconds: 40.0 * 3600.0, now: insightsNow, calendar: monday)
        #expect(p.weekStart == d(2026, 11, 23) && p.weekEnd == d(2026, 11, 30))
        #expect(p.totalSeconds == 6.0 * 3600.0)
        #expect(p.previousWeekSeconds == 5.0 * 3600.0)
        #expect(p.activeDays == 3 && p.sessionCount == 3)
    }

    @Test func progressClampsAndHandlesZeroTarget() {
        let over = InsightsEngine.weeklyProgress(sessions: sessions, weeklyTargetSeconds: 3600.0, now: insightsNow, calendar: cal)
        #expect(over.progress == 1.0 && over.remainingSeconds == 0.0)
        let zero = InsightsEngine.weeklyProgress(sessions: sessions, weeklyTargetSeconds: 0.0, now: insightsNow, calendar: cal)
        #expect(zero.progress == 0.0)
        let empty = InsightsEngine.weeklyProgress(sessions: [], weeklyTargetSeconds: 3600.0, now: insightsNow, calendar: cal)
        #expect(empty.totalSeconds == 0.0 && empty.activeDays == 0 && empty.sessionCount == 0 && empty.previousWeekSeconds == 0.0)
    }
}

@Suite struct CategoryBreakdownTests {
    var sessions: [LabSession] {
        [
            cs(d(2026, 11, 25, 9), d(2026, 11, 25, 12), .reading),     // 3h
            cs(d(2026, 11, 26, 9), d(2026, 11, 26, 10), .experiment),  // 1h
            cs(d(2026, 11, 19, 22), d(2026, 11, 20, 2), .coding),      // 4h, only 2h on 11-20
            cs(d(2026, 11, 1, 9), d(2026, 11, 1, 14), .writing),       // 5h, old
            cs(d(2026, 11, 26, 11), d(2026, 11, 26, 11), .meeting),    // zero length
        ]
    }

    @Test func allTimeRanking() {
        let b = InsightsEngine.categoryBreakdown(sessions: sessions, now: insightsNow, calendar: cal)
        #expect(b.map(\.category) == [.writing, .coding, .reading, .experiment])
        #expect(b.map(\.totalSeconds) == [5.0 * 3600.0, 4.0 * 3600.0, 3.0 * 3600.0, 3600.0])
        #expect(abs(b[0].percentage - 5.0 / 13.0) < 1e-9)
        #expect(abs(b.map(\.percentage).reduce(0, +) - 1.0) < 1e-9)
        #expect(b.allSatisfy { $0.sessionCount == 1 })
        #expect(b[0].id == .writing)
    }

    @Test func windowFiltering() {
        let b = InsightsEngine.categoryBreakdown(sessions: sessions, withinLastDays: 7, now: insightsNow, calendar: cal)
        #expect(b.map(\.category) == [.reading, .coding, .experiment])
        #expect(b.map(\.totalSeconds) == [3.0 * 3600.0, 2.0 * 3600.0, 3600.0])
        #expect(abs(b[0].percentage - 0.5) < 1e-9)
        #expect(abs(b.map(\.percentage).reduce(0, +) - 1.0) < 1e-9)
        let today = InsightsEngine.categoryBreakdown(sessions: sessions, withinLastDays: 1, now: insightsNow, calendar: cal)
        #expect(today.map(\.category) == [.experiment] && today[0].percentage == 1.0)
        #expect(InsightsEngine.categoryBreakdown(sessions: sessions, withinLastDays: 0, now: insightsNow, calendar: cal).isEmpty)
        #expect(InsightsEngine.categoryBreakdown(sessions: [], now: insightsNow, calendar: cal).isEmpty)
    }

    @Test func tiesFollowCaseOrderAndCountsAggregate() {
        let b = InsightsEngine.categoryBreakdown(sessions: [
            cs(d(2026, 11, 26, 9), d(2026, 11, 26, 10), .reading),
            cs(d(2026, 11, 26, 10), d(2026, 11, 26, 10, 30), .experiment),
            cs(d(2026, 11, 26, 11), d(2026, 11, 26, 11, 30), .experiment),
        ], now: insightsNow, calendar: cal)
        #expect(b.map(\.category) == [.experiment, .reading])
        #expect(b.map(\.sessionCount) == [2, 1])
    }
}

@Suite struct RecentGoalsTests {
    @Test func dedupOrderTrimLimit() {
        let sessions = [
            cs(d(2026, 11, 20, 9), d(2026, 11, 20, 10), goal: "PCR"),
            cs(d(2026, 11, 24, 9), d(2026, 11, 24, 10), goal: "  WB  "),
            cs(d(2026, 11, 25, 9), d(2026, 11, 25, 10), goal: "   "),
            cs(d(2026, 11, 26, 9), nil, goal: "PCR"),
        ]
        let goals = ["2026-11-25": "读文献", "2026-11-22": " ", "2026-11-23": "WB", "bad-key": "x", "2026-11-10": "\n组会汇报\n"]
        #expect(InsightsEngine.recentGoals(sessions: sessions, dailyGoals: goals, calendar: cal) == ["PCR", "读文献", "WB", "组会汇报"])
        #expect(InsightsEngine.recentGoals(sessions: sessions, dailyGoals: goals, limit: 2, calendar: cal) == ["PCR", "读文献"])
        #expect(InsightsEngine.recentGoals(sessions: sessions, dailyGoals: goals, limit: 0, calendar: cal).isEmpty)
        #expect(InsightsEngine.recentGoals(sessions: [], dailyGoals: [:], calendar: cal).isEmpty)
    }

    @Test func sameStartUsesUpdatedAt() {
        let a = LabSession(startTime: d(2026, 11, 26, 9), goal: "A", updatedAt: d(2026, 11, 26, 10))
        let b = LabSession(startTime: d(2026, 11, 26, 9), goal: "B", updatedAt: d(2026, 11, 26, 11))
        #expect(InsightsEngine.recentGoals(sessions: [a, b], dailyGoals: [:], calendar: cal) == ["B", "A"])
    }
}

@Suite struct CalmObservationTests {
    func observe(_ sessions: [LabSession], now: Date = insightsNow) -> [InsightsEngine.CalmObservation] {
        InsightsEngine.calmObservations(sessions: sessions, dailyTargetSeconds: 8.0 * 3600.0,
                                        weeklyTargetSeconds: 40.0 * 3600.0, now: now, calendar: cal)
    }

    @Test func emptyStateIsGentleStarter() {
        for input in [[], [cs(d(2026, 11, 26, 9), d(2026, 11, 26, 9))]] {
            let obs = observe(input)
            #expect(obs.count == 1 && obs[0].id == "starter" && !obs[0].detail.isEmpty)
        }
    }

    @Test func dormantWhenNothingRecent() {
        let obs = observe([cs(d(2026, 1, 1, 9), d(2026, 1, 1, 11))])
        #expect(obs.map(\.id) == ["dormant"])
        #expect(obs[0].detail.contains("2026-01-01") && obs[0].detail.contains("2 小时"))
    }

    @Test func populatedPeakTrendCategory() {
        let obs = observe([
            cs(d(2026, 11, 23, 9), d(2026, 11, 23, 12), .reading),
            cs(d(2026, 11, 24, 9), d(2026, 11, 24, 11), .experiment),
            cs(d(2026, 11, 25, 10), d(2026, 11, 25, 12), .reading),
            cs(d(2026, 11, 16, 9), d(2026, 11, 16, 10), .experiment),   // last week, before same point
            cs(d(2026, 11, 20, 9), d(2026, 11, 20, 10), .experiment),   // last week, after same point (Thu 15:00)
        ])
        #expect(obs.map(\.id) == ["peak-window", "weekly-pace", "top-category"])
        #expect(obs[0].title == "专注高峰：上午 09:00–12:00")
        #expect(obs[0].detail.contains("100%"))
        #expect(obs[0].symbolName == "sun.max")
        #expect(obs[1].title == "本周已投入 7 小时")
        #expect(obs[1].detail.contains("上周同期为 1 小时") && obs[1].detail.contains("多 6 小时") && obs[1].detail.contains("18%"))
        #expect(obs[2].title == "近 4 周以「文献研读」为主")
        #expect(obs[2].detail.contains("56%") && obs[2].detail.contains("「实验炼丹」（44%）"))
        #expect(obs[2].symbolName == "book.closed")
    }

    @Test func singleCategoryFallsBackToDailyAverage() {
        let obs = observe([
            cs(d(2026, 11, 21, 22, 30), d(2026, 11, 22, 1, 30)),  // late night, two days
            cs(d(2026, 11, 24, 23), d(2026, 11, 25, 2)),
        ])
        #expect(obs.map(\.id) == ["peak-window", "weekly-pace", "daily-average"])
        #expect(obs[0].title == "专注高峰：深夜 22:00–06:00" && obs[0].symbolName == "moon.stars")
        // Last week's 1.5h on Sat 11-21 is after the same point (Thu 15:00), so no same-period data.
        #expect(obs[1].detail.hasPrefix("上周同期暂无记录") && obs[1].detail.contains("11%"))
        // 6h over 4 active days.
        #expect(obs[2].title == "记录日平均 1 小时 30 分")
        #expect(obs[2].detail.contains("4 天") && obs[2].detail.contains("8 小时"))
    }

    @Test func weekNotStartedYet() {
        let obs = observe([cs(d(2026, 11, 18, 14), d(2026, 11, 18, 16))])
        #expect(obs.map(\.id) == ["peak-window", "weekly-pace", "daily-average"])
        #expect(obs[0].title == "专注高峰：下午 14:00–18:00")
        #expect(obs[1].title == "本周尚未开始记录" && obs[1].detail.contains("2 小时"))
    }
}

@Suite struct CSVExporterTests {
    func lines(_ csv: String) -> [String] {
        csv.components(separatedBy: "\r\n")
    }

    @Test func headerBOMAndEmpty() {
        let csv = CSVExporter.exportCSV(sessions: [], now: insightsNow, calendar: cal)
        #expect(csv == "日期,开始时间,结束时间,时长(小时),时长(分钟),分类,实验目标,科研日志,记录方式\r\n")
        let data = CSVExporter.exportCSVData(sessions: [], now: insightsNow, calendar: cal)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == csv)
    }

    @Test func rowsNewestFirstWithFormatting() {
        let csv = CSVExporter.exportCSV(sessions: [
            cs(d(2026, 11, 24, 9), d(2026, 11, 24, 10, 30), .reading, goal: "读综述", notes: "Nature 综述", manual: true),
            cs(d(2026, 11, 25, 23), d(2026, 11, 26, 1, 15), .coding, goal: "跑 scRNA"),
            cs(d(2026, 11, 26, 14), nil, .experiment, goal: "WB"),
        ], now: d(2026, 11, 26, 15, 30), calendar: cal)
        let l = lines(csv)
        #expect(l.count == 5 && l[4].isEmpty)
        #expect(l[1] == "2026-11-26,14:00,进行中,1.50,90,实验炼丹,WB,,计时记录")
        #expect(l[2] == "2026-11-25,23:00,2026-11-26 01:15,2.25,135,代码分析,跑 scRNA,,计时记录")
        #expect(l[3] == "2026-11-24,09:00,10:30,1.50,90,文献研读,读综述,Nature 综述,手动补录")
    }

    @Test func rfc4180Quoting() {
        let csv = CSVExporter.exportCSV(sessions: [
            cs(d(2026, 11, 24, 9), d(2026, 11, 24, 10), goal: #"说明, "引号""#, notes: "第一行\n第二行\r\n第三行"),
        ], now: insightsNow, calendar: cal)
        #expect(csv.contains(#","说明, ""引号""","第一行"# + "\n第二行\r\n第三行\","))
        #expect(CSVExporter.escape("plain") == "plain")
        #expect(CSVExporter.escape("a,b") == "\"a,b\"")
        #expect(CSVExporter.escape("a\"b") == "\"a\"\"b\"")
        #expect(CSVExporter.escape("a\rb") == "\"a\rb\"")
    }

    @Test func formulaInjectionNeutralized() {
        #expect(CSVExporter.neutralizeFormula("=cmd|' /C calc'!A0") == "'=cmd|' /C calc'!A0")
        #expect(CSVExporter.neutralizeFormula("+1") == "'+1")
        #expect(CSVExporter.neutralizeFormula("-1") == "'-1")
        #expect(CSVExporter.neutralizeFormula("@SUM(A1:A9)") == "'@SUM(A1:A9)")
        #expect(CSVExporter.neutralizeFormula("\tx") == "'\tx")
        #expect(CSVExporter.neutralizeFormula("\rx") == "'\rx")
        #expect(CSVExporter.neutralizeFormula("\nx") == "'\nx")
        #expect(CSVExporter.neutralizeFormula(" \tx") == "' \tx")
        #expect(CSVExporter.neutralizeFormula("＝1+1") == "'＝1+1")
        #expect(CSVExporter.neutralizeFormula("  =1+1") == "'  =1+1")
        #expect(CSVExporter.neutralizeFormula("1-2") == "1-2")
        #expect(CSVExporter.neutralizeFormula("PCR") == "PCR")
        #expect(CSVExporter.neutralizeFormula("") == "")

        let csv = CSVExporter.exportCSV(sessions: [
            cs(d(2026, 11, 24, 9), d(2026, 11, 24, 10), goal: "=HYPERLINK(\"x\")", notes: "@SUM(A1)"),
        ], now: insightsNow, calendar: cal)
        #expect(lines(csv)[1].hasSuffix(#","'=HYPERLINK(""x"")",'@SUM(A1),计时记录"#))
    }
}
