import LabForgeCore
import SwiftUI

struct RanksAndBadgesView: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        let progress = viewModel.rankProgress
        let badges = viewModel.badges

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClaudePageHeader(eyebrow: "Ranks & Badges", title: "段位与徽章",
                                 subtitle: "时间会被铸成段位，习惯会被刻成徽章。")
                FeaturedRankCard(progress: progress, isDark: viewModel.isEffectivelyDark)
                RankLadder(progress: progress)
                VStack(alignment: .leading, spacing: 16) {
                    ClaudeCardHeader(title: "成就徽章墙",
                                     subtitle: "已解锁 \(badges.filter(\.isUnlocked).count) / \(badges.count)")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(badges) { BadgeCard(badge: $0) }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

// MARK: - Featured dark card

/// `pricing-tier-card-featured` / `product-mockup-card-dark` — the dark surface IS the signal.
private struct FeaturedRankCard: View {
    let progress: RankProgress
    let isDark: Bool

    var body: some View {
        let rank = progress.currentRank
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                Text("当前段位 · Tier \(rank.rawValue)").claudeEyebrow(ClaudePalette.primary)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(rank.title)
                        .claudeDisplay(44)
                        .foregroundStyle(ClaudePalette.onDark)
                    Text(rank.englishSubtitle)
                        .font(ClaudeTypography.serif(18))
                        .tracking(-0.3)
                        .foregroundStyle(ClaudePalette.onDarkSoft)
                }
                Text("“\(rank.motto)”")
                    .font(ClaudeTypography.serif(16))
                    .tracking(-0.2)
                    .foregroundStyle(ClaudePalette.onDarkSoft)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(progress.nextRank.map { "距离「\($0.title)」" } ?? "已抵达最高段位")
                            .font(ClaudeTypography.caption)
                            .foregroundStyle(ClaudePalette.onDarkSoft)
                        Spacer()
                        Text(progress.nextRank == nil ? "100%" : String(format: "还需 %.1f 小时", progress.hoursToNextRank))
                            .font(ClaudeTypography.number(12, weight: .medium))
                            .foregroundStyle(ClaudePalette.onDark)
                    }
                    ClaudeProgressBar(value: progress.progressToNext, height: 6,
                                      track: isDark ? ClaudePalette.surfaceDarkSoft : ClaudePalette.surfaceDarkElevated)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: rank.symbolName)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(ClaudePalette.primary)
                    .padding(.bottom, 8)
                Text(String(format: "%.1f", progress.totalHours))
                    .font(.system(size: 48, weight: .light).monospacedDigit())
                    .foregroundStyle(ClaudePalette.onDark)
                Text("累计实验小时")
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.onDarkSoft)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClaudeRadius.lg, style: .continuous)
                .fill(isDark ? ClaudePalette.surfaceDarkElevated : ClaudePalette.surfaceDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeRadius.lg, style: .continuous)
                .strokeBorder(isDark ? ClaudePalette.hairline : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Ladder

private struct RankLadder: View {
    let progress: RankProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClaudeCardHeader(title: "段位阶梯", subtitle: "以累计实验小时晋级")
            HStack(spacing: 10) {
                ForEach(ResearchRank.allCases) { rank in
                    tier(rank)
                }
            }
        }
        .claudeCard(.card, padding: 24)
    }

    private func tier(_ rank: ResearchRank) -> some View {
        let current = rank == progress.currentRank
        let reached = rank <= progress.currentRank
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: rank.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(reached ? ClaudePalette.primary : ClaudePalette.mutedSoft)
                Spacer()
                if current {
                    ClaudeBadgePill(text: "当前", style: .coral)
                } else if reached {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.success)
                }
            }
            Text(rank.title)
                .font(ClaudeTypography.serif(18))
                .tracking(-0.3)
                .foregroundStyle(reached ? ClaudePalette.ink : ClaudePalette.muted)
            Text(rank.englishSubtitle)
                .font(ClaudeTypography.caption)
                .foregroundStyle(ClaudePalette.mutedSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(rank.minHours == 0 ? "起点" : String(format: "≥ %.0f 小时", rank.minHours))
                .font(ClaudeTypography.number(12, weight: .medium))
                .foregroundStyle(ClaudePalette.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                .fill(current ? ClaudePalette.canvas : ClaudePalette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                .strokeBorder(current ? ClaudePalette.primary : ClaudePalette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Badge

private struct BadgeCard: View {
    let badge: AchievementBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(badge.isUnlocked ? ClaudePalette.primary : ClaudePalette.surfaceCreamStrong)
                    Circle()
                        .strokeBorder(badge.isUnlocked ? ClaudePalette.accentAmber : Color.clear, lineWidth: 2)
                        .padding(3)
                    Image(systemName: badge.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(badge.isUnlocked ? ClaudePalette.onPrimary : ClaudePalette.mutedSoft)
                }
                .frame(width: 46, height: 46)
                Spacer()
                if badge.isUnlocked {
                    ClaudeBadgePill(text: "已解锁", systemImage: "checkmark", style: .amber)
                } else {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ClaudePalette.mutedSoft)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title)
                    .font(ClaudeTypography.titleMD)
                    .foregroundStyle(badge.isUnlocked ? ClaudePalette.ink : ClaudePalette.muted)
                Text(badge.subtitle)
                    .font(ClaudeTypography.serif(13))
                    .foregroundStyle(ClaudePalette.mutedSoft)
            }
            Text(badge.requirement)
                .font(ClaudeTypography.bodySM)
                .foregroundStyle(ClaudePalette.body)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
            if badge.isUnlocked {
                Text(badge.unlockedDate.map { "解锁于 \(LabForgeViewModel.chineseDate($0, weekday: false))" } ?? "已达成")
                    .font(ClaudeTypography.number(12))
                    .foregroundStyle(ClaudePalette.adaptive(0xA9583E, 0xE2957A))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ClaudeProgressBar(value: badge.progress, height: 5, fill: ClaudePalette.primary.opacity(0.75))
                    Text(badge.progressText)
                        .font(ClaudeTypography.number(12))
                        .foregroundStyle(ClaudePalette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .claudeCard(badge.isUnlocked ? .canvas : .card, padding: 20)
        .opacity(badge.isUnlocked ? 1 : 0.92)
    }
}
