import Foundation

/// Spreadsheet-friendly CSV export of sessions. Pure and `Sendable`.
///
/// - One row per session, **newest first** by `startTime` (matching HistoryView).
/// - RFC 4180: CRLF line endings; fields containing `,` `"` CR or LF are quoted and `"` is doubled.
/// - Free-text fields (goal, notes) that could be read as spreadsheet formulas are prefixed with `'`.
/// - Dates and times are rendered in `calendar`'s time zone, locale-independently.
/// - Active sessions show `进行中` as the end time and are measured up to `now`.
public enum CSVExporter: Sendable {

    public static let header: [String] = ["日期", "开始时间", "结束时间", "时长(小时)", "时长(分钟)", "分类", "实验目标", "科研日志", "记录方式"]
    public static let activeEndLabel = "进行中"
    public static let manualEntryLabel = "手动补录"
    public static let timerEntryLabel = "计时记录"
    static let lineEnding = "\r\n"
    static let byteOrderMark = "\u{FEFF}"

    public static func exportCSV(sessions: [LabSession], now: Date = Date(), calendar: Calendar = .current) -> String {
        let ordered = sessions.sorted {
            $0.startTime != $1.startTime ? $0.startTime > $1.startTime : $0.id.uuidString < $1.id.uuidString
        }
        var lines = [header.map(escape).joined(separator: ",")]
        for s in ordered {
            let duration = s.duration(asOf: now)
            let end: String
            if let e = s.endTime {
                end = calendar.isDate(e, inSameDayAs: s.startTime)
                    ? time(e, calendar) : "\(CalendarDayHelper.dateKey(for: e, calendar: calendar)) \(time(e, calendar))"
            } else {
                end = activeEndLabel
            }
            let fields = [
                CalendarDayHelper.dateKey(for: s.startTime, calendar: calendar),
                time(s.startTime, calendar),
                end,
                String(format: "%.2f", duration / 3600),
                String(Int((duration / 60).rounded(.down))),
                s.category.title,
                neutralizeFormula(s.goal),
                neutralizeFormula(s.notes),
                s.isManualEntry ? manualEntryLabel : timerEntryLabel,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: lineEnding) + lineEnding
    }

    /// UTF-8 bytes prefixed with a BOM (`EF BB BF`) so Excel and Numbers detect the encoding.
    public static func exportCSVData(sessions: [LabSession], now: Date = Date(), calendar: Calendar = .current) -> Data {
        Data((byteOrderMark + exportCSV(sessions: sessions, now: now, calendar: calendar)).utf8)
    }

    /// RFC 4180 field escaping.
    public static func escape(_ field: String) -> String {
        let needsQuoting = field.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Prefixes an apostrophe for spreadsheet formula markers and leading control whitespace.
    public static func neutralizeFormula(_ field: String) -> String {
        let triggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "＝", "＋", "－", "＠", "\t", "\r", "\n"]
        let prefix = field.unicodeScalars.first { scalar in
            triggers.contains(scalar) || !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return prefix.map(triggers.contains) == true ? "'" + field : field
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
