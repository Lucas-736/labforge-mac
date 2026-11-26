import Foundation
import Testing
@testable import LabForgeCore

@Suite struct PersistenceTests {
    func sample() -> LabStoreData {
        LabStoreData(
            sessions: [
                session(d(2026, 1, 1, 9), d(2026, 1, 1, 12), goal: "PCR", notes: "条带清晰"),
                session(d(2026, 1, 2, 22), d(2026, 1, 3, 1)),
                session(d(2026, 1, 4, 8), nil, goal: "细胞传代"),
            ],
            dailyGoals: ["2026-01-01": "完成 PCR"],
            settings: LabSettings(appearanceMode: .dark, dailyTargetHours: 6, reminderEnabled: true, reminderHour: 8, reminderMinute: 30)
        )
    }

    @Test func defaultURL() {
        let url = LabPersistenceStore.defaultFileURL
        #expect(url.lastPathComponent == "records.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "LabForge")
        #expect(url.path.contains("Library/Application Support"))
    }

    @Test func loadMissingReturnsDefault() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        #expect(try store.load() == LabStoreData())
    }

    @Test func roundTrip() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LabPersistenceStore(fileURL: url)
        let data = sample()
        try store.save(data)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try store.load() == data)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.contains("2026-01-01T01:00:00.000Z")) // ISO 8601, UTC
        // Overwrite works.
        var changed = data
        changed.dailyGoals["2026-01-02"] = "读文献"
        try store.save(changed)
        #expect(try store.load() == changed)
    }

    @Test func fractionalSecondsPreserved() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        let start = Date(timeIntervalSince1970: 1_767_000_000.25)
        let data = LabStoreData(sessions: [session(start, start.addingTimeInterval(10.5))])
        #expect(try store.decodeImportedJSON(store.exportJSONData(from: data)) == data)
    }

    @Test func loadCorruptedThrows() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(throws: LabStoreError.self) { try LabPersistenceStore(fileURL: url).load() }
    }

    @Test func importAcceptsSecondPrecisionDates() throws {
        let json = """
        {"schemaVersion":1,"sessions":[{"id":"\(UUID().uuidString)","startTime":"2026-01-01T01:00:00Z","endTime":"2026-01-01T02:00:00Z",
        "goal":"","notes":"","isManualEntry":true,"createdAt":"2026-01-01T01:00:00Z","updatedAt":"2026-01-01T02:00:00Z"}],"dailyGoals":{}}
        """
        let data = try LabPersistenceStore(fileURL: tempStoreURL()).decodeImportedJSON(Data(json.utf8))
        #expect(data.sessions.count == 1 && data.sessions[0].duration() == 3600.0 && data.settings == LabSettings())
    }

    @Test func importRejectsBadInput() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        #expect(throws: LabStoreError.self) { try store.decodeImportedJSON(Data("[]".utf8)) }

        var future = sample()
        future.schemaVersion = 99
        #expect(throws: LabStoreError.unsupportedSchemaVersion(99)) {
            try store.decodeImportedJSON(store.exportJSONData(from: future))
        }

        let negative = LabStoreData(sessions: [session(d(2026, 1, 1, 12), d(2026, 1, 1, 11))])
        #expect(throws: LabStoreError.invalidSessionRange) {
            try store.decodeImportedJSON(store.exportJSONData(from: negative))
        }
    }

    @Test func importRejectsUnrelatedObjectsAndDuplicateRecords() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        for json in ["{}", #"{"unrelated":true}"#] {
            #expect(throws: LabStoreError.self) { try store.decodeImportedJSON(Data(json.utf8)) }
        }
        let record = hourOn(2026, 1, 1)
        let duplicate = try store.exportJSONData(from: LabStoreData(sessions: [record, record]))
        #expect(throws: LabStoreError.self) { try store.decodeImportedJSON(duplicate) }
    }

    @Test func importRepairsMultipleActiveSessions() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        let oldA = session(d(2026, 1, 1, 9), nil, updatedAt: d(2026, 1, 1, 11))
        let oldB = session(d(2026, 1, 2, 9), nil) // updatedAt == startTime
        let newest = session(d(2026, 1, 3, 9), nil)
        let raw = try store.exportJSONData(from: LabStoreData(sessions: [oldA, newest, oldB]))
        let fixed = try store.decodeImportedJSON(raw)
        #expect(fixed.sessions.filter(\.isActive).map(\.id) == [newest.id])
        #expect(fixed.sessions.first { $0.id == oldA.id }!.endTime == d(2026, 1, 1, 11))
        #expect(fixed.sessions.first { $0.id == oldB.id }!.endTime == d(2026, 1, 2, 9))
        #expect(fixed.activeSession?.id == newest.id)
    }

    @Test func mergeDeduplicates() {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        let id = UUID()
        let old = session(d(2026, 1, 1, 9), d(2026, 1, 1, 10), notes: "旧", id: id, updatedAt: d(2026, 1, 1, 10))
        let new = session(d(2026, 1, 1, 9), d(2026, 1, 1, 11), notes: "新", id: id, updatedAt: d(2026, 1, 5))
        let onlyExisting = hourOn(2026, 1, 2)
        let onlyImported = hourOn(2026, 1, 3)
        let existing = LabStoreData(sessions: [old, onlyExisting], dailyGoals: ["2026-01-01": "A", "2026-01-02": "B"],
                                    settings: LabSettings(appearanceMode: .dark))
        let imported = LabStoreData(sessions: [new, onlyImported], dailyGoals: ["2026-01-02": "B2", "2026-01-03": "C", "2026-01-01": " "])

        let merged = store.merge(imported: imported, into: existing)
        #expect(merged.sessions.count == 3)
        #expect(merged.sessions.map(\.id) == [id, onlyExisting.id, onlyImported.id])
        #expect(merged.sessions[0].notes == "新")
        #expect(merged.dailyGoals == ["2026-01-01": "A", "2026-01-02": "B2", "2026-01-03": "C"])
        #expect(merged.settings.appearanceMode == .dark)

        // Older imported copy loses.
        let reverse = store.merge(imported: LabStoreData(sessions: [old]), into: LabStoreData(sessions: [new]))
        #expect(reverse.sessions == [new])
    }

    @Test func mergeKeepsSingleActive() {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        let a = session(d(2026, 1, 1, 9), nil, updatedAt: d(2026, 1, 1, 12))
        let b = session(d(2026, 1, 2, 9), nil)
        let merged = store.merge(imported: LabStoreData(sessions: [a]), into: LabStoreData(sessions: [b]))
        #expect(merged.sessions.filter(\.isActive).map(\.id) == [b.id])
        #expect(merged.sessions.first { $0.id == a.id }!.endTime == d(2026, 1, 1, 12))
    }

    @Test func validateSession() throws {
        let store = LabPersistenceStore(fileURL: tempStoreURL())
        try store.validateSession(startTime: d(2026, 1, 1, 9), endTime: nil)
        try store.validateSession(startTime: d(2026, 1, 1, 9), endTime: d(2026, 1, 1, 9, 0, 1))
        #expect(throws: LabStoreError.invalidSessionRange) { try store.validateSession(startTime: d(2026, 1, 1, 9), endTime: d(2026, 1, 1, 9)) }
        #expect(throws: LabStoreError.invalidSessionRange) { try store.validateSession(startTime: d(2026, 1, 1, 9), endTime: d(2026, 1, 1, 8)) }
        #expect(LabStoreError.invalidSessionRange.errorDescription?.isEmpty == false)
    }
}
