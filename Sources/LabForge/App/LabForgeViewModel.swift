import AppKit
import Foundation
import LabForgeCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting UI types

enum WorkbenchTab: String, CaseIterable, Identifiable {
    case today, heatmap, ranks, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日打卡"
        case .heatmap: return "科研热力图"
        case .ranks: return "段位与徽章"
        case .history: return "历史记录"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .heatmap: return "square.grid.3x3"
        case .ranks: return "rosette"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable { case success, info, error }
    let id = UUID()
    let text: String
    let kind: Kind
}

// MARK: - View model

/// Main-actor state coordinator: persistence, LabForgeCore engines, live ticker, sleep/wake,
/// settings, services, import/export and transient UI feedback.
@MainActor
@Observable
final class LabForgeViewModel {

    // MARK: Observed state

    private(set) var data: LabStoreData
    /// Refreshed once per second while a session is active, and on wake / activation / day change.
    private(set) var now = Date()
    var selectedTab: WorkbenchTab = .today
    var isReportSheetPresented = false
    private(set) var currentQuote: ResearchQuote
    private(set) var toast: ToastMessage?
    private(set) var celebration: CelebrationTrigger?
    private(set) var notificationStatus: NotificationService.Status = .notDetermined
    private(set) var launchStatus: LaunchAtLoginService.Status = .disabled

    // MARK: Non-observed internals

    @ObservationIgnored let store: LabPersistenceStore
    @ObservationIgnored private let notificationService = NotificationService()
    @ObservationIgnored private let launchService = LaunchAtLoginService()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var observerTokens: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var lastDayKey: String
    @ObservationIgnored private var isShutDown = false
    @ObservationIgnored private var writesBlocked = false
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var notificationStatusTask: Task<Void, Never>?

    var calendar: Calendar { .current }

    // MARK: Lifecycle

    init(store: LabPersistenceStore = LabPersistenceStore()) {
        self.store = store
        var startupMessage: ToastMessage?
        do {
            self.data = try store.load()
        } catch {
            // Never overwrite a damaged file: move it aside first, then start fresh.
            let backup: URL?
            switch error as? LabStoreError {
            case .corruptedData, .invalidSessionRange:
                backup = Self.backUpDamagedFile(at: store.fileURL)
            default:
                backup = nil
            }
            writesBlocked = backup == nil
            self.data = LabStoreData()
            startupMessage = ToastMessage(
                text: "数据文件无法读取（\(error.localizedDescription)）\(backup.map { "，已备份为 \($0.lastPathComponent)" } ?? "，已暂停写入以保留原文件")",
                kind: .error)
        }
        let start = Date()
        self.now = start
        self.currentQuote = QuoteLibrary.dailyQuote(for: start)
        self.lastDayKey = CalendarDayHelper.dateKey(for: start)

        applyAppKitAppearance()
        installObservers()
        updateTicker()
        refreshServiceStatuses()
        if let startupMessage { show(startupMessage) }
    }

    /// Stops the ticker, flushes pending writes and removes observers. Called on app termination.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        tickTask?.cancel()
        tickTask = nil
        toastTask?.cancel()
        reminderTask?.cancel()
        notificationStatusTask?.cancel()
        if pendingSaveTask != nil {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            persist()
        }
        for (center, token) in observerTokens { center.removeObserver(token) }
        observerTokens.removeAll()
    }

    // MARK: Live ticker & sleep/wake

    /// Runs a 1-second structured tick loop only while a session is active.
    private func updateTicker() {
        guard !isShutDown else { return }
        if let active = data.activeSession {
            guard tickTask == nil else { return }
            let start = active.startTime
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    // Align ticks to whole elapsed seconds of the running session.
                    let elapsed = max(0, Date().timeIntervalSince(start))
                    let wait = 1 - elapsed.truncatingRemainder(dividingBy: 1)
                    try? await Task.sleep(for: .milliseconds(Int((wait.isFinite && wait > 0 ? wait : 1) * 1000) + 5))
                    guard !Task.isCancelled, let self else { return }
                    self.refreshNow()
                }
            }
        } else {
            tickTask?.cancel()
            tickTask = nil
            refreshNow()
        }
    }

    private func restartTicker() {
        tickTask?.cancel()
        tickTask = nil
        refreshNow()
        updateTicker()
    }

    /// Recomputes `now` (and the daily quote when the calendar day rolls over).
    func refreshNow() {
        let date = Date()
        now = date
        let key = CalendarDayHelper.dateKey(for: date, calendar: calendar)
        if key != lastDayKey {
            lastDayKey = key
            currentQuote = QuoteLibrary.dailyQuote(for: date, calendar: calendar)
        }
    }

    private func installObservers() {
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isShutDown else { return }
                self.restartTicker()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observerTokens.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                object: nil, queue: .main, using: handler)))
        let center = NotificationCenter.default
        observerTokens.append((center, center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isShutDown else { return }
                self.restartTicker()
                self.refreshServiceStatuses()
            }
        }))
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            observerTokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
        }
    }

    // MARK: Derived — sessions & time

    var activeSession: LabSession? { data.activeSession }
    var isActive: Bool { data.activeSession != nil }
    var todayKey: String { CalendarDayHelper.dateKey(for: now, calendar: calendar) }

    /// Elapsed seconds of the running session, computed from wall-clock time (sleep-safe).
    var activeElapsedSeconds: TimeInterval {
        _ = now // observation dependency: re-evaluated on each tick
        guard let active = data.activeSession else { return 0 }
        return max(0, Date().timeIntervalSince(active.startTime))
    }

    var todayTotalSeconds: TimeInterval {
        CalendarDayHelper.totalSeconds(on: now, sessions: data.sessions, now: now, calendar: calendar)
    }

    var totalSeconds: TimeInterval { CalendarDayHelper.totalSeconds(sessions: data.sessions, now: now) }

    var todaySessions: [LabSession] {
        let key = todayKey
        return data.sessions
            .filter { s in CalendarDayHelper.daySegments(for: s, now: now, calendar: calendar).contains { $0.dateKey == key } }
            .sorted { $0.startTime < $1.startTime }
    }

    var streak: StreakSummary { StreakCalculator.compute(sessions: data.sessions, now: now, calendar: calendar) }
    var rankProgress: RankProgress { RankEngine.progress(forTotalSeconds: totalSeconds) }
    var badges: [AchievementBadge] { BadgeEngine.evaluate(sessions: data.sessions, dailyGoals: data.dailyGoals, now: now, calendar: calendar) }
    var heatmapDays: [HeatmapDay] { HeatmapBuilder.build365Days(sessions: data.sessions, dailyGoals: data.dailyGoals, now: now, calendar: calendar) }
    var dailySummaries: [DailySummary] { CalendarDayHelper.dailySummaries(sessions: data.sessions, dailyGoals: data.dailyGoals, now: now, calendar: calendar) }

    var dailyTargetSeconds: TimeInterval { data.settings.dailyTargetSeconds }
    var dailyTargetProgress: Double {
        guard dailyTargetSeconds > 0 else { return 0 }
        return min(todayTotalSeconds / dailyTargetSeconds, 1)
    }

    /// Status-bar title.
    var menuBarTitle: String {
        let streakCount = streak.currentStreak
        if isActive {
            return "🔥\(streakCount) · \(DurationFormatter.menuBarDuration(todayTotalSeconds))"
        }
        if !todaySessions.isEmpty {
            return "🔥\(streakCount) · 今日 \(DurationFormatter.menuBarDuration(todayTotalSeconds))"
        }
        return "LabForge · 待打卡"
    }

    /// Warm editorial status line for the popover / hero.
    var statusLine: String {
        if let active = data.activeSession {
            return "自 \(Self.timeString(active.startTime)) 起在实验室，专注正在累积。"
        }
        if todaySessions.isEmpty {
            let hour = calendar.component(.hour, from: now)
            return hour < 11 ? "新的一天，从进组那一刻开始计时。" : "今天还没有打卡，现在开始也不晚。"
        }
        if todayTotalSeconds >= dailyTargetSeconds {
            return "今日目标已达成，记得好好休息。"
        }
        return "今日已累计 \(DurationFormatter.humanReadable(todayTotalSeconds))，距目标还差 \(DurationFormatter.humanReadable(dailyTargetSeconds - todayTotalSeconds))。"
    }

    var greeting: String {
        switch calendar.component(.hour, from: now) {
        case 5..<11: return "早上好，研究者"
        case 11..<14: return "中午好，研究者"
        case 14..<18: return "下午好，研究者"
        case 18..<23: return "晚上好，研究者"
        default: return "夜深了，研究者"
        }
    }

    // MARK: Check-in / out

    func toggleCheckIn() {
        if isActive { checkOut() } else { checkIn() }
    }

    func checkIn() {
        guard data.activeSession == nil else { return }
        let start = Date()
        let goal = (data.dailyGoals[CalendarDayHelper.dateKey(for: start, calendar: calendar)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = data
        candidate.sessions.append(LabSession(startTime: start, goal: goal))
        guard saveSessionChange(candidate) else { return }
        restartTicker()
        celebration = CelebrationTrigger(kind: .checkIn)
        show("已进入实验室，计时开始。今天也一起铸造点什么吧。", .success)
    }

    func checkOut() {
        guard let active = data.activeSession, let index = data.sessions.firstIndex(where: { $0.id == active.id }) else { return }
        let end = Date()
        var candidate = data
        candidate.sessions[index].endTime = max(end, active.startTime)
        candidate.sessions[index].updatedAt = end
        guard saveSessionChange(candidate) else { return }
        updateTicker()
        celebration = CelebrationTrigger(kind: .checkOut)
        show("收工！本次实验 \(DurationFormatter.humanReadable(data.sessions[index].duration(asOf: end)))。", .success)
    }

    // MARK: Today goal & research log

    var todayGoal: String {
        get { data.dailyGoals[todayKey] ?? "" }
        set {
            let key = todayKey
            data.dailyGoals[key] = newValue
            if let active = data.activeSession, let i = data.sessions.firstIndex(where: { $0.id == active.id }) {
                data.sessions[i].goal = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                data.sessions[i].updatedAt = Date()
            }
            scheduleSave()
        }
    }

    /// The session today's log is attached to: the running one, else today's most recent.
    private var logSessionID: UUID? {
        data.activeSession?.id ?? todaySessions.last?.id
    }

    var canEditTodayLog: Bool { logSessionID != nil }

    var todayLog: String {
        get {
            guard let id = logSessionID else { return "" }
            return data.sessions.first { $0.id == id }?.notes ?? ""
        }
        set {
            guard let id = logSessionID, let i = data.sessions.firstIndex(where: { $0.id == id }) else { return }
            data.sessions[i].notes = newValue
            data.sessions[i].updatedAt = Date()
            scheduleSave()
        }
    }

    // MARK: Manual backfill / edit / delete

    enum SessionEditError: LocalizedError {
        case invalidRange, futureEnd, futureStart, notFound

        var errorDescription: String? {
            switch self {
            case .invalidRange: return "结束时间必须晚于开始时间。"
            case .futureEnd: return "结束时间不能晚于现在。"
            case .futureStart: return "开始时间不能晚于现在。"
            case .notFound: return "找不到这条记录，可能已被删除。"
            }
        }
    }

    static func validate(start: Date, end: Date?, now: Date = Date()) -> SessionEditError? {
        if start > now.addingTimeInterval(60) { return .futureStart }
        guard let end else { return nil }
        if end <= start { return .invalidRange }
        if end > now.addingTimeInterval(60) { return .futureEnd }
        return nil
    }

    func addManualSession(start: Date, end: Date, goal: String, notes: String) throws {
        if let error = Self.validate(start: start, end: end) { throw error }
        try store.validateSession(startTime: start, endTime: end)
        let session = LabSession(startTime: start, endTime: end,
                                 goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                                 notes: notes, isManualEntry: true, createdAt: Date(), updatedAt: Date())
        var candidate = data
        candidate.sessions.append(session)
        candidate.sessions.sort { $0.startTime < $1.startTime }
        try commit(candidate)
        refreshNow()
        show("已补卡：\(DurationFormatter.humanReadable(session.duration()))。", .success)
    }

    /// `end == nil` keeps a running session running.
    func updateSession(id: UUID, start: Date, end: Date?, goal: String, notes: String) throws {
        guard let i = data.sessions.firstIndex(where: { $0.id == id }) else { throw SessionEditError.notFound }
        let wasActive = data.sessions[i].isActive
        let resolvedEnd = wasActive ? nil : (end ?? data.sessions[i].endTime)
        if let error = Self.validate(start: start, end: resolvedEnd) { throw error }
        try store.validateSession(startTime: start, endTime: resolvedEnd)
        var candidate = data
        candidate.sessions[i].startTime = start
        candidate.sessions[i].endTime = resolvedEnd
        candidate.sessions[i].goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.sessions[i].notes = notes
        candidate.sessions[i].updatedAt = Date()
        candidate.sessions.sort { $0.startTime < $1.startTime }
        try commit(candidate)
        restartTicker()
        show("记录已更新。", .success)
    }

    func deleteSession(id: UUID) {
        guard let i = data.sessions.firstIndex(where: { $0.id == id }) else { return }
        var candidate = data
        candidate.sessions.remove(at: i)
        guard saveSessionChange(candidate) else { return }
        updateTicker()
        show("记录已删除。", .info)
    }

    // MARK: Appearance

    var appearanceMode: AppearanceMode { data.settings.appearanceMode }

    var preferredColorScheme: ColorScheme? {
        switch data.settings.appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Whether the app currently renders dark (resolving `.system` through AppKit).
    var isEffectivelyDark: Bool {
        switch data.settings.appearanceMode {
        case .light: return false
        case .dark: return true
        case .system:
            return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    func setAppearance(_ mode: AppearanceMode) {
        guard data.settings.appearanceMode != mode else { return }
        data.settings.appearanceMode = mode
        applyAppKitAppearance()
        persist()
    }

    /// 1-click light ↔ warm charcoal toggle.
    func toggleAppearance() {
        setAppearance(isEffectivelyDark ? .light : .dark)
    }

    /// Keeps AppKit chrome (title bar, menu-bar window, dynamic `NSColor`s) in sync with the mode.
    private func applyAppKitAppearance() {
        guard let app = NSApp else { return }
        switch data.settings.appearanceMode {
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        case .system: app.appearance = nil
        }
    }

    /// Re-applies the AppKit appearance once `NSApp` exists (called from the app delegate).
    func applicationDidFinishLaunching() {
        applyAppKitAppearance()
        refreshServiceStatuses()
        if !writesBlocked { syncReminder(showFeedback: false) }
    }

    // MARK: Daily target

    var dailyTargetHours: Double {
        get { data.settings.dailyTargetHours }
        set {
            let stepped = (newValue * 2).rounded() / 2
            guard stepped != data.settings.dailyTargetHours else { return }
            data.settings.dailyTargetHours = stepped
            persist()
        }
    }

    // MARK: Reminder

    var reminderEnabled: Bool { data.settings.reminderEnabled }

    var reminderTime: Date {
        get {
            calendar.date(bySettingHour: data.settings.reminderHour, minute: data.settings.reminderMinute, second: 0, of: now) ?? now
        }
        set {
            let c = calendar.dateComponents([.hour, .minute], from: newValue)
            data.settings.reminderHour = c.hour ?? 9
            data.settings.reminderMinute = c.minute ?? 0
            persist()
            if data.settings.reminderEnabled { syncReminder(showFeedback: false) }
        }
    }

    var notificationStatusText: String {
        NotificationService.description(for: notificationStatus, enabled: data.settings.reminderEnabled,
                                        hour: data.settings.reminderHour, minute: data.settings.reminderMinute)
    }

    var isNotificationAvailable: Bool { NotificationService.isAvailable }

    func setReminderEnabled(_ enabled: Bool) {
        data.settings.reminderEnabled = enabled
        persist()
        syncReminder(showFeedback: true)
    }

    private func syncReminder(showFeedback: Bool) {
        let settings = data.settings
        let previous = reminderTask
        previous?.cancel()
        notificationStatusTask?.cancel()

        // Wait for an in-flight system add before applying the newest settings.
        reminderTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            let status: NotificationService.Status
            if settings.reminderEnabled {
                status = await self.notificationService.scheduleDailyReminder(
                    hour: settings.reminderHour, minute: settings.reminderMinute)
            } else {
                self.notificationService.cancelDailyReminder()
                status = await self.notificationService.currentStatus()
            }
            guard !Task.isCancelled else { return }
            self.reminderTask = nil
            self.notificationStatus = status
            guard showFeedback else { return }
            if !settings.reminderEnabled {
                self.show("已关闭每日打卡提醒。", .info)
            } else if status == .authorized(scheduled: true) {
                self.show(String(format: "已开启每日 %02d:%02d 打卡提醒。",
                                 settings.reminderHour, settings.reminderMinute), .success)
            } else {
                self.data.settings.reminderEnabled = false
                self.persist()
                self.show(self.notificationStatusText, .error)
            }
        }
    }

    // MARK: Launch at login

    var launchAtLoginEnabled: Bool { launchStatus == .enabled || launchStatus == .requiresApproval }
    var launchStatusText: String { LaunchAtLoginService.description(for: launchStatus) }
    var isLaunchAtLoginAvailable: Bool { LaunchAtLoginService.isAvailable }

    func setLaunchAtLogin(_ enabled: Bool) {
        let status = launchService.setEnabled(enabled)
        launchStatus = status
        data.settings.launchAtLogin = (status == .enabled || status == .requiresApproval)
        persist()
        switch status {
        case .enabled: show("已开启开机自启动。", .success)
        case .disabled: show("已关闭开机自启动。", .info)
        case .requiresApproval: show("请在「系统设置 → 登录项」中允许 LabForge。", .info)
        case .unavailable, .notFound, .error: show(LaunchAtLoginService.description(for: status), .error)
        }
    }

    func openLoginItemsSettings() { launchService.openSystemSettings() }

    func refreshServiceStatuses() {
        launchStatus = launchService.currentStatus()
        guard reminderTask == nil, !isShutDown else { return }
        notificationStatusTask?.cancel()
        notificationStatusTask = Task { [weak self] in
            guard let self else { return }
            let status = await self.notificationService.currentStatus()
            guard !Task.isCancelled else { return }
            self.notificationStatus = status
        }
    }

    // MARK: Quotes

    func nextQuote() {
        currentQuote = QuoteLibrary.nextQuote(after: currentQuote.id)
    }

    // MARK: Data backup

    var dataFilePath: String {
        (store.fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    func revealDataFileInFinder() {
        let url = store.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }

    func exportJSONBackup() {
        let panel = NSSavePanel()
        panel.title = "导出 LabForge JSON 备份"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        panel.nameFieldStringValue = String(format: "LabForge-备份-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.resolvingSymlinksInPath().standardizedFileURL != store.fileURL.resolvingSymlinksInPath().standardizedFileURL else {
            show("请选择不同于当前数据文件的备份位置。", .error)
            return
        }
        do {
            let json = try store.exportJSONData(from: data)
            try json.write(to: url, options: .atomic)
            show("已导出 \(data.sessions.count) 条记录到 \(url.lastPathComponent)。", .success)
        } catch {
            show("导出失败：\(error.localizedDescription)", .error)
        }
    }

    func importJSONBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择 LabForge JSON 备份"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imported: LabStoreData
        do {
            imported = try store.decodeImportedJSON(try Data(contentsOf: url))
        } catch {
            show("导入失败：\(error.localizedDescription)", .error)
            return
        }

        let alert = NSAlert()
        alert.messageText = "如何导入这份备份？"
        alert.informativeText = "备份包含 \(imported.sessions.count) 条打卡记录。\n\n「合并」：按记录 ID 去重，保留较新的版本，当前设置不变。\n「覆盖」：用备份完整替换当前全部数据（不可撤销）。"
        alert.addButton(withTitle: "合并")
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .informational

        let choice = alert.runModal()
        let before = data.sessions.count
        let replace: Bool
        let candidate: LabStoreData
        switch choice {
        case .alertFirstButtonReturn:
            replace = false
            candidate = store.merge(imported: imported, into: data)
        case .alertSecondButtonReturn:
            replace = true
            candidate = imported
        default:
            return
        }

        do {
            try commit(candidate)
        } catch {
            show("导入失败：\(error.localizedDescription)", .error)
            return
        }
        restartTicker()
        if replace {
            applyAppKitAppearance()
            syncReminder(showFeedback: false)
            refreshServiceStatuses()
            show("已用备份覆盖，共 \(data.sessions.count) 条记录。", .success)
        } else {
            show("合并完成：新增 \(max(0, data.sessions.count - before)) 条，共 \(data.sessions.count) 条记录。", .success)
        }
    }

    // MARK: Report card

    func makeReportSnapshot() -> ReportCardSnapshot {
        let days = heatmapDays
        let streakSummary = streak
        let rank = rankProgress
        return ReportCardSnapshot(
            date: now,
            todaySeconds: todayTotalSeconds,
            targetSeconds: dailyTargetSeconds,
            sessionCount: todaySessions.count,
            streak: streakSummary.currentStreak,
            longestStreak: streakSummary.longestStreak,
            totalActiveDays: streakSummary.totalActiveDays,
            totalHours: rank.totalHours,
            rankTitle: rank.currentRank.title,
            rankSubtitle: rank.currentRank.englishSubtitle,
            goal: todayGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            log: todaySessions.map(\.notes).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n"),
            quote: currentQuote,
            recentLevels: days.suffix(14).map(\.intensityLevel),
            isActive: isActive
        )
    }

    // MARK: Toast

    func show(_ text: String, _ kind: ToastMessage.Kind) {
        show(ToastMessage(text: text, kind: kind))
    }

    private func show(_ message: ToastMessage) {
        guard !isShutDown else { return }
        toast = message
        toastTask?.cancel()
        let id = message.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(message.kind == .error ? 4.5 : 2.8))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            self.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    // MARK: Persistence

    /// Immediate atomic write.
    private func persist() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        do {
            try save(data)
        } catch {
            show("保存失败：\(error.localizedDescription)", .error)
        }
    }

    private func commit(_ candidate: LabStoreData) throws {
        try save(candidate)
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        data = candidate
    }

    private func saveSessionChange(_ candidate: LabStoreData) -> Bool {
        do {
            try commit(candidate)
            return true
        } catch {
            show("保存失败：\(error.localizedDescription)", .error)
            return false
        }
    }

    private func save(_ candidate: LabStoreData) throws {
        guard !writesBlocked else {
            throw LabStoreError.ioFailure("原始数据文件受保护。请先备份并移走该文件，然后重新启动 LabForge。")
        }
        try store.save(candidate)
    }

    /// Coalesces rapid text edits into one write shortly after typing pauses.
    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.pendingSaveTask = nil
            self.persist()
        }
    }

    private static func backUpDamagedFile(at url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = UUID().uuidString
        let backup = url.deletingLastPathComponent().appendingPathComponent("records.damaged-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return backup
        } catch {
            return nil
        }
    }

    // MARK: Formatting helpers

    static func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func chineseDate(_ date: Date, weekday: Bool = true) -> String {
        var style = Date.FormatStyle(locale: Locale(identifier: "zh_CN")).year().month(.defaultDigits).day()
        if weekday { style = style.weekday(.wide) }
        return date.formatted(style)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: "zh_CN")).month(.defaultDigits).day())
    }
}
