import AppKit
import LabForgeCore
import SwiftUI

enum ReportCardVariant: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { self == .light ? "暖奶油纸" : "暖炭黑" }
    var palette: FixedPalette { self == .light ? .light : .dark }
}

/// Immutable data for one report card render.
struct ReportCardSnapshot {
    var date: Date
    var todaySeconds: TimeInterval
    var targetSeconds: TimeInterval
    var sessionCount: Int
    var streak: Int
    var longestStreak: Int
    var totalActiveDays: Int
    var totalHours: Double
    var rankTitle: String
    var rankSubtitle: String
    var goal: String
    var log: String
    var quote: ResearchQuote
    /// Oldest first, 14 entries, 0...4.
    var recentLevels: [Int]
    var isActive: Bool

    var targetProgress: Double { targetSeconds > 0 ? min(todaySeconds / targetSeconds, 1) : 0 }
}

/// Editorial magazine-cover report card (540 × 720 pt → 1080 × 1440 PNG @2x).
/// Uses a fixed palette so the export never depends on the window appearance.
struct ReportCardView: View {
    static let size = CGSize(width: 540, height: 720)

    let snapshot: ReportCardSnapshot
    var variant: ReportCardVariant = .light

    private var p: FixedPalette { variant.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 22)
            headline
                .padding(.bottom, 24)
            metrics
                .padding(.bottom, 20)
            progress
                .padding(.bottom, 20)
            activityStrip
                .padding(.bottom, 22)
            journal
            Spacer(minLength: 16)
            quote
                .padding(.bottom, 20)
            footer
        }
        .padding(40)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(p.canvas)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    LabForgeMarkView(size: 16, color: p.primary)
                    Text("LABFORGE · 研铸日报")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(p.ink)
                }
                Spacer()
                Text(issueDate)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .tracking(1.2)
                    .foregroundStyle(p.muted)
            }
            Rectangle().fill(p.ink).frame(height: 1)
            HStack {
                Text("NO. \(String(format: "%03d", max(snapshot.totalActiveDays, 1)))")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .tracking(1.5)
                    .foregroundStyle(p.mutedSoft)
                Spacer()
                Text(weekdayText)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(p.mutedSoft)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(snapshot.rankTitle)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.0)
                Text("·").opacity(0.7)
                Text(snapshot.rankSubtitle.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
            }
            .foregroundStyle(p.onPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(p.primary))

            Text(headlineText)
                .font(.system(size: 38, weight: .regular, design: .serif))
                .tracking(-1.0)
                .lineSpacing(2)
                .foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric(label: "今日时长", value: DurationFormatter.menuBarDuration(snapshot.todaySeconds), unit: "h:m")
            metricDivider
            metric(label: "连续打卡", value: "\(snapshot.streak)", unit: "天")
            metricDivider
            metric(label: "累计时长", value: String(format: "%.1f", snapshot.totalHours), unit: "小时")
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(p.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(p.hairline).frame(height: 1) }
    }

    private var metricDivider: some View {
        Rectangle().fill(p.hairline).frame(width: 1, height: 44).padding(.horizontal, 16)
    }

    private func metric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .light).monospacedDigit())
                    .foregroundStyle(p.ink)
                Text(unit)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(p.mutedSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("每日目标")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(p.muted)
                Spacer()
                Text("\(Int((snapshot.targetProgress * 100).rounded()))% · 目标 \(DurationFormatter.shortHours(snapshot.targetSeconds))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(p.body)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.surfaceCreamStrong)
                    Capsule().fill(p.primary)
                        .frame(width: snapshot.targetProgress > 0 ? max(6, geo.size.width * snapshot.targetProgress) : 0)
                }
            }
            .frame(height: 6)
        }
    }

    private var activityStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近 14 天")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.muted)
            HStack(spacing: 5) {
                ForEach(Array(paddedLevels.enumerated()), id: \.offset) { index, level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(p.heatmap(level))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(index == paddedLevels.count - 1 ? p.ink.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                        .frame(height: 22)
                }
            }
        }
    }

    private var journal: some View {
        HStack(alignment: .top, spacing: 16) {
            journalColumn(title: "今日实验目标", text: snapshot.goal.isEmpty ? "未设定目标 —— 自由探索的一天。" : snapshot.goal)
            journalColumn(title: "科研日志摘录", text: snapshot.log.isEmpty ? "今天还没有写下日志。" : snapshot.log)
        }
    }

    private func journalColumn(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.primary)
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(p.body)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.surfaceCard))
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(snapshot.quote.text.split(separator: "\n").last.map(String.init) ?? snapshot.quote.text)”")
                .font(.system(size: 17, weight: .regular, design: .serif))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(p.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("—— \(snapshot.quote.author)")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(p.muted)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle().fill(p.hairline).frame(height: 1)
            HStack {
                Text("Forged in LabForge 研铸")
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(p.body)
                Spacer()
                Text("最长连胜 \(snapshot.longestStreak) 天 · 活跃 \(snapshot.totalActiveDays) 天")
                    .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                    .foregroundStyle(p.mutedSoft)
            }
        }
    }

    // MARK: Text

    private var headlineText: String {
        if snapshot.todaySeconds < 60 {
            return snapshot.isActive ? "实验刚刚开始，\n今天的故事正在书写。" : "今天还没有打卡，\n明天的实验室见。"
        }
        let duration = DurationFormatter.humanReadable(snapshot.todaySeconds)
        if snapshot.targetProgress >= 1 { return "今日目标达成，\n在实验室铸下 \(duration)。" }
        return "今天在实验室\n铸下 \(duration)。"
    }

    private var issueDate: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: snapshot.date)
        return String(format: "%04d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var weekdayText: String {
        snapshot.date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN")).weekday(.wide))
            + (snapshot.isActive ? " · 实验进行中" : "")
    }

    private var paddedLevels: [Int] {
        let levels = Array(snapshot.recentLevels.suffix(14))
        return Array(repeating: 0, count: max(0, 14 - levels.count)) + levels
    }
}

// MARK: - Preview sheet

struct ReportPreviewSheet: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var variant: ReportCardVariant = .light
    @State private var snapshot: ReportCardSnapshot?
    @State private var feedback: ToastMessage?
    private let previewScale = 0.62

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日科研战报").claudeDisplay(26).foregroundStyle(ClaudePalette.ink)
                    Text("1080 × 1440 PNG · 适合分享到朋友圈与组会群")
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.muted)
                }
                Spacer()
                Picker("纸张", selection: $variant) {
                    ForEach(ReportCardVariant.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                if let snapshot {
                    ReportCardView(snapshot: snapshot, variant: variant)
                        .clipShape(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: ClaudeRadius.md, style: .continuous)
                            .strokeBorder(ClaudePalette.hairline, lineWidth: 1))
                        .scaleEffect(previewScale)
                        .frame(width: ReportCardView.size.width * previewScale, height: ReportCardView.size.height * previewScale)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .frame(minHeight: 180, idealHeight: ReportCardView.size.height * previewScale + 16,
                   maxHeight: ReportCardView.size.height * previewScale + 16)
            .background(ClaudePalette.surfaceSoft)

            ClaudeDivider()

            HStack(spacing: 10) {
                if let feedback {
                    Label(feedback.text, systemImage: feedback.kind == .error ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .font(ClaudeTypography.caption)
                        .foregroundStyle(feedback.kind == .error ? ClaudePalette.error : ClaudePalette.muted)
                        .lineLimit(2)
                        .help(feedback.text)
                        .transition(.opacity)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(ClaudeTextButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .padding(.trailing, 6)
                Button("复制到剪贴板", action: copy).buttonStyle(ClaudeSecondaryButtonStyle())
                Button("另存为…", action: saveAs).buttonStyle(ClaudeSecondaryButtonStyle())
                Button("保存到桌面", action: saveToDesktop)
                    .buttonStyle(ClaudePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 600)
        .background(ClaudePalette.canvas)
        .onAppear {
            snapshot = viewModel.makeReportSnapshot()
            variant = viewModel.isEffectivelyDark ? .dark : .light
        }
    }

    private func perform(_ action: (ReportCardSnapshot) throws -> String?) {
        guard let snapshot else { return }
        do {
            if let message = try action(snapshot) {
                withAnimation(.easeOut(duration: 0.15)) { feedback = ToastMessage(text: message, kind: .success) }
            }
        } catch {
            feedback = ToastMessage(text: error.localizedDescription, kind: .error)
        }
    }

    private func saveToDesktop() {
        perform { snap in
            let url = try ReportCardExporter.saveToDesktop(snapshot: snap, variant: variant)
            return "已保存到桌面：\(url.lastPathComponent)"
        }
    }

    private func saveAs() {
        perform { snap in
            guard let url = try ReportCardExporter.saveWithPanel(snapshot: snap, variant: variant) else { return nil }
            return "已保存：\(url.lastPathComponent)"
        }
    }

    private func copy() {
        perform { snap in
            try ReportCardExporter.copyToPasteboard(snapshot: snap, variant: variant)
            return "已复制图像到剪贴板"
        }
    }
}
