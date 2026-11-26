import LabForgeCore
import SwiftUI

struct SettingsView: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClaudePageHeader(eyebrow: "Preferences", title: "设置",
                                 subtitle: "外观、目标、提醒与数据，都在这里。")
                AppearanceSection()
                HStack(alignment: .top, spacing: 20) {
                    DailyTargetSection()
                    ReminderSection()
                }
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
            ClaudeCardHeader(title: "每日目标时长", subtitle: "进度条与战报按此计算")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", viewModel.dailyTargetHours))
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .foregroundStyle(ClaudePalette.ink)
                Text("小时 / 天")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.muted)
                Spacer()
                Stepper("", value: $vm.dailyTargetHours, in: LabSettings.dailyTargetRange, step: 0.5)
                    .labelsHidden()
            }
            Slider(value: $vm.dailyTargetHours, in: LabSettings.dailyTargetRange, step: 0.5)
                .tint(ClaudePalette.primary)
            HStack {
                Text("1.0h").font(ClaudeTypography.number(11)).foregroundStyle(ClaudePalette.mutedSoft)
                Spacer()
                Text("16.0h").font(ClaudeTypography.number(11)).foregroundStyle(ClaudePalette.mutedSoft)
            }
        }
        .claudeCard(.card)
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
            ClaudeCardHeader(title: "数据备份与恢复", subtitle: "所有记录只保存在本机，JSON 格式，原子写入。")
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

            HStack(spacing: 10) {
                Button { viewModel.revealDataFileInFinder() } label: { Label("在 Finder 中显示", systemImage: "folder") }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
                Button { viewModel.exportJSONBackup() } label: { Label("导出 JSON 备份", systemImage: "square.and.arrow.up") }
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
                    Text("LabForge 研铸").claudeDisplay(24).foregroundStyle(ClaudePalette.ink)
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
