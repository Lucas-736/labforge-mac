import LabForgeCore
import SwiftUI

struct HeatmapView: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @State private var hoveredDayID: String?

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let days = viewModel.heatmapDays
        let grid = HeatmapBuilder.buildWeeksGrid(days: days, calendar: viewModel.calendar)
        let streak = viewModel.streak
        let yearSeconds = days.reduce(0) { $0 + $1.totalSeconds }
        let activeDays = days.filter { $0.totalSeconds > 0 }.count
        let focused = days.first { $0.id == hoveredDayID } ?? days.last

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
                    ClaudeCardHeader(title: "年度热力图", subtitle: "悬停查看某一天的详情") {
                        legend
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        heatmapGrid(grid)
                            .padding(.vertical, 2)
                    }
                    .defaultScrollAnchor(.trailing)
                    if let focused { detailBar(focused) }
                }
                .claudeCard(.canvas, padding: 24)

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
            let isToday = day.id == viewModel.todayKey
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(ClaudePalette.heatmap(level: day.intensityLevel))
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(isHovered ? ClaudePalette.ink : (isToday ? ClaudePalette.primaryActive : Color.clear),
                                      lineWidth: isHovered ? 1.5 : 1)
                )
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredDayID = day.id } else if hoveredDayID == day.id { hoveredDayID = nil }
                }
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

    private func detailBar(_ day: HeatmapDay) -> some View {
        HStack(spacing: 16) {
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
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous).fill(ClaudePalette.surfaceSoft))
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
