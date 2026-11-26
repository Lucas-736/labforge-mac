import Foundation

public enum RankEngine: Sendable {

    /// Highest rank whose `minHours` is `<= hours`.
    public static func rank(forTotalHours hours: Double) -> ResearchRank {
        let h = hours.isFinite ? hours : 0
        return ResearchRank.allCases.last { h >= $0.minHours } ?? .novice
    }

    public static func progress(forTotalSeconds seconds: TimeInterval) -> RankProgress {
        let hours = (seconds.isFinite && seconds > 0) ? seconds / 3600 : 0
        let current = rank(forTotalHours: hours)
        guard let next = current.nextRank else {
            return RankProgress(currentRank: current, nextRank: nil, totalHours: hours, progressToNext: 1, hoursToNextRank: 0)
        }
        let span = next.minHours - current.minHours
        let progress = min(max((hours - current.minHours) / span, 0), 1)
        return RankProgress(currentRank: current, nextRank: next, totalHours: hours,
                            progressToNext: progress, hoursToNextRank: max(0, next.minHours - hours))
    }
}
