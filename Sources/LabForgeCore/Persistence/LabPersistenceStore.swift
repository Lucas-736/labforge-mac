import Foundation

public enum LabStoreError: Error, LocalizedError, Sendable, Equatable {
    case invalidSessionRange
    case corruptedData(String)
    case unsupportedSchemaVersion(Int)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSessionRange: return "结束时间必须晚于开始时间。"
        case .corruptedData(let detail): return "数据文件已损坏或格式不正确：\(detail)"
        case .unsupportedSchemaVersion(let v): return "不支持的数据版本 \(v)（当前版本 \(LabStoreData.currentSchemaVersion)），请升级 LabForge。"
        case .ioFailure(let detail): return "读写数据文件失败：\(detail)"
        }
    }
}

/// JSON persistence for `LabStoreData`. Stateless apart from the file URL, so it is `Sendable`.
///
/// Dates are encoded as ISO 8601 strings with millisecond precision (UTC); decoding also accepts
/// ISO 8601 without fractional seconds.
public struct LabPersistenceStore: Sendable {
    public let fileURL: URL

    /// `~/Library/Application Support/LabForge/records.json`
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("LabForge", isDirectory: true).appendingPathComponent("records.json")
    }

    public init(fileURL: URL = LabPersistenceStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    // MARK: File IO

    /// Returns `LabStoreData()` when the file does not exist yet.
    public func load() throws -> LabStoreData {
        let raw: Data
        do {
            raw = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return LabStoreData()
        } catch {
            throw LabStoreError.ioFailure(error.localizedDescription)
        }
        return try validatedData(from: decode(raw))
    }

    /// Creates parent directories and writes pretty-printed JSON atomically.
    public func save(_ data: LabStoreData) throws {
        let encoded = try exportJSONData(from: data)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            throw LabStoreError.ioFailure(error.localizedDescription)
        }
    }

    // MARK: Import / Export

    public func exportJSONData(from data: LabStoreData) throws -> Data {
        do { return try Self.makeEncoder().encode(data) } catch { throw LabStoreError.corruptedData(error.localizedDescription) }
    }

    /// Decodes and validates imported JSON:
    /// - `schemaVersion` must be `1...currentSchemaVersion`;
    /// - any session with `endTime < startTime` throws `invalidSessionRange`;
    /// - session IDs must be unique;
    /// - multiple active sessions are repaired (newest kept, older ones closed).
    public func decodeImportedJSON(_ rawData: Data) throws -> LabStoreData {
        let data = try validatedData(from: decode(rawData))
        if data == LabStoreData() {
            let object = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any]
            guard LabStoreData.CodingKeys.allCases.contains(where: { object?[$0.rawValue] != nil }) else {
                throw LabStoreError.corruptedData("找不到 LabForge 备份字段")
            }
        }
        return data
    }

    private func validatedData(from data: LabStoreData) throws -> LabStoreData {
        try checkSchema(data)
        var ids = Set<UUID>()
        for session in data.sessions {
            guard ids.insert(session.id).inserted else {
                throw LabStoreError.corruptedData("重复的记录 ID：\(session.id)")
            }
            if let end = session.endTime, end < session.startTime { throw LabStoreError.invalidSessionRange }
        }
        return Self.normalizeActiveSessions(data)
    }

    /// Merges `imported` into `existing`: sessions deduplicated by `id` (newer `updatedAt` wins, ties keep
    /// existing), non-empty imported daily goals override, existing settings are kept, and at most one
    /// session remains active. Sessions are returned sorted by `startTime`.
    public func merge(imported: LabStoreData, into existing: LabStoreData) -> LabStoreData {
        var byID: [UUID: LabSession] = [:]
        for s in existing.sessions { byID[s.id] = s }
        for s in imported.sessions {
            if let current = byID[s.id], current.updatedAt >= s.updatedAt { continue }
            byID[s.id] = s
        }
        var goals = existing.dailyGoals
        for (key, goal) in imported.dailyGoals where !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            goals[key] = goal
        }
        let sessions = byID.values.sorted { ($0.startTime, $0.id.uuidString) < ($1.startTime, $1.id.uuidString) }
        let merged = LabStoreData(schemaVersion: LabStoreData.currentSchemaVersion, sessions: sessions,
                                  dailyGoals: goals, settings: existing.settings)
        return Self.normalizeActiveSessions(merged)
    }

    /// Throws `invalidSessionRange` when `endTime` is set and not after `startTime`.
    public func validateSession(startTime: Date, endTime: Date?) throws {
        if let end = endTime, end <= startTime { throw LabStoreError.invalidSessionRange }
    }

    // MARK: Helpers

    /// Keeps only the newest (by `startTime`) active session; older ones are closed at their
    /// `updatedAt` when that is after `startTime`, otherwise at `startTime`.
    public static func normalizeActiveSessions(_ data: LabStoreData) -> LabStoreData {
        let active = data.sessions.filter(\.isActive)
        guard active.count > 1, let keep = active.max(by: { $0.startTime < $1.startTime }) else { return data }
        var out = data
        out.sessions = data.sessions.map { s in
            guard s.isActive, s.id != keep.id else { return s }
            var closed = s
            closed.endTime = s.updatedAt > s.startTime ? s.updatedAt : s.startTime
            return closed
        }
        return out
    }

    private func decode(_ raw: Data) throws -> LabStoreData {
        do {
            return try Self.makeDecoder().decode(LabStoreData.self, from: raw)
        } catch {
            throw LabStoreError.corruptedData(String(describing: error))
        }
    }

    private func checkSchema(_ data: LabStoreData) throws {
        guard data.schemaVersion >= 1 else { throw LabStoreError.corruptedData("schemaVersion \(data.schemaVersion)") }
        guard data.schemaVersion <= LabStoreData.currentSchemaVersion else {
            throw LabStoreError.unsupportedSchemaVersion(data.schemaVersion)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let string = try c.decode(String.self)
            if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return d }
            if let d = try? Date.ISO8601FormatStyle().parse(string) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return decoder
    }
}
