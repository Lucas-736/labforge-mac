import LabForgeCore
import SwiftUI

/// Main dashboard window: warm sidebar + canvas content area + toast overlay.
struct MainWorkbenchView: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(ClaudePalette.hairline).frame(width: 1)
                }

            ZStack(alignment: .top) {
                ClaudePalette.canvas
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ToastOverlay(toast: viewModel.toast, dismiss: viewModel.dismissToast)
                    .padding(.top, 16)
            }
        }
        .background(ClaudePalette.canvas)
        .sheet(isPresented: $vm.isReportSheetPresented) {
            ReportPreviewSheet()
                .environment(viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .today: TodayDashboardView()
        case .heatmap: HeatmapView()
        case .ranks: RanksAndBadgesView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(LabForgeViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                LabForgeWordmark(markSize: 22, fontSize: 21)
                Text("科研打卡 · 时长铸造")
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.mutedSoft)
                    .padding(.leading, 30)
            }
            .padding(.top, 28)
            .padding(.horizontal, 18)
            .padding(.bottom, 26)

            VStack(spacing: 4) {
                ForEach(WorkbenchTab.allCases) { tab in
                    SidebarTabButton(tab: tab, isSelected: viewModel.selectedTab == tab) {
                        viewModel.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusDot(active: viewModel.isActive)
                    Text(viewModel.isActive
                         ? "进行中 · \(DurationFormatter.liveTimer(viewModel.activeElapsedSeconds))"
                         : (viewModel.todaySessions.isEmpty ? "今日待打卡" : "今日 \(DurationFormatter.menuBarDuration(viewModel.todayTotalSeconds))"))
                        .font(ClaudeTypography.number(12, weight: .medium))
                        .foregroundStyle(ClaudePalette.body)
                        .lineLimit(1)
                }

                Button {
                    viewModel.isReportSheetPresented = true
                } label: {
                    Label("生成今日战报", systemImage: "doc.richtext")
                }
                .buttonStyle(ClaudeSecondaryButtonStyle(fullWidth: true, height: 36))

                Button {
                    viewModel.toggleAppearance()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isEffectivelyDark ? "sun.max" : "moon")
                            .frame(width: 16)
                        Text(viewModel.isEffectivelyDark ? "切换到暖浅色" : "切换到暖炭黑")
                        Spacer()
                    }
                }
                .buttonStyle(ClaudeTextButtonStyle(color: ClaudePalette.muted))
            }
            .padding(18)
            .overlay(alignment: .top) { ClaudeDivider() }
        }
        .frame(maxHeight: .infinity)
        .background(ClaudePalette.surfaceSoft)
    }
}

/// `category-tab` / `category-tab-active` — warm pill, never system blue.
private struct SidebarTabButton: View {
    let tab: WorkbenchTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? ClaudePalette.primary : ClaudePalette.muted)
                    .frame(width: 18)
                Text(tab.title)
                    .font(ClaudeTypography.navLink)
                    .foregroundStyle(isSelected ? ClaudePalette.ink : ClaudePalette.muted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                    .fill(isSelected ? ClaudePalette.surfaceCard : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? ClaudePalette.hairline : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Toast

private struct ToastOverlay: View {
    let toast: ToastMessage?
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 10) {
                    Image(systemName: icon(for: toast.kind))
                        .foregroundStyle(color(for: toast.kind))
                    Text(toast.text)
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.onDark)
                        .lineLimit(2)
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(ClaudeTextButtonStyle(color: ClaudePalette.onDarkSoft))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: ClaudeRadius.lg, style: .continuous).fill(ClaudePalette.surfaceDark))
                .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .shadow(color: Color(hex: 0x141413, opacity: 0.08), radius: 3, y: 1)
                .frame(maxWidth: 520)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
    }

    private func icon(for kind: ToastMessage.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: ToastMessage.Kind) -> Color {
        switch kind {
        case .success: return ClaudePalette.success
        case .info: return ClaudePalette.accentAmber
        case .error: return ClaudePalette.error
        }
    }
}
