import Foundation

/// What kind of research work a session represents.
///
/// Decoding is resilient: unknown raw values fall back to `.experiment`, so files written by a
/// newer LabForge (with categories this build does not know) still load.
public enum SessionCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case experiment
    case reading
    case writing
    case coding
    case meeting

    public var id: String { rawValue }

    public static let `default`: SessionCategory = .experiment

    public var title: String {
        switch self {
        case .experiment: return "实验炼丹"
        case .reading: return "文献研读"
        case .writing: return "论文写作"
        case .coding: return "代码分析"
        case .meeting: return "组会讨论"
        }
    }

    public var englishName: String {
        switch self {
        case .experiment: return "Experiment"
        case .reading: return "Reading"
        case .writing: return "Writing"
        case .coding: return "Coding"
        case .meeting: return "Meeting"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .experiment: return "flask"
        case .reading: return "book.closed"
        case .writing: return "pencil.and.outline"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .meeting: return "person.2"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionCategory(rawValue: raw) ?? .default
    }
}
