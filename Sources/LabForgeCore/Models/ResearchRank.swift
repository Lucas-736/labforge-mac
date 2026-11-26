import Foundation

/// Five research ranks unlocked by cumulative lab hours.
public enum ResearchRank: Int, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case novice = 1
    case apprentice = 2
    case alchemist = 3
    case harvester = 4
    case legend = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .novice: return "学术萌新"
        case .apprentice: return "烧瓶学徒"
        case .alchemist: return "深夜炼丹师"
        case .harvester: return "顶会收割机"
        case .legend: return "实验室传说"
        }
    }

    public var englishSubtitle: String {
        switch self {
        case .novice: return "Academic Novice"
        case .apprentice: return "Flask Apprentice"
        case .alchemist: return "Midnight Alchemist"
        case .harvester: return "Top-Venue Harvester"
        case .legend: return "Lab Legend"
        }
    }

    public var motto: String {
        switch self {
        case .novice: return "每一个专家，都曾是认真提问的新手。"
        case .apprentice: return "移液枪握稳了，世界就慢慢清晰了。"
        case .alchemist: return "夜色是最安静的合作者。"
        case .harvester: return "积累终会在某一天，变成别人眼中的突然。"
        case .legend: return "你走过的路，成了后来者的地图。"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .novice: return "leaf"
        case .apprentice: return "flask"
        case .alchemist: return "moon.stars"
        case .harvester: return "trophy"
        case .legend: return "crown"
        }
    }

    /// Cumulative hours required to reach this rank.
    public var minHours: Double {
        switch self {
        case .novice: return 0
        case .apprentice: return 20
        case .alchemist: return 80
        case .harvester: return 200
        case .legend: return 500
        }
    }

    public var nextRank: ResearchRank? { ResearchRank(rawValue: rawValue + 1) }

    public static func < (lhs: ResearchRank, rhs: ResearchRank) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Progress snapshot toward the next rank.
public struct RankProgress: Sendable, Equatable, Hashable {
    public var currentRank: ResearchRank
    public var nextRank: ResearchRank?
    public var totalHours: Double
    /// 0...1; `1` at the top rank.
    public var progressToNext: Double
    /// `0` at the top rank.
    public var hoursToNextRank: Double

    public init(currentRank: ResearchRank, nextRank: ResearchRank?, totalHours: Double, progressToNext: Double, hoursToNextRank: Double) {
        self.currentRank = currentRank
        self.nextRank = nextRank
        self.totalHours = totalHours
        self.progressToNext = progressToNext
        self.hoursToNextRank = hoursToNextRank
    }
}
