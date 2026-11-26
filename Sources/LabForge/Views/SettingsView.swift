import LabForgeCore
import SwiftUI

struct SettingsView: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClaudePageHeader(eyebrow: "Preferences", title: "设置",
                                 subtitle: "档案、外观、目标、提醒与数据，都在这里。")
                ResearcherProfileSection()
                AppearanceSection()
                HStack(alignment: .top, spacing: 20) {
                    DailyTargetSection()
                    ReminderSection()
                }
                MenuBarShortcutSoundSection()
                LaunchAtLoginSection()
                DataSection()
                AboutSection()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

// MARK: - Researcher profile

private struct ResearcherProfileSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                ResearcherMonogram(name: viewModel.effectiveResearcherName, size: 56)
                Text(viewModel.effectiveResearcherName)
                    .claudeDisplay(22)
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(2)
                if !viewModel.trimmedLabName.isEmpty {
                    Text(viewModel.trimmedLabName)
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.muted)
                        .lineLimit(2)
                }
                ClaudeBadgePill(text: viewModel.rankProgress.currentRank.title,
                                systemImage: viewModel.rankProgress.currentRank.symbolName)
            }
            .frame(width: 180, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                ClaudeCardHeader(title: "研究者档案", subtitle: "用于每日问候、侧边栏与战报署名，修改后自动保存。")
                QuickProfileEditorForm(researcherName: $vm.researcherName, labName: $vm.labName,
                                       researchFocus: $vm.researchFocus)
            }
        }
        .claudeCard(.canvas)
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClaudeCardHeader(title: "外观", subtitle: "默认 Claude 暖浅色；暖炭黑适合深夜实验。")
            HStack(spacing: 14) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceCard(mode: mode, isSelected: viewModel.appearanceMode == mode) {
                        viewModel.setAppearance(mode)
                    }
                }
            }
        }
        .claudeCard(.canvas)
    }
}

private struct AppearanceCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                preview
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                        .strokeBorder(ClaudePalette.hairline, lineWidth: 1))
                HStack {
                    Text(mode.displayName)
                        .font(ClaudeTypography.titleSM)
                        .foregroundStyle(ClaudePalette.ink)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? ClaudePalette.primary : ClaudePalette.mutedSoft)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: ClaudeRadius.lg, style: .continuous)
                .fill(isSelected ? ClaudePalette.surfaceCard : ClaudePalette.canvas))
            .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.lg, style: .continuous)
                .strokeBorder(isSelected ? ClaudePalette.primary : ClaudePalette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .light: MiniPalettePreview(palette: .light)
        case .dark: MiniPalettePreview(palette: .dark)
        case .system:
            HStack(spacing: 0) {
                MiniPalettePreview(palette: .light)
                MiniPalettePreview(palette: .dark)
            }
        }
    }
}

/// Tiny mock of the workbench in a fixed palette.
private struct MiniPalettePreview: View {
    let palette: FixedPalette

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Circle().fill(palette.primary).frame(width: 8, height: 8)
                RoundedRectangle(cornerRadius: 2).fill(palette.surfaceCard).frame(width: 26, height: 6)
                RoundedRectangle(cornerRadius: 2).fill(palette.hairline).frame(width: 20, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(palette.hairline).frame(width: 22, height: 4)
                Spacer()
            }
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(palette.surfaceSoft)
            VStack(alignment: .leading, spacing: 6) {
                Text("Aa")
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                RoundedRectangle(cornerRadius: 2).fill(palette.muted.opacity(0.5)).frame(width: 46, height: 4)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 1.5).fill(palette.heatmap(level)).frame(width: 8, height: 8)
                    }
                }
                Spacer()
                RoundedRectangle(cornerRadius: 3).fill(palette.primary).frame(width: 44, height: 12)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(palette.canvas)
        }
    }
}

// MARK: - Target

private struct DailyTargetSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 16) {
            ClaudeCardHeader(title: "目标时长", subtitle: "进度条、洞察与战报按此计算")
            target(label: "每日目标时长", value: viewModel.dailyTargetHours, unit: "小时 / 天",
                   binding: $vm.dailyTargetHours, range: LabSettings.dailyTargetRange, step: 0.5)
            ClaudeDivider(color: ClaudePalette.hairline)
            target(label: "每周目标时长", value: viewModel.weeklyTargetHours, unit: "小时 / 周",
                   binding: $vm.weeklyTargetHours, range: LabSettings.weeklyTargetRange, step: 1.0)
        }
        .claudeCard(.card)
    }

    private func target(label: String, value: Double, unit: String, binding: Binding<Double>,
                        range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(ClaudeTypography.caption)
                .foregroundStyle(ClaudePalette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: step < 1 ? "%.1f" : "%.0f", value))
                    .font(.system(size: 34, weight: .light).monospacedDigit())
                    .foregroundStyle(ClaudePalette.ink)
                Text(unit)
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.muted)
                Spacer()
                Stepper("", value: binding, in: range, step: step)
                    .labelsHidden()
            }
            Slider(value: binding, in: range, step: step)
                .tint(ClaudePalette.primary)
            HStack {
                Text(String(format: step < 1 ? "%.1fh" : "%.0fh", range.lowerBound))
                    .font(ClaudeTypography.number(11)).foregroundStyle(ClaudePalette.mutedSoft)
                Spacer()
                Text(String(format: step < 1 ? "%.1fh" : "%.0fh", range.upperBound))
                    .font(ClaudeTypography.number(11)).foregroundStyle(ClaudePalette.mutedSoft)
            }
        }
    }
}

// MARK: - Menu bar, shortcut & sound

private struct MenuBarShortcutSoundSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    private static let sleepThresholds: [(minutes: Int, title: String)] = [(0, "关闭"), (15, "15 分钟"), (30, "30 分钟"), (60, "60 分钟")]

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 18) {
            ClaudeCardHeader(title: "菜单栏、快捷键与提示音", subtitle: "安静地待在菜单栏，需要时一键打卡。")

            row(icon: "menubar.rectangle", title: "菜单栏显示", detail: "选择菜单栏图标旁显示的信息量") {
                Picker("", selection: $vm.menuBarStyle) {
                    Text("完整").tag(MenuBarDisplayStyle.full)
                    Text("极简").tag(MenuBarDisplayStyle.compact)
                    Text("纯图标").tag(MenuBarDisplayStyle.iconOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            ClaudeDivider(color: ClaudePalette.hairlineSoft)

            row(icon: "dock.rectangle", title: "隐藏程序坞（Dock）图标",
                detail: "仅在顶部菜单栏常驻，不在底部程序坞显示；随时可点菜单栏打开主仪表盘") {
                Toggle("", isOn: Binding(get: { viewModel.hideDockIcon }, set: { viewModel.setHideDockIcon($0) }))
                    .toggleStyle(.switch)
                    .tint(ClaudePalette.primary)
                    .labelsHidden()
            }
            ClaudeDivider(color: ClaudePalette.hairlineSoft)

            row(icon: "command", title: "全局快捷键 \(GlobalHotKeyService.shortcutLabel)",
                detail: viewModel.globalShortcutStatusText,
                detailColor: viewModel.globalShortcutEnabled && !viewModel.isGlobalShortcutRegistered ? ClaudePalette.error : ClaudePalette.muted) {
                HStack(spacing: 10) {
                    ClaudeBadgePill(text: "无需辅助功能权限", style: .outline)
                    Toggle("", isOn: $vm.globalShortcutEnabled)
                        .toggleStyle(.switch)
                        .tint(ClaudePalette.primary)
                        .labelsHidden()
                }
            }
            ClaudeDivider(color: ClaudePalette.hairlineSoft)

            row(icon: "speaker.wave.1", title: "打卡 / 收工提示音", detail: "柔和的系统音效，音量约 45%") {
                HStack(spacing: 10) {
                    Picker("", selection: $vm.soundName) {
                        ForEach(LabSettings.availableSoundNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .disabled(!viewModel.soundEnabled)
                    Button {
                        viewModel.previewSound()
                    } label: {
                        Label("试听", systemImage: "play.fill")
                    }
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                    Toggle("", isOn: $vm.soundEnabled)
                        .toggleStyle(.switch)
                        .tint(ClaudePalette.primary)
                        .labelsHidden()
                }
            }
            ClaudeDivider(color: ClaudePalette.hairlineSoft)

            row(icon: "moon.zzz", title: "休眠恢复提示",
                detail: "计时中电脑休眠超过设定时长，唤醒后询问是否保留这段时间") {
                Picker("", selection: $vm.sleepPromptThresholdMinutes) {
                    ForEach(Self.sleepThresholds, id: \.minutes) { Text($0.title).tag($0.minutes) }
                    if !Self.sleepThresholds.contains(where: { $0.minutes == viewModel.sleepPromptThresholdMinutes }) {
                        Text("\(viewModel.sleepPromptThresholdMinutes) 分钟").tag(viewModel.sleepPromptThresholdMinutes)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
        }
        .claudeCard(.canvas)
    }

    private func row<Control: View>(icon: String, title: String, detail: String,
                                    detailColor: Color = ClaudePalette.muted,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClaudePalette.primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(ClaudePalette.surfaceSoft))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClaudeTypography.titleSM)
                    .foregroundStyle(ClaudePalette.ink)
                Text(detail)
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

// MARK: - Reminder

private struct ReminderSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        VStack(alignment: .leading, spacing: 16) {
            ClaudeCardHeader(title: "每日打卡提醒", subtitle: "系统通知，温和地叫你进实验室") {
                Toggle("", isOn: Binding(get: { viewModel.reminderEnabled }, set: { viewModel.setReminderEnabled($0) }))
                    .toggleStyle(.switch)
                    .tint(ClaudePalette.primary)
                    .labelsHidden()
                    .disabled(!viewModel.isNotificationAvailable)
            }
            HStack {
                Text("提醒时间")
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.muted)
                Spacer()
                DatePicker("", selection: $vm.reminderTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 90)
            }
            StatusBanner(text: viewModel.notificationStatusText, tone: tone)
        }
        .claudeCard(.card)
    }

    private var tone: StatusBanner.Tone {
        switch viewModel.notificationStatus {
        case .authorized(scheduled: true) where viewModel.reminderEnabled: return .ok
        case .unavailable, .denied, .error: return .warn
        default: return .neutral
        }
    }
}

// MARK: - Launch at login

private struct LaunchAtLoginSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClaudeCardHeader(title: "开机自启动", subtitle: "登录 macOS 后自动出现在菜单栏") {
                Toggle("", isOn: Binding(get: { viewModel.launchAtLoginEnabled }, set: { viewModel.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .tint(ClaudePalette.primary)
                    .labelsHidden()
                    .disabled(!viewModel.isLaunchAtLoginAvailable)
            }
            HStack(alignment: .center, spacing: 12) {
                StatusBanner(text: viewModel.launchStatusText, tone: tone)
                if viewModel.launchStatus == .requiresApproval || isErrorStatus {
                    Button("打开登录项设置", action: viewModel.openLoginItemsSettings)
                        .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                }
            }
        }
        .claudeCard(.canvas)
    }

    private var isErrorStatus: Bool {
        if case .error = viewModel.launchStatus { return true }
        return false
    }

    private var tone: StatusBanner.Tone {
        switch viewModel.launchStatus {
        case .enabled: return .ok
        case .requiresApproval, .unavailable, .notFound, .error: return .warn
        case .disabled: return .neutral
        }
    }
}

// MARK: - Data

private struct DataSection: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClaudeCardHeader(title: "数据备份与恢复", subtitle: "所有记录只保存在本机，JSON 格式，原子写入；CSV 便于在 Excel / Numbers 中分析。")
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(ClaudePalette.primary)
                Text(viewModel.dataFilePath)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(ClaudePalette.body)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(viewModel.data.sessions.count) 条记录")
                    .font(ClaudeTypography.number(12))
                    .foregroundStyle(ClaudePalette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous).fill(ClaudePalette.surfaceSoft))
            .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous).strokeBorder(ClaudePalette.hairline, lineWidth: 1))

            ClaudeFlowLayout(spacing: 10, lineSpacing: 10) {
                Button { viewModel.revealDataFileInFinder() } label: { Label("在 Finder 中显示", systemImage: "folder") }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
                Button { viewModel.exportJSONBackup() } label: { Label("导出 JSON 备份", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
                Button { viewModel.exportCSVBackup() } label: { Label("导出 CSV 表格", systemImage: "tablecells") }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
                Button { viewModel.importJSONBackup() } label: { Label("导入恢复 JSON（支持合并或覆盖）", systemImage: "square.and.arrow.down") }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
            }
        }
        .claudeCard(.canvas)
    }
}

// MARK: - About

private struct AboutSection: View {
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            LabForgeMarkView(size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("LabForge").claudeDisplay(24).foregroundStyle(ClaudePalette.ink)
                    ClaudeBadgePill(text: "v\(version)", style: .neutral)
                }
                Text("把每一次进出实验室，铸成看得见的积累。原生 SwiftUI + AppKit，数据完全本地。")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.muted)
                Text("com.labforge.app · macOS 14+")
                    .font(ClaudeTypography.number(11))
                    .foregroundStyle(ClaudePalette.mutedSoft)
            }
            Spacer()
        }
        .claudeCard(.card)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - Banner

private struct StatusBanner: View {
    enum Tone { case ok, warn, neutral }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(ClaudeTypography.bodySM)
                .foregroundStyle(ClaudePalette.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous).fill(ClaudePalette.canvas))
        .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous).strokeBorder(ClaudePalette.hairline, lineWidth: 1))
    }

    private var icon: String {
        switch tone {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .ok: return ClaudePalette.success
        case .warn: return ClaudePalette.warning
        case .neutral: return ClaudePalette.muted
        }
    }
}
