import LabForgeCore
import SwiftUI

struct TodayDashboardView: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @State private var isEditingProfile = false

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let prompt = viewModel.pendingSleepRecovery {
                    SleepRecoveryBanner(prompt: prompt)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
        .animation(.easeOut(duration: 0.2), value: viewModel.pendingSleepRecovery)
        .sheet(isPresented: $isEditingProfile) {
            QuickProfileEditorSheet(researcherName: $vm.researcherName, labName: $vm.labName,
                                    researchFocus: $vm.researchFocus)
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LabForgeViewModel.chineseDate(viewModel.now)).claudeEyebrow(ClaudePalette.primary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(viewModel.greeting)
                    .claudeDisplay(40)
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Button {
                    isEditingProfile = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(ClaudeIconButtonStyle(size: 28))
                .help("编辑资料")
                .accessibilityLabel("编辑资料")
            }
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
        @Bindable var vm = viewModel
        let streak = viewModel.streak
        let rank = viewModel.rankProgress
        let week = viewModel.weeklyProgress

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

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.isActive ? "本次实验分类" : "下一段实验分类")
                        .font(ClaudeTypography.caption)
                        .foregroundStyle(ClaudePalette.mutedSoft)
                    ViewThatFits(in: .horizontal) {
                        CategorySelectorStrip(selection: $vm.activeCategory)
                        CategorySelectorStrip(selection: $vm.activeCategory, compact: true)
                    }
                }

                VStack(spacing: 8) {
                    Button(action: viewModel.toggleCheckIn) {
                        Label(viewModel.isActive ? "结束实验收工" : "进入实验室打卡",
                              systemImage: viewModel.isActive ? "stop.circle" : "flame")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(ClaudePrimaryButtonStyle(fullWidth: true, height: 48))
                    .keyboardShortcut(.return, modifiers: [.command])

                    Text(shortcutHint)
                        .font(ClaudeTypography.number(11))
                        .foregroundStyle(ClaudePalette.mutedSoft)
                        .frame(maxWidth: .infinity)
                }

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
                    HStack {
                        Text("本周目标")
                            .font(ClaudeTypography.caption)
                            .foregroundStyle(ClaudePalette.muted)
                        Spacer()
                        Text(String(format: "本周 %.1fh / %.1fh · %d%%", week.totalSeconds / 3600, week.targetSeconds / 3600,
                                    Int((week.progress * 100).rounded())))
                            .font(ClaudeTypography.number(12, weight: .medium))
                            .foregroundStyle(ClaudePalette.body)
                    }
                    .padding(.top, 4)
                    ClaudeProgressBar(value: week.progress, height: 5, fill: ClaudePalette.primary.opacity(0.75))
                }
            }
            SparkCelebrationView(trigger: viewModel.celebration)
        }
        .claudeCard(.canvas, padding: 28, radius: ClaudeRadius.xl)
    }

    private var shortcutHint: String {
        let action = viewModel.isActive ? "收工" : "打卡"
        if viewModel.isGlobalShortcutRegistered {
            return "⌘↩ \(action) · 任意应用中 \(GlobalHotKeyService.shortcutLabel)"
        }
        return "⌘↩ 快速\(action)"
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
                let current = viewModel.todayGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                let suggestions = Array(viewModel.recentGoals.filter { $0 != current }.prefix(4))
                if !suggestions.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("最近")
                            .font(ClaudeTypography.caption)
                            .foregroundStyle(ClaudePalette.mutedSoft)
                            .padding(.top, 4)
                        ClaudeFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(suggestions, id: \.self) { goal in
                                SuggestionPill(text: goal) { vm.todayGoal = goal }
                            }
                        }
                    }
                }
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
                .fill(session.isActive ? ClaudePalette.accentTeal : ClaudePalette.category(session.category).opacity(0.8))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(LabForgeViewModel.timeString(session.startTime)) – \(session.endTime.map(LabForgeViewModel.timeString) ?? "进行中")")
                        .font(ClaudeTypography.number(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    CategoryTagPill(category: session.category, compact: true)
                }
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

// MARK: - Sleep recovery

/// Calm warm banner shown after the Mac slept through part of a running session.
private struct SleepRecoveryBanner: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    let prompt: SleepRecoveryPrompt

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(ClaudePalette.accentForeground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ClaudePalette.canvas))
                .overlay(Circle().strokeBorder(ClaudePalette.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("电脑刚刚休眠过")
                    .font(ClaudeTypography.serif(18))
                    .tracking(-0.3)
                    .foregroundStyle(ClaudePalette.ink)
                Text("检测到电脑休眠了 \(awayText)（自 \(LabForgeViewModel.timeString(prompt.sleepStart)) 起），要如何处理这段计时？")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("保留全部计时", action: viewModel.keepSleepTime)
                        .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                    Button("按休眠时刻收工", action: viewModel.endSessionAtSleepStart)
                        .buttonStyle(ClaudeSecondaryButtonStyle(height: 30, compact: true))
                    Button("忽略", action: viewModel.dismissSleepRecovery)
                        .buttonStyle(ClaudeTextButtonStyle())
                        .padding(.leading, 6)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .claudeCard(.soft, padding: 18)
    }

    private var awayText: String {
        let minutes = max(0, Int(prompt.awaySeconds / 60))
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) 小时 \(m) 分钟" : "\(m) 分钟"
    }
}
