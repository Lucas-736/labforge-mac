import AppKit
import LabForgeCore
import SwiftUI

/// Menu bar extra window (~340pt).
struct MenuBarPopoverView: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var vm = viewModel
        let rank = viewModel.rankProgress
        let streak = viewModel.streak

        VStack(alignment: .leading, spacing: 0) {
            // Header: brand + rank + streak
            HStack(spacing: 8) {
                LabForgeWordmark(markSize: 18, fontSize: 17)
                Spacer(minLength: 4)
                ClaudeBadgePill(text: rank.currentRank.title, systemImage: rank.currentRank.symbolName)
                StreakFlameBadge(streak: streak.currentStreak, lit: streak.isCheckedInToday)
            }
            .padding(.bottom, 18)

            // Timer block
            ZStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        StatusDot(active: viewModel.isActive)
                        Text(viewModel.isActive ? "实验进行中" : "今日累计")
                            .font(ClaudeTypography.caption)
                            .foregroundStyle(ClaudePalette.muted)
                    }
                    Text(DurationFormatter.liveTimer(viewModel.isActive ? viewModel.activeElapsedSeconds : viewModel.todayTotalSeconds))
                        .font(.system(size: 40, weight: .light).monospacedDigit())
                        .foregroundStyle(ClaudePalette.ink)
                        .contentTransition(.numericText())
                    Text(viewModel.statusLine)
                        .font(ClaudeTypography.serif(14))
                        .tracking(-0.2)
                        .foregroundStyle(ClaudePalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SparkCelebrationView(trigger: viewModel.celebration)
            }
            .claudeCard(.card, padding: 18)
            .padding(.bottom, 12)

            CategorySelectorStrip(selection: $vm.activeCategory, compact: true)
                .padding(.bottom, 12)

            Button(action: viewModel.toggleCheckIn) {
                Label(viewModel.isActive ? "结束实验收工" : "进入实验室打卡",
                      systemImage: viewModel.isActive ? "stop.circle" : "flame")
            }
            .buttonStyle(ClaudePrimaryButtonStyle(fullWidth: true, height: 42))
            .padding(.bottom, 16)

            if let toast = viewModel.toast, toast.kind == .error {
                Text(toast.text)
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("今日实验目标")
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.muted)
                TextField("例如：完成 qPCR 引物验证", text: $vm.todayGoal)
                    .claudeTextField(height: 36)
                let current = viewModel.todayGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                let suggestions = Array(viewModel.recentGoals.filter { $0 != current }.prefix(3))
                if !suggestions.isEmpty && (current.isEmpty || !viewModel.recentGoals.contains(current)) {
                    ClaudeFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(suggestions, id: \.self) { goal in
                            SuggestionPill(text: goal, maxWidth: 140) { vm.todayGoal = goal }
                        }
                    }
                }
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("每日目标进度")
                        .font(ClaudeTypography.caption)
                        .foregroundStyle(ClaudePalette.muted)
                    Spacer()
                    Text("\(DurationFormatter.menuBarDuration(viewModel.todayTotalSeconds)) / \(DurationFormatter.shortHours(viewModel.dailyTargetSeconds))")
                        .font(ClaudeTypography.number(12, weight: .medium))
                        .foregroundStyle(ClaudePalette.body)
                }
                ClaudeProgressBar(value: viewModel.dailyTargetProgress, height: 6)
            }
            .padding(.bottom, 18)

            ClaudeDivider().padding(.bottom, 12)

            HStack {
                Button {
                    openWindow(id: LabForgeApp.dashboardID)
                    NSApp.activate()
                } label: {
                    Label("打开主仪表盘", systemImage: "macwindow")
                }
                .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))

                Button {
                    viewModel.toggleAppearance()
                } label: {
                    Image(systemName: viewModel.isEffectivelyDark ? "sun.max" : "moon")
                }
                .buttonStyle(ClaudeIconButtonStyle(size: 30))
                .help("切换浅色 / 暖炭黑")

                Spacer()

                if viewModel.isGlobalShortcutRegistered {
                    Text(GlobalHotKeyService.shortcutLabel)
                        .font(ClaudeTypography.number(11))
                        .foregroundStyle(ClaudePalette.mutedSoft)
                        .help("全局快捷键：在任意应用中打卡 / 收工")
                        .padding(.trailing, 6)
                }

                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(ClaudeTextButtonStyle())
                    .keyboardShortcut("q")
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(ClaudePalette.canvas)
    }
}
