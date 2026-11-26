import LabForgeCore
import SwiftUI

struct HistoryView: View {
    @Environment(LabForgeViewModel.self) private var viewModel
    @State private var query = ""
    @State private var editorMode: SessionEditorSheet.Mode?
    @State private var pendingDelete: LabSession?

    var body: some View {
        let summaries = filtered(viewModel.dailySummaries)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ClaudePageHeader(eyebrow: "Lab Journal", title: "历史记录",
                                 subtitle: "按天整理的每一段实验。忘记打卡？可以手动补上。") {
                    Button {
                        editorMode = .create
                    } label: {
                        Label("手动补卡", systemImage: "plus")
                    }
                    .buttonStyle(ClaudePrimaryButtonStyle())
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ClaudePalette.mutedSoft)
                    TextField("搜索目标、日志或日期（如 2026-11）", text: $query)
                        .claudeTextField()
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
        .sheet(item: $editorMode) { mode in
            SessionEditorSheet(mode: mode)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            LabForgeMarkView(size: 30, color: ClaudePalette.mutedSoft)
            Text(query.isEmpty ? "还没有任何记录" : "没有匹配「\(query)」的记录")
                .font(ClaudeTypography.serif(20))
                .tracking(-0.3)
                .foregroundStyle(ClaudePalette.ink)
            Text(query.isEmpty ? "第一次打卡之后，这里会变成你的实验年鉴。" : "试试其他关键词或日期。")
                .font(ClaudeTypography.bodySM)
                .foregroundStyle(ClaudePalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .claudeCard(.card)
    }

    private func filtered(_ summaries: [DailySummary]) -> [DailySummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return summaries }
        return summaries.filter { s in
            s.dateKey.contains(q)
                || s.goal.lowercased().contains(q)
                || LabForgeViewModel.chineseDate(s.date).contains(q)
                || s.sessions.contains { $0.goal.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
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
        case create
        case edit(LabSession)

        var id: String {
            switch self {
            case .create: return "create"
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
    @State private var errorText: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            let now = Date()
            let cal = Calendar.current
            let defaultEnd = cal.date(bySetting: .second, value: 0, of: now) ?? now
            _start = State(initialValue: defaultEnd.addingTimeInterval(-2 * 3600))
            _end = State(initialValue: defaultEnd)
            _goal = State(initialValue: "")
            _notes = State(initialValue: "")
        case .edit(let s):
            _start = State(initialValue: s.startTime)
            _end = State(initialValue: s.endTime ?? Date())
            _goal = State(initialValue: s.goal)
            _notes = State(initialValue: s.notes)
        }
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
        .frame(width: 460)
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
                try viewModel.addManualSession(start: start, end: end, goal: goal, notes: notes)
            case .edit(let s):
                try viewModel.updateSession(id: s.id, start: start, end: s.isActive ? nil : end, goal: goal, notes: notes)
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
