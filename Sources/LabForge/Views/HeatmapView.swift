import LabForgeCore
import SwiftUI

struct HeatmapView: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @State private var hoveredDayID: String?
    @State private var lockedDayID: String?

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let days = viewModel.heatmapDays
        let grid = HeatmapBuilder.buildWeeksGrid(days: days, calendar: viewModel.calendar)
        let streak = viewModel.streak
        let yearSeconds = days.reduce(0) { $0 + $1.totalSeconds }
        let activeDays = days.filter { $0.totalSeconds > 0 }.count
        let locked = lockedDayID.flatMap { id in days.first { $0.id == id } }
        let focused = locked ?? days.first { $0.id == hoveredDayID } ?? days.last

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClaudePageHeader(eyebrow: "Research Footprint", title: "365 天科研足迹",
                                 subtitle: "每一格都是一天，颜色越深，铸下的时间越多。")

                HStack(spacing: 14) {
                    ClaudeStatTile(label: "年度总时长", value: String(format: "%.1f h", yearSeconds / 3600),
                                   caption: "近 365 天", systemImage: "hourglass")
                    ClaudeStatTile(label: "累计活跃天数", value: "\(activeDays) 天",
                                   caption: "全部 \(streak.totalActiveDays) 天", systemImage: "calendar")
                    ClaudeStatTile(label: "当前连胜", value: "\(streak.currentStreak) 天",
                                   caption: streak.isCheckedInToday ? "今日已打卡" : "今日待打卡", systemImage: "flame")
                    ClaudeStatTile(label: "最长连胜", value: "\(streak.longestStreak) 天",
                                   caption: "历史最佳", systemImage: "trophy")
                }

                VStack(alignment: .leading, spacing: 16) {
                    ClaudeCardHeader(title: "年度热力图", subtitle: "悬停预览，点击锁定某一天；再次点击解除锁定") {
                        legend
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        heatmapGrid(grid)
                            .padding(.vertical, 2)
                    }
                    .defaultScrollAnchor(.trailing)
                    if let focused { detailBar(focused, isLocked: locked != nil) }
                }
                .claudeCard(.canvas, padding: 24)

                observationsSection

                WeeklyRhythmCard()

                recentBars(Array(days.suffix(14)))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    // MARK: Grid

    private func heatmapGrid(_ grid: [[HeatmapDay?]]) -> some View {
        let labels = monthLabels(grid)
        return VStack(alignment: .leading, spacing: 6) {
            // Month axis
            HStack(spacing: gap) {
                Color.clear.frame(width: 22, height: 12)
                ForEach(grid.indices, id: \.self) { column in
                    ZStack(alignment: .leading) {
                        Color.clear.frame(width: cell, height: 12)
                        if let label = labels[column] {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ClaudePalette.mutedSoft)
                                .fixedSize()
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: gap) {
                // Weekday labels
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 1 ? weekdayName(row: row) : "")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(ClaudePalette.mutedSoft)
                            .frame(width: 22, height: cell, alignment: .leading)
                    }
                }
                ForEach(grid.indices, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            cellView(grid[column][row])
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: HeatmapDay?) -> some View {
        if let day {
            let isHovered = hoveredDayID == day.id
            let isLocked = lockedDayID == day.id
            let isToday = day.id == viewModel.todayKey
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(ClaudePalette.heatmap(level: day.intensityLevel))
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(isLocked ? ClaudePalette.primaryActive
                                      : (isHovered ? ClaudePalette.ink : (isToday ? ClaudePalette.primaryActive : Color.clear)),
                                      lineWidth: isLocked || isHovered ? 1.5 : 1)
                )
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredDayID = day.id } else if hoveredDayID == day.id { hoveredDayID = nil }
                }
                .onTapGesture {
                    lockedDayID = lockedDayID == day.id ? nil : day.id
                }
                .accessibilityAddTraits(.isButton)
                .help("\(LabForgeViewModel.chineseDate(day.date, weekday: false)) · \(DurationFormatter.humanReadable(day.totalSeconds))")
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func monthLabels(_ grid: [[HeatmapDay?]]) -> [Int: String] {
        var result: [Int: String] = [:]
        var lastMonth: Int?
        for (index, column) in grid.enumerated() {
            guard let first = column.compactMap({ $0 }).first else { continue }
            let month = viewModel.calendar.component(.month, from: first.date)
            if month != lastMonth {
                // Skip a label squeezed into the very first partial column.
                if lastMonth != nil || column.compactMap({ $0 }).count >= 4 {
                    result[index] = "\(month)月"
                }
                lastMonth = month
            }
        }
        return result
    }

    private func weekdayName(row: Int) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[(viewModel.calendar.firstWeekday - 1 + row) % 7]
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("少").font(ClaudeTypography.caption).foregroundStyle(ClaudePalette.mutedSoft)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(ClaudePalette.heatmap(level: level))
                    .frame(width: 11, height: 11)
            }
            Text("多").font(ClaudeTypography.caption).foregroundStyle(ClaudePalette.mutedSoft)
        }
    }

    private func detailBar(_ day: HeatmapDay, isLocked: Bool) -> some View {
        HStack(spacing: 14) {
            if isLocked {
                Button {
                    lockedDayID = nil
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ClaudePalette.primary)
                }
                .buttonStyle(.plain)
                .help("已锁定，点击解除")
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ClaudePalette.heatmap(level: day.intensityLevel))
                .frame(width: 14, height: 14)
            Text(LabForgeViewModel.chineseDate(day.date))
                .font(ClaudeTypography.titleSM)
                .foregroundStyle(ClaudePalette.ink)
            Text(day.totalSeconds > 0 ? DurationFormatter.humanReadable(day.totalSeconds) : "无打卡")
                .font(ClaudeTypography.number(13, weight: .medium))
                .foregroundStyle(ClaudePalette.body)
            Text("\(day.sessionCount) 段实验")
                .font(ClaudeTypography.number(13))
                .foregroundStyle(ClaudePalette.muted)
            Text(day.goalSummary.isEmpty ? "未记录目标" : day.goalSummary)
                .font(ClaudeTypography.bodySM)
                .foregroundStyle(day.goalSummary.isEmpty ? ClaudePalette.mutedSoft : ClaudePalette.body)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                viewModel.requestBackfill(on: day.date)
            } label: {
                Label("补卡", systemImage: "plus")
            }
            .buttonStyle(ClaudeSecondaryButtonStyle(height: 28, compact: true))
            .help("为 \(LabForgeViewModel.chineseDate(day.date, weekday: false)) 手动补卡")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous).fill(ClaudePalette.surfaceSoft))
        .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
            .strokeBorder(isLocked ? ClaudePalette.hairline : Color.clear, lineWidth: 1))
    }

    // MARK: Calm insights

    private var observationsSection: some View {
        let observations = viewModel.calmObservations
        return VStack(alignment: .leading, spacing: 14) {
            ClaudeCardHeader(title: "冷静科研洞察", subtitle: "只陈述事实，不做评判")
            HStack(alignment: .top, spacing: 14) {
                ForEach(observations) { observation in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: observation.symbolName)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(ClaudePalette.accentForeground)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(ClaudePalette.canvas))
                            .overlay(Circle().strokeBorder(ClaudePalette.hairline, lineWidth: 1))
                        Text(observation.title)
                            .font(ClaudeTypography.serif(17))
                            .tracking(-0.3)
                            .foregroundStyle(ClaudePalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(observation.detail)
                            .font(ClaudeTypography.bodySM)
                            .lineSpacing(2)
                            .foregroundStyle(ClaudePalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .claudeCard(.card, padding: 20)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Recent bars

    private func recentBars(_ days: [HeatmapDay]) -> some View {
        let target = viewModel.dailyTargetSeconds
        let maxSeconds = max(days.map(\.totalSeconds).max() ?? 0, target, 3600)
        let chartHeight: CGFloat = 140

        return VStack(alignment: .leading, spacing: 18) {
            ClaudeCardHeader(title: "近 14 天", subtitle: "虚线为每日目标 \(DurationFormatter.shortHours(target))")
            ZStack(alignment: .bottomLeading) {
                // Target line
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .stroke(ClaudePalette.mutedSoft.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1)
                    Color.clear.frame(height: chartHeight * CGFloat(target / maxSeconds))
                }
                .frame(height: chartHeight)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days) { day in
                        let isToday = day.id == viewModel.todayKey
                        VStack(spacing: 6) {
                            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                                .fill(day.totalSeconds > 0 ? ClaudePalette.heatmap(level: max(day.intensityLevel, 1)) : ClaudePalette.surfaceCard)
                                .frame(height: max(3, chartHeight * CGFloat(day.totalSeconds / maxSeconds)))
                                .help("\(LabForgeViewModel.shortDate(day.date)) · \(DurationFormatter.humanReadable(day.totalSeconds))")
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .overlay(alignment: .bottom) {
                            if isToday {
                                Rectangle().fill(ClaudePalette.ink).frame(height: 1.5).offset(y: 1)
                            }
                        }
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)
            }
            HStack(spacing: 8) {
                ForEach(days) { day in
                    Text(day.id == viewModel.todayKey ? "今" : "\(viewModel.calendar.component(.day, from: day.date))")
                        .font(ClaudeTypography.number(10.5, weight: day.id == viewModel.todayKey ? .semibold : .regular))
                        .foregroundStyle(day.id == viewModel.todayKey ? ClaudePalette.ink : ClaudePalette.mutedSoft)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .claudeCard(.card, padding: 24)
    }
}

// MARK: - Weekly rhythm & category distribution

private struct WeeklyRhythmCard: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        let week = viewModel.weeklyProgress
        let breakdown = viewModel.categoryBreakdown
        VStack(alignment: .leading, spacing: 18) {
            ClaudeCardHeader(title: "本周节奏与研究分布", subtitle: "周一为一周起点 · 分布统计近 28 天")
            HStack(alignment: .top, spacing: 28) {
                weekly(week)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle().fill(ClaudePalette.hairline).frame(width: 1)
                distribution(breakdown)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .claudeCard(.canvas, padding: 24)
    }

    private func weekly(_ week: InsightsEngine.WeeklyProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本周已铸").claudeEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", week.totalSeconds / 3600))
                    .font(.system(size: 36, weight: .light).monospacedDigit())
                    .foregroundStyle(ClaudePalette.ink)
                Text(String(format: "h / 周目标 %.1fh", week.targetSeconds / 3600))
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ClaudeProgressBar(value: week.progress)
            HStack(spacing: 18) {
                fact(label: "活跃天数", value: "\(week.activeDays) / 7 天")
                fact(label: "完成度", value: "\(Int((week.progress * 100).rounded()))%")
                fact(label: "还差", value: week.remainingSeconds > 0 ? DurationFormatter.humanReadable(week.remainingSeconds) : "已达成")
            }
            Text(comparison(week))
                .font(ClaudeTypography.bodySM)
                .foregroundStyle(ClaudePalette.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func comparison(_ week: InsightsEngine.WeeklyProgress) -> String {
        let previous = week.previousWeekSeconds
        guard previous > 0 else { return "上周暂无记录。" }
        let base = "上周全周共 \(DurationFormatter.humanReadable(previous))"
        let diff = week.totalSeconds - previous
        if diff >= 60 { return "\(base)，本周已多出 \(DurationFormatter.humanReadable(diff))。" }
        if diff > -60 { return "\(base)，本周已与之持平。" }
        return "\(base)，本周距上周总量还差 \(DurationFormatter.humanReadable(-diff))。"
    }

    private func fact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ClaudeTypography.caption)
                .foregroundStyle(ClaudePalette.mutedSoft)
            Text(value)
                .font(ClaudeTypography.number(14, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
                .lineLimit(1)
        }
    }

    private func distribution(_ breakdown: [InsightsEngine.CategoryBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 28 天研究分布").claudeEyebrow()
            if breakdown.isEmpty {
                Text("近 28 天还没有记录。打卡时选择分类，这里会显示时间分配。")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.mutedSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(breakdown) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Image(systemName: item.category.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ClaudePalette.category(item.category))
                                .frame(width: 16)
                            Text(item.category.title)
                                .font(ClaudeTypography.caption)
                                .foregroundStyle(ClaudePalette.body)
                            Spacer(minLength: 8)
                            Text("\(DurationFormatter.humanReadable(item.totalSeconds)) · \(Int((item.percentage * 100).rounded()))%")
                                .font(ClaudeTypography.number(12))
                                .foregroundStyle(ClaudePalette.muted)
                                .lineLimit(1)
                        }
                        ClaudeProgressBar(value: item.percentage, height: 6, fill: ClaudePalette.category(item.category))
                    }
                }
            }
        }
    }
}
