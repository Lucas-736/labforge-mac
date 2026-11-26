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

private struct RunningSessionIdentity: Equatable {
    let id: UUID
    let start: Date

    init(_ session: LabSession) {
        id = session.id
        start = session.startTime
    }
}

/// Published after the Mac wakes from a long sleep while a session was running.
struct SleepRecoveryPrompt: Identifiable, Equatable {
    let id = UUID()
    let sleepStart: Date
    fileprivate let session: RunningSessionIdentity
    let awaySeconds: TimeInterval
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
    private(set) var isGlobalShortcutRegistered = false
    private(set) var pendingSleepRecovery: SleepRecoveryPrompt?
    /// Set by heatmap click-to-backfill; consumed by `HistoryView`.
    private(set) var pendingBackfillDate: Date?
    /// Category used by the next check-in when no session is running.
    private var nextCategory: SessionCategory = .default

    // MARK: Non-observed internals

    @ObservationIgnored let store: LabPersistenceStore
    @ObservationIgnored private let notificationService = NotificationService()
    @ObservationIgnored private let launchService = LaunchAtLoginService()
    @ObservationIgnored private let hotKeyService = GlobalHotKeyService()
    @ObservationIgnored private let soundService = SoundService()
    @ObservationIgnored private var sleepStart: (date: Date, elapsed: ContinuousClock.Instant, session: RunningSessionIdentity)?
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
        self.nextCategory = data.sessions.max { $0.startTime < $1.startTime }?.category ?? .default

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
        hotKeyService.shutdown()
        isGlobalShortcutRegistered = false
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
        observerTokens.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            // The observer runs on OperationQueue.main; capture the active session before sleep.
            MainActor.assumeIsolated {
                guard let self, !self.isShutDown else { return }
                self.handleWillSleep()
            }
        }))
        observerTokens.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isShutDown else { return }
                self.restartTicker()
                self.handleDidWake()
            }
        }))
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

    // MARK: Derived — weekly target & insights

    /// Monday-first weeks (ISO-style), matching Chinese academic convention.
    var weekCalendar: Calendar {
        var c = calendar
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    var weeklyProgress: InsightsEngine.WeeklyProgress {
        InsightsEngine.weeklyProgress(sessions: data.sessions, weeklyTargetSeconds: data.settings.weeklyTargetSeconds,
                                      now: now, calendar: weekCalendar)
    }

    /// Last 28 days.
    var categoryBreakdown: [InsightsEngine.CategoryBreakdown] {
        InsightsEngine.categoryBreakdown(sessions: data.sessions, withinLastDays: InsightsEngine.observationWindowDays,
                                         now: now, calendar: calendar)
    }

    var allTimeCategoryBreakdown: [InsightsEngine.CategoryBreakdown] {
        InsightsEngine.categoryBreakdown(sessions: data.sessions, withinLastDays: nil, now: now, calendar: calendar)
    }

    var recentGoals: [String] {
        InsightsEngine.recentGoals(sessions: data.sessions, dailyGoals: data.dailyGoals, limit: 5, calendar: calendar)
    }

    var calmObservations: [InsightsEngine.CalmObservation] {
        InsightsEngine.calmObservations(sessions: data.sessions, dailyTargetSeconds: data.settings.dailyTargetSeconds,
                                        weeklyTargetSeconds: data.settings.weeklyTargetSeconds,
                                        now: now, calendar: weekCalendar)
    }

    // MARK: Menu bar label

    var menuBarStyle: MenuBarDisplayStyle {
        get { data.settings.menuBarStyle }
        set { updateSettings { $0.menuBarStyle = newValue } }
    }

    /// Status-bar title for the current `menuBarStyle` (empty for `.iconOnly`).
    var menuBarTitle: String {
        let duration = DurationFormatter.menuBarDuration(todayTotalSeconds)
        let checkedInToday = !todaySessions.isEmpty
        switch data.settings.menuBarStyle {
        case .full:
            let streakCount = streak.currentStreak
            if isActive { return "🔥\(streakCount) · \(duration)" }
            if checkedInToday { return "🔥\(streakCount) · 今日 \(duration)" }
            return "LabForge · 待打卡"
        case .compact:
            if isActive { return duration }
            if checkedInToday { return "今日 \(duration)" }
            return "待打卡"
        case .iconOnly:
            return ""
        }
    }

    /// SF Symbol for the icon-only menu bar style.
    var menuBarSymbol: String {
        isActive || !todaySessions.isEmpty ? "flame.fill" : "flame"
    }

    /// VoiceOver description of the menu bar item.
    var menuBarAccessibilityLabel: String {
        let duration = DurationFormatter.humanReadable(todayTotalSeconds)
        if isActive { return "LabForge 实验进行中，今日 \(duration)" }
        if !todaySessions.isEmpty { return "LabForge 今日已打卡，累计 \(duration)" }
        return "LabForge 今日待打卡"
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
        let name = effectiveResearcherName
        switch calendar.component(.hour, from: now) {
        case 5..<11: return "早上好，\(name)"
        case 11..<14: return "中午好，\(name)"
        case 14..<18: return "下午好，\(name)"
        case 18..<23: return "晚上好，\(name)"
        default: return "夜深了，\(name)"
        }
    }

    // MARK: Researcher profile (debounced text fields)

    var researcherName: String {
        get { data.settings.researcherName }
        set {
            guard newValue != data.settings.researcherName else { return }
            data.settings.researcherName = newValue
            scheduleSave()
        }
    }

    var labName: String {
        get { data.settings.labName }
        set {
            guard newValue != data.settings.labName else { return }
            data.settings.labName = newValue
            scheduleSave()
        }
    }

    var researchFocus: String {
        get { data.settings.researchFocus }
        set {
            guard newValue != data.settings.researchFocus else { return }
            data.settings.researchFocus = newValue
            scheduleSave()
        }
    }

    var effectiveResearcherName: String { data.settings.effectiveResearcherName }
    var trimmedLabName: String { data.settings.trimmedLabName }
    var trimmedResearchFocus: String { data.settings.trimmedResearchFocus }

    // MARK: Session category

    /// The running session's category, or the one the next check-in will use.
    var activeCategory: SessionCategory {
        get { data.activeSession?.category ?? nextCategory }
        set {
            nextCategory = newValue
            guard let active = data.activeSession, active.category != newValue,
                  let i = data.sessions.firstIndex(where: { $0.id == active.id }) else { return }
            var candidate = data
            candidate.sessions[i].category = newValue
            candidate.sessions[i].updatedAt = Date()
            _ = saveSessionChange(candidate)
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
        candidate.sessions.append(LabSession(startTime: start, goal: goal, category: nextCategory))
        guard saveSessionChange(candidate) else { return }
        restartTicker()
        playChime()
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
        nextCategory = active.category
        updateTicker()
        playChime()
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

    func addManualSession(start: Date, end: Date, goal: String, notes: String,
                          category: SessionCategory = .default) throws {
        if let error = Self.validate(start: start, end: end) { throw error }
        try store.validateSession(startTime: start, endTime: end)
        let session = LabSession(startTime: start, endTime: end,
                                 goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                                 notes: notes, isManualEntry: true, category: category,
                                 createdAt: Date(), updatedAt: Date())
        var candidate = data
        candidate.sessions.append(session)
        candidate.sessions.sort { $0.startTime < $1.startTime }
        try commit(candidate)
        refreshNow()
        show("已补卡：\(DurationFormatter.humanReadable(session.duration()))。", .success)
    }

    /// `end == nil` keeps a running session running.
    func updateSession(id: UUID, start: Date, end: Date?, goal: String, notes: String,
                       category: SessionCategory? = nil) throws {
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
        if let category { candidate.sessions[i].category = category }
        candidate.sessions[i].updatedAt = Date()
        candidate.sessions.sort { $0.startTime < $1.startTime }
        try commit(candidate)
        restartTicker()
        show("记录已更新。", .success)
    }

    /// Heatmap click-to-backfill: opens the manual entry sheet for `date` in History.
    func requestBackfill(on date: Date) {
        pendingBackfillDate = calendar.startOfDay(for: date)
        selectedTab = .history
    }

    /// Returns and clears the pending backfill day.
    func consumePendingBackfill() -> Date? {
        defer { pendingBackfillDate = nil }
        return pendingBackfillDate
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
        if !applyDockIconPolicy() { show("无法切换程序坞图标。", .error) }
        refreshServiceStatuses()
        if !writesBlocked { syncReminder(showFeedback: false) }
        syncGlobalShortcut(showFeedback: false)
    }

    // MARK: Dock icon (menu-bar-only mode)

    var hideDockIcon: Bool { data.settings.hideDockIcon }

    func setHideDockIcon(_ hidden: Bool) {
        guard updateSettings({ $0.hideDockIcon = hidden }) else { return }
        guard applyDockIconPolicy() else {
            show("设置已保存，但 macOS 未能切换程序坞图标。", .error)
            return
        }
        show(hidden ? "已隐藏程序坞图标，仅在顶部菜单栏显示。" : "已在程序坞显示 LabForge 图标。", hidden ? .success : .info)
    }

    /// Applies the saved preference and restores focus to the dashboard if it was in use.
    private func applyDockIconPolicy() -> Bool {
        guard let app = NSApp else { return false }
        let target: NSApplication.ActivationPolicy = data.settings.hideDockIcon ? .accessory : .regular
        guard app.activationPolicy() != target else { return true }
        let dashboard = LabForgeAppDelegate.dashboardWindow()
        let restoreFocus = app.isActive && dashboard?.isVisible == true
        guard app.setActivationPolicy(target) else { return false }
        guard restoreFocus else { return true }
        dashboard?.makeKeyAndOrderFront(nil)
        app.activate()
        Task { @MainActor in
            guard NSApp.activationPolicy() == target,
                  let dashboard = LabForgeAppDelegate.dashboardWindow(),
                  dashboard.isVisible, !dashboard.isMiniaturized else { return }
            dashboard.makeKeyAndOrderFront(nil)
        }
        return true
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

    var weeklyTargetHours: Double {
        get { data.settings.weeklyTargetHours }
        set {
            guard newValue.isFinite else { return }
            let range = LabSettings.weeklyTargetRange
            let stepped = min(max(newValue.rounded(), range.lowerBound), range.upperBound)
            guard stepped != data.settings.weeklyTargetHours else { return }
            updateSettings { $0.weeklyTargetHours = stepped }
        }
    }

    // MARK: Sound

    var soundEnabled: Bool {
        get { data.settings.soundEnabled }
        set { updateSettings { $0.soundEnabled = newValue } }
    }

    var soundName: String {
        get { data.settings.effectiveSoundName }
        set {
            guard updateSettings({ $0.soundName = newValue }) else { return }
            previewSound()
        }
    }

    func previewSound() {
        soundService.play(data.settings.effectiveSoundName)
    }

    private func playChime() {
        guard data.settings.soundEnabled else { return }
        soundService.play(data.settings.effectiveSoundName)
    }

    // MARK: Global shortcut

    var globalShortcutEnabled: Bool {
        get { data.settings.globalShortcutEnabled }
        set {
            guard newValue != data.settings.globalShortcutEnabled,
                  updateSettings({ $0.globalShortcutEnabled = newValue }) else { return }
            syncGlobalShortcut(showFeedback: true)
        }
    }

    private func syncGlobalShortcut(showFeedback: Bool) {
        guard !isShutDown else { return }
        if data.settings.globalShortcutEnabled {
            let ok = hotKeyService.register { [weak self] in
                guard let self, !self.isShutDown else { return }
                self.toggleCheckIn()
            }
            isGlobalShortcutRegistered = ok
            guard showFeedback else { return }
            if ok {
                show("已开启全局快捷键 \(GlobalHotKeyService.shortcutLabel)", .success)
            } else {
                show("全局快捷键 \(GlobalHotKeyService.shortcutLabel) 注册失败，可能已被其他应用占用。", .error)
            }
        } else {
            hotKeyService.unregister()
            isGlobalShortcutRegistered = false
            if showFeedback { show("已关闭全局快捷键", .info) }
        }
    }

    var globalShortcutStatusText: String {
        if !data.settings.globalShortcutEnabled { return "已关闭 · 开启后可在任意应用中按 \(GlobalHotKeyService.shortcutLabel) 打卡 / 收工" }
        if isGlobalShortcutRegistered { return "已生效 · 任意应用中按 \(GlobalHotKeyService.shortcutLabel) 打卡 / 收工，无需辅助功能权限" }
        return "未能注册 \(GlobalHotKeyService.shortcutLabel)，可能与其他应用的快捷键冲突"
    }

    // MARK: Sleep recovery

    var sleepPromptThresholdMinutes: Int {
        get { data.settings.sleepPromptThresholdMinutes }
        set {
            guard updateSettings({ $0.sleepPromptThresholdMinutes = newValue }) else { return }
            if !data.settings.sleepPromptEnabled {
                pendingSleepRecovery = nil
                sleepStart = nil
            }
        }
    }

    private func handleWillSleep() {
        sleepStart = nil
        guard data.settings.sleepPromptEnabled, let active = data.activeSession else { return }
        let date = Date()
        guard date > active.startTime else { return }
        sleepStart = (date, ContinuousClock.now, RunningSessionIdentity(active))
    }

    private func handleDidWake() {
        defer { sleepStart = nil }
        guard let sleepStart, let active = data.activeSession,
              sleepStart.session == RunningSessionIdentity(active),
              data.settings.sleepPromptEnabled, now > sleepStart.date else { return }
        let elapsed = sleepStart.elapsed.duration(to: ContinuousClock.now)
        guard elapsed >= .seconds(data.settings.sleepPromptThresholdMinutes * 60) else { return }
        pendingSleepRecovery = SleepRecoveryPrompt(sleepStart: sleepStart.date, session: sleepStart.session,
                                                   awaySeconds: TimeInterval(elapsed.components.seconds))
    }

    /// Keeps the full running time (including the sleep).
    func keepSleepTime() {
        guard pendingSleepRecovery != nil else { return }
        pendingSleepRecovery = nil
        show("已保留全部计时，继续专注。", .info)
    }

    /// Closes the running session at the moment the Mac went to sleep.
    func endSessionAtSleepStart() {
        guard let prompt = pendingSleepRecovery else { return }
        let end = prompt.sleepStart
        guard let active = data.activeSession, prompt.session == RunningSessionIdentity(active),
              let i = data.sessions.firstIndex(where: { $0.id == active.id }),
              end > active.startTime, end <= Date() else {
            pendingSleepRecovery = nil
            show("无法按休眠时刻结束这条记录。", .info)
            return
        }
        var candidate = data
        candidate.sessions[i].endTime = end
        candidate.sessions[i].updatedAt = Date()
        guard saveSessionChange(candidate) else { return }
        pendingSleepRecovery = nil
        nextCategory = active.category
        updateTicker()
        show("已按休眠时刻 \(Self.timeString(end)) 收工，本次实验 \(DurationFormatter.humanReadable(end.timeIntervalSince(active.startTime)))。", .success)
    }

    func dismissSleepRecovery() {
        pendingSleepRecovery = nil
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
        NSApp.activate()
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

    func exportCSVBackup() {
        let panel = NSSavePanel()
        panel.title = "导出 LabForge CSV 表格"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        panel.nameFieldStringValue = String(format: "LabForge-记录-%04d-%02d-%02d.csv", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.resolvingSymlinksInPath().standardizedFileURL != store.fileURL.resolvingSymlinksInPath().standardizedFileURL else {
            show("请选择不同于当前数据文件的导出位置。", .error)
            return
        }
        do {
            let csv = CSVExporter.exportCSVData(sessions: data.sessions, now: Date(), calendar: calendar)
            try csv.write(to: url, options: .atomic)
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
        NSApp.activate()
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

        NSApp.activate()
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
            pendingSleepRecovery = nil
            sleepStart = nil
            nextCategory = data.activeSession?.category
                ?? data.sessions.max { $0.startTime < $1.startTime }?.category ?? .default
            applyAppKitAppearance()
            let dockPolicyApplied = applyDockIconPolicy()
            syncReminder(showFeedback: false)
            syncGlobalShortcut(showFeedback: false)
            refreshServiceStatuses()
            let summary = "已用备份覆盖，共 \(data.sessions.count) 条记录。"
            show(dockPolicyApplied ? summary : summary + " macOS 未能切换程序坞图标。", dockPolicyApplied ? .success : .error)
        } else {
            show("合并完成：新增 \(max(0, data.sessions.count - before)) 条，共 \(data.sessions.count) 条记录。", .success)
        }
    }

    // MARK: Report card

    func makeReportSnapshot() -> ReportCardSnapshot {
        let days = heatmapDays
        let streakSummary = streak
        let rank = rankProgress
        let week = weeklyProgress
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
            isActive: isActive,
            researcherName: effectiveResearcherName,
            labName: trimmedLabName,
            researchFocus: trimmedResearchFocus,
            weeklySeconds: week.totalSeconds,
            weeklyTargetSeconds: week.targetSeconds
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

    /// Write-before-mutate settings change for toggles / pickers. Returns `false` if saving failed
    /// (in which case `data` is left untouched).
    @discardableResult
    private func updateSettings(_ mutate: (inout LabSettings) -> Void) -> Bool {
        var candidate = data
        mutate(&candidate.settings)
        guard candidate.settings != data.settings else { return true }
        return saveSessionChange(candidate)
    }

    private func commit(_ candidate: LabStoreData) throws {
        try save(candidate)
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        if data.activeSession.map(RunningSessionIdentity.init) != candidate.activeSession.map(RunningSessionIdentity.init) {
            pendingSleepRecovery = nil
            sleepStart = nil
        }
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
