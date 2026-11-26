import Foundation
import Testing
@testable import LabForgeCore

@Suite struct BackwardCompatibilityTests {
    /// A records.json written by LabForge v1 (no category / profile / v1.1 preference keys).
    static let v1JSON = """
    {
      "schemaVersion" : 1,
      "sessions" : [
        {"id":"6F1C1D2E-0000-4000-8000-000000000001","startTime":"2026-01-01T01:00:00.000Z","endTime":"2026-01-01T04:00:00.000Z",
         "goal":"PCR","notes":"条带清晰","isManualEntry":false,"createdAt":"2026-01-01T01:00:00.000Z","updatedAt":"2026-01-01T04:00:00.000Z"},
        {"id":"6F1C1D2E-0000-4000-8000-000000000002","startTime":"2026-01-04T00:00:00.000Z",
         "goal":"细胞传代","notes":"","isManualEntry":true,"createdAt":"2026-01-04T00:00:00.000Z","updatedAt":"2026-01-04T00:00:00.000Z"}
      ],
      "dailyGoals" : {"2026-01-01":"完成 PCR"},
      "settings" : {"appearanceMode":"dark","dailyTargetHours":6,"reminderEnabled":true,"reminderHour":8,"reminderMinute":30,"launchAtLogin":false}
    }
    """

    @Test func v1RecordsDecodeWithDefaults() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        let data = try store.decodeImportedJSON(Data(Self.v1JSON.utf8))
        #expect(data.sessions.count == 2)
        #expect(data.sessions.allSatisfy { $0.category == .experiment })
        #expect(data.sessions[0].goal == "PCR" && data.sessions[1].isActive && data.sessions[1].isManualEntry)
        let s = data.settings
        #expect(s.appearanceMode == .dark && s.dailyTargetHours == 6.0 && s.reminderEnabled && s.reminderHour == 8 && s.reminderMinute == 30)
        #expect(s.researcherName == "" && s.labName == "" && s.researchFocus == "")
        #expect(s.weeklyTargetHours == 40.0)
        #expect(s.menuBarStyle == .full)
        #expect(s.soundEnabled && s.soundName == "Glass")
        #expect(s.globalShortcutEnabled)
        #expect(s.sleepPromptThresholdMinutes == 30)
        #expect(s.hideDockIcon)
        #expect(s == LabSettings(appearanceMode: .dark, dailyTargetHours: 6, reminderEnabled: true, reminderHour: 8, reminderMinute: 30))
    }

    @Test func v1RecordsLoadFromDisk() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.v1JSON.utf8).write(to: url)
        let loaded = try LabPersistenceStore(fileURL: url).load()
        #expect(loaded.sessions.count == 2 && loaded.settings.weeklyTargetHours == 40.0)
    }

    @Test func newFieldsRoundTrip() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        let settings = LabSettings(researcherName: "黄泽", labName: "张元课题组", researchFocus: "肿瘤免疫", weeklyTargetHours: 50,
                                   menuBarStyle: .iconOnly, soundEnabled: false, soundName: "Purr",
                                   globalShortcutEnabled: false, sleepPromptThresholdMinutes: 0)
        let data = LabStoreData(sessions: [LabSession(startTime: d(2026, 1, 1, 9), endTime: d(2026, 1, 1, 10), category: .reading)],
                                settings: settings)
        let decoded = try store.decodeImportedJSON(store.exportJSONData(from: data))
        #expect(decoded == data)
        #expect(decoded.sessions[0].category == .reading)
        let text = String(decoding: try store.exportJSONData(from: data), as: UTF8.self)
        #expect(text.contains("\"category\" : \"reading\"") && text.contains("\"menuBarStyle\" : \"iconOnly\""))
    }

    @Test func unknownCategoryAndStyleFallBack() throws {
        func sessionJSON(_ category: String) -> Data {
            Data("""
            {"id":"\(UUID().uuidString)","startTime":"2026-01-01T01:00:00Z","endTime":"2026-01-01T02:00:00Z","goal":"","notes":"",
             "isManualEntry":false,"createdAt":"2026-01-01T01:00:00Z","updatedAt":"2026-01-01T02:00:00Z","category":\(category)}
            """.utf8)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(LabSession.self, from: sessionJSON("\"alchemy\"")).category == .experiment)
        #expect(try decoder.decode(LabSession.self, from: sessionJSON("42")).category == .experiment)
        #expect(try decoder.decode(LabSession.self, from: sessionJSON("null")).category == .experiment)
        #expect(try decoder.decode(LabSession.self, from: sessionJSON("\"meeting\"")).category == .meeting)
        #expect(try JSONDecoder().decode(SessionCategory.self, from: Data(#""future""#.utf8)) == .experiment)

        let settings = try JSONDecoder().decode(LabSettings.self, from: Data(#"{"menuBarStyle":"hologram","soundEnabled":"yes","labName":7}"#.utf8))
        #expect(settings.menuBarStyle == .full && settings.soundEnabled && settings.labName == "")
        #expect(try JSONDecoder().decode(MenuBarDisplayStyle.self, from: Data(#""compact""#.utf8)) == .compact)
    }

    @Test func v1RequiredSessionFieldsStayStrict() {
        let missingStart = Data(#"{"id":"\#(UUID().uuidString)","goal":"","notes":"","isManualEntry":false,"createdAt":"2026-01-01T01:00:00Z","updatedAt":"2026-01-01T01:00:00Z"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(throws: DecodingError.self) { try decoder.decode(LabSession.self, from: missingStart) }
    }
}

@Suite struct ProfileSettingsTests {
    @Test func newDefaults() {
        let s = LabSettings()
        #expect(s.researcherName.isEmpty && s.labName.isEmpty && s.researchFocus.isEmpty)
        #expect(s.weeklyTargetHours == 40.0 && s.weeklyTargetSeconds == 40.0 * 3600.0)
        #expect(s.menuBarStyle == .full && s.soundEnabled && s.soundName == "Glass" && s.globalShortcutEnabled)
        #expect(s.sleepPromptThresholdMinutes == 30 && s.sleepPromptEnabled)
        #expect(LabSettings.availableSoundNames == ["Glass", "Hero", "Pop", "Tink", "Submarine", "Purr"])
        #expect(LabSettings.weeklyTargetRange == 5.0...112.0)
    }

    @Test func weeklyTargetClamping() {
        #expect(LabSettings(weeklyTargetHours: 1).weeklyTargetHours == 5.0)
        #expect(LabSettings(weeklyTargetHours: 500).weeklyTargetHours == 112.0)
        #expect(LabSettings(weeklyTargetHours: .nan).weeklyTargetHours == 40.0)
        #expect(LabSettings(weeklyTargetHours: .infinity).weeklyTargetHours == 40.0)
        var s = LabSettings()
        s.weeklyTargetHours = 0
        #expect(s.weeklyTargetHours == 5.0)
        s.weeklyTargetHours = 60.5
        #expect(s.weeklyTargetHours == 60.5 && s.weeklyTargetSeconds == 60.5 * 3600.0)
    }

    @Test func sleepThresholdClamping() {
        #expect(LabSettings(sleepPromptThresholdMinutes: 999).sleepPromptThresholdMinutes == 240)
        #expect(LabSettings(sleepPromptThresholdMinutes: -5).sleepPromptThresholdMinutes == 0)
        var s = LabSettings()
        s.sleepPromptThresholdMinutes = 0
        #expect(!s.sleepPromptEnabled)
        s.sleepPromptThresholdMinutes = 1000
        #expect(s.sleepPromptThresholdMinutes == 240)
    }

    @Test func decodingClampsNewFields() throws {
        let raw = Data(#"{"weeklyTargetHours":1000,"sleepPromptThresholdMinutes":-3}"#.utf8)
        let s = try JSONDecoder().decode(LabSettings.self, from: raw)
        #expect(s.weeklyTargetHours == 112.0 && s.sleepPromptThresholdMinutes == 0)
    }

    @Test func profileTrimming() {
        var s = LabSettings(researcherName: "  黄泽 \n", labName: " 张元课题组\t", researchFocus: "\n肿瘤免疫  ")
        #expect(s.effectiveResearcherName == "黄泽")
        #expect(s.trimmedLabName == "张元课题组")
        #expect(s.trimmedResearchFocus == "肿瘤免疫")
        s.researcherName = "   \n"
        #expect(s.effectiveResearcherName == "研究者")
        #expect(LabSettings().effectiveResearcherName == "研究者")
    }

    @Test func profilePersistsTrimmedText() throws {
        let settings = LabSettings(researcherName: "  黄 泽 ", labName: "  Lab Group  ", researchFocus: "   ")
        let restored = try JSONDecoder().decode(LabSettings.self, from: JSONEncoder().encode(settings))

        #expect(restored.researcherName == "黄 泽")
        #expect(restored.labName == "Lab Group")
        #expect(restored.researchFocus.isEmpty)
    }

    @Test func soundFallback() {
        #expect(LabSettings(soundName: "Hero").effectiveSoundName == "Hero")
        #expect(LabSettings(soundName: "Bogus").effectiveSoundName == "Glass")
    }

    @Test func enumMetadata() {
        #expect(SessionCategory.allCases.map(\.title) == ["实验炼丹", "文献研读", "论文写作", "代码分析", "组会讨论"])
        #expect(SessionCategory.allCases.map(\.englishName) == ["Experiment", "Reading", "Writing", "Coding", "Meeting"])
        #expect(SessionCategory.allCases.map(\.symbolName) == ["flask", "book.closed", "pencil.and.outline",
                                                               "chevron.left.forwardslash.chevron.right", "person.2"])
        #expect(SessionCategory.coding.id == "coding" && SessionCategory.default == .experiment)
        #expect(MenuBarDisplayStyle.allCases.map(\.displayName) == ["完整：火焰与时长", "极简：仅时长", "纯图标：省空间"])
        #expect(MenuBarDisplayStyle.iconOnly.id == "iconOnly")
        #expect(LabSession(startTime: d(2026, 1, 1)).category == .experiment)
    }

    @Test func hideDockIconDefaultsToTrue() {
        #expect(LabSettings().hideDockIcon)
        #expect(LabSettings(hideDockIcon: false).hideDockIcon == false)
    }

    @Test func hideDockIconRoundTrips() throws {
        for hidden in [false, true] {
            let original = LabSettings(hideDockIcon: hidden)
            let encoded = try JSONEncoder().encode(original)
            let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(object["hideDockIcon"] as? Bool == hidden)
            let restored = try JSONDecoder().decode(LabSettings.self, from: encoded)
            #expect(restored.hideDockIcon == hidden)
            #expect(restored == original)
        }
    }

    @Test func hideDockIconLegacyAndInvalidDecodeToTrue() throws {
        let legacy = try JSONDecoder().decode(LabSettings.self, from: Data(#"{"appearanceMode":"dark","dailyTargetHours":6}"#.utf8))
        #expect(legacy.hideDockIcon)
        #expect(legacy.dailyTargetHours == 6.0)
        let invalid = try JSONDecoder().decode(LabSettings.self, from: Data(#"{"hideDockIcon":"nope"}"#.utf8))
        #expect(invalid.hideDockIcon)
        let off = try JSONDecoder().decode(LabSettings.self, from: Data(#"{"hideDockIcon":false}"#.utf8))
        #expect(off.hideDockIcon == false)
    }
}
