import LabForgeCore
import SwiftUI

struct HistoryView: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @State private var query = ""
    @State private var categoryFilter: SessionCategory?
    @State private var editorMode: SessionEditorSheet.Mode?
    @State private var pendingDelete: LabSession?

    var body: some View {
        let summaries = filtered(viewModel.dailySummaries)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClaudePageHeader(eyebrow: "Lab Journal", title: "历史记录",
                                 subtitle: "按天整理的每一段实验。忘记打卡？可以手动补上。") {
                    HStack(spacing: 10) {
                        Button {
                            viewModel.exportCSVBackup()
                        } label: {
                            Label("导出 CSV", systemImage: "tablecells")
                        }
                        .buttonStyle(ClaudeSecondaryButtonStyle())
                        .help("导出全部记录为 Excel / Numbers 可读的 CSV 表格")
                        Button {
                            editorMode = .create(initialDate: nil)
                        } label: {
                            Label("手动补卡", systemImage: "plus")
                        }
                        .buttonStyle(ClaudePrimaryButtonStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(ClaudePalette.mutedSoft)
                        TextField("搜索目标、日志或日期（如 2026-11）", text: $query)
                            .claudeTextField()
                    }
                    categoryFilterRow
                        .padding(.leading, 26)
                }

                if summaries.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(summaries) { summary in
                            DayGroupCard(summary: summary, now: viewModel.now,
                                         onEdit: { editorMode = .edit($0) },
                                         onDelete: { pendingDelete = $0 })
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .onAppear(perform: consumeBackfill)
        .onChange(of: viewModel.pendingBackfillDate) { _, _ in consumeBackfill() }
        .sheet(item: $editorMode) { mode in
            SessionEditorSheet(mode: mode, initialCategory: viewModel.activeCategory)
                .environment(viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .alert("删除这条记录？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { session in
            Button("删除", role: .destructive) { viewModel.deleteSession(id: session.id) }
            Button("取消", role: .cancel) {}
        } message: { session in
            Text("\(LabForgeViewModel.chineseDate(session.startTime, weekday: false)) \(LabForgeViewModel.timeString(session.startTime)) 开始，时长 \(DurationFormatter.humanReadable(session.duration(asOf: viewModel.now)))。删除后无法恢复。")
        }
    }

    private func consumeBackfill() {
        guard let date = viewModel.consumePendingBackfill() else { return }
        editorMode = .create(initialDate: date)
    }

    private var categoryFilterRow: some View {
        ClaudeFlowLayout(spacing: 6, lineSpacing: 6) {
            filterPill(title: "全部", tone: nil, isSelected: categoryFilter == nil) { categoryFilter = nil }
            ForEach(SessionCategory.allCases) { category in
                filterPill(title: category.title, tone: ClaudePalette.category(category),
                           isSelected: categoryFilter == category) {
                    categoryFilter = categoryFilter == category ? nil : category
                }
            }
        }
    }

    private func filterPill(title: String, tone: Color?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let tone {
                    Circle().fill(tone).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(isSelected ? ClaudePalette.ink : ClaudePalette.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(isSelected ? ClaudePalette.surfaceCard : Color.clear))
            .overlay(Capsule().strokeBorder(isSelected ? ClaudePalette.hairline : ClaudePalette.hairlineSoft, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            LabForgeMarkView(size: 30, color: ClaudePalette.mutedSoft)
            Text(emptyTitle)
                .font(ClaudeTypography.serif(20))
                .tracking(-0.3)
                .foregroundStyle(ClaudePalette.ink)
            Text(isFiltering ? "试试其他关键词、日期或分类。" : "第一次打卡之后，这里会变成你的实验年鉴。")
                .font(ClaudeTypography.bodySM)
                .foregroundStyle(ClaudePalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .claudeCard(.card)
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || categoryFilter != nil
    }

    private var emptyTitle: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return "没有匹配「\(q)」的记录" }
        if let categoryFilter { return "还没有「\(categoryFilter.title)」分类的记录" }
        return "还没有任何记录"
    }

    private func filtered(_ summaries: [DailySummary]) -> [DailySummary] {
        let byCategory = categoryFilter.map { filter(summaries, by: $0) } ?? summaries
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return byCategory }
        return byCategory.filter { s in
            s.dateKey.contains(q)
                || s.goal.lowercased().contains(q)
                || LabForgeViewModel.chineseDate(s.date).contains(q)
                || s.sessions.contains { $0.goal.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
        }
    }

    /// Keeps only sessions of `category`, recomputing each day's total; drops empty days.
    private func filter(_ summaries: [DailySummary], by category: SessionCategory) -> [DailySummary] {
        summaries.compactMap { summary in
            let sessions = summary.sessions.filter { $0.category == category }
            guard !sessions.isEmpty else { return nil }
            let seconds = sessions.reduce(0.0) { total, session in
                total + CalendarDayHelper.daySegments(for: session, now: viewModel.now, calendar: viewModel.calendar)
                    .filter { $0.dateKey == summary.dateKey }
                    .reduce(0.0) { $0 + $1.seconds }
            }
            var copy = summary
            copy.sessions = sessions
            copy.sessionCount = sessions.count
            copy.totalSeconds = seconds
            return copy
        }
    }
}

// MARK: - Day group

private struct DayGroupCard: View {
    let summary: DailySummary
    let now: Date
    let onEdit: (LabSession) -> Void
    let onDelete: (LabSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(LabForgeViewModel.chineseDate(summary.date))
                    .font(ClaudeTypography.serif(19))
                    .tracking(-0.3)
                    .foregroundStyle(ClaudePalette.ink)
                if !summary.goal.isEmpty {
                    ClaudeBadgePill(text: summary.goal, systemImage: "target")
                        .frame(maxWidth: 320, alignment: .leading)
                }
                Spacer()
                Text("\(summary.sessionCount) 段 · \(DurationFormatter.humanReadable(summary.totalSeconds))")
                    .font(ClaudeTypography.number(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.body)
            }
            if summary.sessions.isEmpty {
                Text("当天设定了目标，但没有打卡记录。")
                    .font(ClaudeTypography.bodySM)
                    .foregroundStyle(ClaudePalette.mutedSoft)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summary.sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { ClaudeDivider(color: ClaudePalette.hairlineSoft) }
                        SessionRow(session: session, now: now, onEdit: { onEdit(session) }, onDelete: { onDelete(session) })
                    }
                }
            }
        }
        .claudeCard(.canvas, padding: 22)
    }
}

private struct SessionRow: View {
    let session: LabSession
    let now: Date
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(LabForgeViewModel.timeString(session.startTime)) – \(session.endTime.map(LabForgeViewModel.timeString) ?? "进行中")")
                    .font(ClaudeTypography.number(14, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text(DurationFormatter.liveTimer(session.duration(asOf: now)))
                    .font(ClaudeTypography.number(12))
                    .foregroundStyle(ClaudePalette.muted)
            }
            .frame(width: 130, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.goal.isEmpty ? "未填写目标" : session.goal)
                        .font(ClaudeTypography.titleSM)
                        .foregroundStyle(session.goal.isEmpty ? ClaudePalette.mutedSoft : ClaudePalette.ink)
                        .lineLimit(1)
                    CategoryTagPill(category: session.category, compact: true)
                    if session.isManualEntry { ClaudeBadgePill(text: "补卡", style: .outline) }
                    if session.isActive { ClaudeBadgePill(text: "进行中", style: .coral) }
                }
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.body)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(ClaudeIconButtonStyle(size: 28))
                    .help("编辑")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(ClaudeIconButtonStyle(size: 28))
                    .help("删除")
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Editor sheet

struct SessionEditorSheet: View {
    enum Mode: Identifiable {
        /// `initialDate` pre-populates start / end on that calendar day (heatmap click-to-backfill).
        case create(initialDate: Date?)
        case edit(LabSession)

        var id: String {
            switch self {
            case .create(let date): return "create-\(date.map { String($0.timeIntervalSince1970) } ?? "now")"
            case .edit(let s): return s.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(LabForgeViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date
    @State private var goal: String
    @State private var notes: String
    @State private var category: SessionCategory
    @State private var errorText: String?

    init(mode: Mode, initialDate: Date? = nil, initialCategory: SessionCategory = .default) {
        self.mode = mode
        switch mode {
        case .create(let modeDate):
            let range = Self.defaultRange(on: modeDate ?? initialDate)
            _start = State(initialValue: range.start)
            _end = State(initialValue: range.end)
            _goal = State(initialValue: "")
            _notes = State(initialValue: "")
            _category = State(initialValue: initialCategory)
        case .edit(let s):
            _start = State(initialValue: s.startTime)
            _end = State(initialValue: s.endTime ?? Date())
            _goal = State(initialValue: s.goal)
            _notes = State(initialValue: s.notes)
            _category = State(initialValue: s.category)
        }
    }

    /// Two hours ending now or 09:00–11:00 on a past day selected in the heatmap.
    static func defaultRange(on day: Date?, now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let roundedNow = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let fallback = (start: roundedNow.addingTimeInterval(-2 * 3600), end: roundedNow)
        guard let day, let interval = calendar.dateInterval(of: .day, for: day) else { return fallback }
        if interval.contains(now), now < interval.end {
            let end = roundedNow > interval.start ? roundedNow : now
            guard end > interval.start else { return fallback }
            return (max(interval.start, end.addingTimeInterval(-2 * 3600)), end)
        }
        guard interval.end <= now,
              let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
              let end = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day),
              start >= interval.start, end < interval.end, start < end else { return fallback }
        return (start, end)
    }

    private var initialDayText: String? {
        if case .create(let date?) = mode { return LabForgeViewModel.chineseDate(date) }
        return nil
    }

    private var isActiveSession: Bool {
        if case .edit(let s) = mode { return s.isActive }
        return false
    }

    private var liveError: String? {
        LabForgeViewModel.validate(start: start, end: isActiveSession ? nil : end)?.errorDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(modeEyebrow).claudeEyebrow(ClaudePalette.primary)
                Text(modeTitle).claudeDisplay(26).foregroundStyle(ClaudePalette.ink)
                if let initialDayText {
                    Text("从热力图选择：\(initialDayText)")
                        .font(ClaudeTypography.bodySM)
                        .foregroundStyle(ClaudePalette.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("分类").font(ClaudeTypography.caption).foregroundStyle(ClaudePalette.muted)
                ViewThatFits(in: .horizontal) {
                    CategorySelectorStrip(selection: $category)
                    CategorySelectorStrip(selection: $category, compact: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                field("开始时间") {
                    DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                if isActiveSession {
                    field("结束时间") {
                        ClaudeBadgePill(text: "进行中 · 收工时自动记录", style: .coral)
                    }
                } else {
                    field("结束时间") {
                        DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                }
                if liveError == nil && !isActiveSession {
                    Text("时长 \(DurationFormatter.humanReadable(end.timeIntervalSince(start)))")
                        .font(ClaudeTypography.number(12))
                        .foregroundStyle(ClaudePalette.muted)
                        .padding(.leading, 84)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("实验目标").font(ClaudeTypography.caption).foregroundStyle(ClaudePalette.muted)
                TextField("这段时间在做什么？", text: $goal)
                    .claudeTextField()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("实验日志").font(ClaudeTypography.caption).foregroundStyle(ClaudePalette.muted)
                ClaudeTextEditor(text: $notes, placeholder: "步骤、现象、待办……", minHeight: 100)
            }

            if let message = errorText ?? liveError {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(ClaudeTypography.caption)
                    .foregroundStyle(ClaudePalette.error)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(ClaudeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(saveTitle, action: save)
                    .buttonStyle(ClaudePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(liveError != nil)
            }
        }
        .padding(28)
        .frame(width: 540)
        .background(ClaudePalette.canvas)
        .onChange(of: start) { _, _ in errorText = nil }
        .onChange(of: end) { _, _ in errorText = nil }
    }

    private var modeEyebrow: String {
        if case .create = mode { return "Manual Entry" }
        return "Edit Session"
    }

    private var modeTitle: String {
        if case .create = mode { return "手动补卡" }
        return "编辑实验记录"
    }

    private var saveTitle: String {
        if case .create = mode { return "保存补卡" }
        return "保存修改"
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(ClaudeTypography.caption)
                .foregroundStyle(ClaudePalette.muted)
                .frame(width: 72, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func save() {
        do {
            switch mode {
            case .create:
                try viewModel.addManualSession(start: start, end: end, goal: goal, notes: notes, category: category)
            case .edit(let s):
                try viewModel.updateSession(id: s.id, start: start, end: s.isActive ? nil : end, goal: goal, notes: notes,
                                            category: category)
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
