import LabForgeCore
import SwiftUI

struct TodayDashboardView: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                HStack(alignment: .top, spacing: 20) {
                    HeroCheckInCard()
                        .frame(maxWidth: .infinity)
                    QuoteCard()
                        .frame(width: 300)
                }
                HStack(alignment: .top, spacing: 20) {
                    GoalAndLogCard()
                    TodaySessionsCard()
                        .frame(width: 300)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LabForgeViewModel.chineseDate(viewModel.now)).claudeEyebrow(ClaudePalette.primary)
            Text(viewModel.greeting)
                .claudeDisplay(40)
                .foregroundStyle(ClaudePalette.ink)
            Text(viewModel.statusLine)
                .font(ClaudeTypography.bodyMD)
                .foregroundStyle(ClaudePalette.muted)
        }
    }
}

// MARK: - Hero

private struct HeroCheckInCard: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        let streak = viewModel.streak
        let rank = viewModel.rankProgress

        ZStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    HStack(spacing: 8) {
                        StatusDot(active: viewModel.isActive)
                        Text(viewModel.isActive ? "实验进行中" : (viewModel.todaySessions.isEmpty ? "尚未打卡" : "今日已收工"))
                            .font(ClaudeTypography.caption)
                            .foregroundStyle(ClaudePalette.muted)
                    }
                    Spacer()
                    ClaudeBadgePill(text: rank.currentRank.title, systemImage: rank.currentRank.symbolName, style: .neutral)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(DurationFormatter.liveTimer(viewModel.isActive ? viewModel.activeElapsedSeconds : viewModel.todayTotalSeconds))
                        .font(ClaudeTypography.heroTimer)
                        .foregroundStyle(ClaudePalette.ink)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(viewModel.isActive
                         ? "本次实验 · 今日累计 \(DurationFormatter.humanReadable(viewModel.todayTotalSeconds))"
                         : "今日累计时长")
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.muted)
                }

                Button(action: viewModel.toggleCheckIn) {
                    Label(viewModel.isActive ? "结束实验收工" : "进入实验室打卡",
                          systemImage: viewModel.isActive ? "stop.circle" : "flame")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(ClaudePrimaryButtonStyle(fullWidth: true, height: 48))
                .keyboardShortcut(.return, modifiers: [.command])

                HStack(spacing: 24) {
                    metric(icon: "flame.fill", label: "当前连胜", value: "\(streak.currentStreak) 天",
                           tint: streak.isCheckedInToday ? ClaudePalette.primary : ClaudePalette.mutedSoft)
                    metric(icon: "trophy", label: "最长连胜", value: "\(streak.longestStreak) 天", tint: ClaudePalette.accentAmber)
                    metric(icon: "hourglass", label: "累计", value: String(format: "%.1f h", rank.totalHours), tint: ClaudePalette.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("每日目标")
                            .font(ClaudeTypography.caption)
                            .foregroundStyle(ClaudePalette.muted)
                        Spacer()
                        Text("\(DurationFormatter.menuBarDuration(viewModel.todayTotalSeconds)) / \(DurationFormatter.shortHours(viewModel.dailyTargetSeconds)) · \(Int((viewModel.dailyTargetProgress * 100).rounded()))%")
                            .font(ClaudeTypography.number(12, weight: .medium))
                            .foregroundStyle(ClaudePalette.body)
                    }
                    ClaudeProgressBar(value: viewModel.dailyTargetProgress)
                }
            }
            SparkCelebrationView(trigger: viewModel.celebration)
        }
        .claudeCard(.canvas, padding: 28, radius: ClaudeRadius.xl)
    }

    private func metric(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.mutedSoft)
                Text(value)
                    .font(ClaudeTypography.number(15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
            }
        }
    }
}

// MARK: - Quote

private struct QuoteCard: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        let quote = viewModel.currentQuote
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("每日一言").claudeEyebrow()
                Spacer()
                Button(action: viewModel.nextQuote) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ClaudeIconButtonStyle(size: 28))
                .help("换一句")
            }
            Text(quote.text)
                .font(ClaudeTypography.quote)
                .tracking(ClaudeTracking.quote)
                .lineSpacing(5)
                .foregroundStyle(ClaudePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .id(quote.id)
                .transition(.opacity)
            Spacer(minLength: 0)
            HStack {
                Text("—— \(quote.author)")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.muted)
                    .lineLimit(1)
                Spacer()
                ClaudeBadgePill(text: quote.tag, style: .amber)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .claudeCard(.card, padding: 24)
        .animation(.easeOut(duration: 0.25), value: quote.id)
    }
}

// MARK: - Goal & log

private struct GoalAndLogCard: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                ClaudeCardHeader(title: "今日实验目标", subtitle: "写下今天最想推进的一件事")
                TextField("例如：完成 CD8⁺ T 细胞流式染色", text: $vm.todayGoal)
                    .claudeTextField()
            }
            VStack(alignment: .leading, spacing: 10) {
                ClaudeCardHeader(title: "今日科研日志",
                                 subtitle: viewModel.canEditTodayLog ? "记录步骤、现象与下一步，自动保存" : "打卡后即可记录本次实验的日志")
                ClaudeTextEditor(text: $vm.todayLog,
                                 placeholder: viewModel.canEditTodayLog ? "今天观察到了什么？哪一步需要调整？" : "先点击「进入实验室打卡」",
                                 minHeight: 140,
                                 isDisabled: !viewModel.canEditTodayLog)
            }
        }
        .claudeCard(.canvas, padding: 24)
    }
}

// MARK: - Sessions

private struct TodaySessionsCard: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        let sessions = viewModel.todaySessions
        VStack(alignment: .leading, spacing: 14) {
            ClaudeCardHeader(title: "今日实验记录", subtitle: "\(sessions.count) 段 · \(DurationFormatter.humanReadable(viewModel.todayTotalSeconds))")
            if sessions.isEmpty {
                Text("还没有记录。打卡后，每一段实验都会出现在这里。")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.mutedSoft)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.reversed().enumerated()), id: \.element.id) { index, session in
                        if index > 0 { ClaudeDivider(color: ClaudePalette.hairlineSoft) }
                        row(session)
                    }
                }
            }
            Button {
                viewModel.isReportSheetPresented = true
            } label: {
                Label("生成今日科研战报", systemImage: "doc.richtext")
            }
            .buttonStyle(ClaudeSecondaryButtonStyle(fullWidth: true))
        }
        .claudeCard(.soft, padding: 24)
    }

    private func row(_ session: LabSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(session.isActive ? ClaudePalette.accentTeal : ClaudePalette.primary.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(LabForgeViewModel.timeString(session.startTime)) – \(session.endTime.map(LabForgeViewModel.timeString) ?? "进行中")")
                    .font(ClaudeTypography.number(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                if !session.goal.isEmpty {
                    Text(session.goal)
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(DurationFormatter.menuBarDuration(session.duration(asOf: viewModel.now)))
                .font(ClaudeTypography.number(13))
                .foregroundStyle(ClaudePalette.body)
        }
        .padding(.vertical, 9)
    }
}
