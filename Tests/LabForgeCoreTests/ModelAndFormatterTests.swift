import Foundation
import Testing
@testable import LabForgeCore

@Suite struct LabSessionTests {
    @Test func activeAndDuration() {
        let s = session(d(2026, 1, 1, 9), nil)
        #expect(s.isActive)
        #expect(s.duration(asOf: d(2026, 1, 1, 10, 30)) == 5400)
        #expect(s.duration(asOf: d(2026, 1, 1, 8)) == 0) // clamped
        let closed = session(d(2026, 1, 1, 9), d(2026, 1, 1, 9, 45))
        #expect(!closed.isActive)
        #expect(closed.duration(asOf: d(2030, 1, 1)) == 2700)
        #expect(session(d(2026, 1, 1, 9), d(2026, 1, 1, 8)).duration() == 0)
    }
}

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = LabSettings()
        #expect(s.appearanceMode == .light)
        #expect(s.dailyTargetHours == 8)
        #expect(!s.reminderEnabled && s.reminderHour == 9 && s.reminderMinute == 0 && !s.launchAtLogin)
        #expect(AppearanceMode.default == .light)
        #expect(AppearanceMode.light.displayName == "Claude 暖浅色")
        #expect(AppearanceMode.dark.displayName == "暖炭黑")
        #expect(AppearanceMode.system.displayName == "跟随系统")
    }

    @Test func clamping() {
        #expect(LabSettings(dailyTargetHours: 0.2).dailyTargetHours == 1)
        #expect(LabSettings(dailyTargetHours: 30).dailyTargetHours == 16)
        var s = LabSettings()
        s.dailyTargetHours = 100
        #expect(s.dailyTargetHours == 16)
        s.reminderHour = 99
        s.reminderMinute = -5
        #expect(s.reminderHour == 23 && s.reminderMinute == 0)
    }

    @Test func resilientDecoding() throws {
        let partial = #"{"appearanceMode":"dark","dailyTargetHours":40}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(LabSettings.self, from: partial)
        #expect(s.appearanceMode == .dark)
        #expect(s.dailyTargetHours == 16)
        #expect(s.reminderHour == 9 && !s.launchAtLogin)
        let bogus = #"{"appearanceMode":"neon"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(LabSettings.self, from: bogus) == LabSettings())
        #expect(try JSONDecoder().decode(LabSettings.self, from: Data("{}".utf8)) == LabSettings())
    }

    @Test func storeDataDefaultsWhenKeysMissing() throws {
        let data = try JSONDecoder().decode(LabStoreData.self, from: Data("{}".utf8))
        #expect(data == LabStoreData())
        #expect(data.schemaVersion == 1)
    }
}

@Suite struct DurationFormatterTests {
    @Test func menuBar() {
        #expect(DurationFormatter.menuBarDuration(2 * 3600 + 18 * 60 + 59) == "02:18")
        #expect(DurationFormatter.menuBarDuration(0) == "00:00")
        #expect(DurationFormatter.menuBarDuration(-50) == "00:00")
        #expect(DurationFormatter.menuBarDuration(125 * 3600) == "125:00")
        #expect(DurationFormatter.menuBarDuration(.nan) == "00:00")
    }

    @Test func live() {
        #expect(DurationFormatter.liveTimer(2 * 3600 + 18 * 60 + 5) == "02:18:05")
        #expect(DurationFormatter.liveTimer(59.9) == "00:00:59")
        #expect(DurationFormatter.liveTimer(-1) == "00:00:00")
    }

    @Test func human() {
        #expect(DurationFormatter.humanReadable(2 * 3600 + 18 * 60) == "2 小时 18 分")
        #expect(DurationFormatter.humanReadable(45 * 60) == "45 分钟")
        #expect(DurationFormatter.humanReadable(3 * 3600) == "3 小时")
        #expect(DurationFormatter.humanReadable(59) == "不足 1 分钟")
        #expect(DurationFormatter.humanReadable(-100) == "不足 1 分钟")
    }

    @Test func short() {
        #expect(DurationFormatter.shortHours(2.3 * 3600) == "2.3h")
        #expect(DurationFormatter.shortHours(0) == "0.0h")
        #expect(DurationFormatter.shortHours(-10) == "0.0h")
        #expect(DurationFormatter.shortHours(100 * 3600) == "100.0h")
    }
}

@Suite struct RankTests {
    @Test func metadata() {
        #expect(ResearchRank.allCases.map(\.title) == ["学术萌新", "烧瓶学徒", "深夜炼丹师", "顶会收割机", "实验室传说"])
        #expect(ResearchRank.allCases.map(\.minHours) == [0, 20, 80, 200, 500])
        #expect(ResearchRank.alchemist.englishSubtitle == "Midnight Alchemist")
        #expect(ResearchRank.novice.nextRank == .apprentice)
        #expect(ResearchRank.legend.nextRank == nil)
        #expect(ResearchRank.allCases.allSatisfy { !$0.motto.isEmpty && !$0.symbolName.isEmpty })
    }

    @Test(arguments: [
        (0.0, ResearchRank.novice), (19.99, .novice), (20, .apprentice), (79.9, .apprentice),
        (80, .alchemist), (199.9, .alchemist), (200, .harvester), (499.9, .harvester), (500, .legend), (5000, .legend), (-3, .novice),
    ])
    func boundaries(hours: Double, expected: ResearchRank) {
        #expect(RankEngine.rank(forTotalHours: hours) == expected)
    }

    @Test func progress() {
        let p = RankEngine.progress(forTotalSeconds: 50 * 3600)
        #expect(p.currentRank == .apprentice && p.nextRank == .alchemist)
        #expect(abs(p.progressToNext - 0.5) < 1e-9)
        #expect(abs(p.hoursToNextRank - 30) < 1e-9)
        #expect(p.totalHours == 50)

        let zero = RankEngine.progress(forTotalSeconds: 0)
        #expect(zero.currentRank == .novice && zero.progressToNext == 0 && zero.hoursToNextRank == 20)

        let top = RankEngine.progress(forTotalSeconds: 600 * 3600)
        #expect(top.currentRank == .legend && top.nextRank == nil && top.progressToNext == 1 && top.hoursToNextRank == 0)
    }
}
