import Foundation
@testable import LabForgeCore

/// Fixed Gregorian calendar in Asia/Shanghai (no DST), Sunday-first weeks.
let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    c.locale = Locale(identifier: "en_US_POSIX")
    c.firstWeekday = 1
    return c
}()

func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0, calendar: Calendar = cal) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min, second: s))!
}

func session(_ start: Date, _ end: Date?, goal: String = "", notes: String = "", id: UUID = UUID(), updatedAt: Date? = nil) -> LabSession {
    LabSession(id: id, startTime: start, endTime: end, goal: goal, notes: notes, updatedAt: updatedAt)
}

/// A one-hour session starting at 10:00 on the given day.
func hourOn(_ y: Int, _ m: Int, _ day: Int, notes: String = "") -> LabSession {
    session(d(y, m, day, 10), d(y, m, day, 11), notes: notes)
}

func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("LabForgeTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("records.json")
}
