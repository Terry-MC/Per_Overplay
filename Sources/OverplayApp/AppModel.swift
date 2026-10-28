import AppKit
import Combine
import Foundation
import UserNotifications
import OverplayCore

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case usage
    case quota
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .usage: return "用量"
        case .quota: return "额度"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .usage: return "chart.bar.xaxis"
        case .quota: return "gauge.with.dots.needle.50percent"
        case .settings: return "gearshape"
        }
    }
}

enum BannerStyle {
    case info
    case success
    case warning
    case error
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var style: BannerStyle
    var message: String
}

struct DailyCostPoint: Identifiable, Equatable {
    var day: String
    var provider: String
    var cost: Double
    var currency: String
    var id: String { "\(day)|\(provider)|\(currency)" }
}

struct DailyTokenPoint: Identifiable, Equatable {
    var day: String
    var prompt: Int
    var completion: Int
    var promptAvailable: Bool
    var completionAvailable: Bool
    var id: String { day }
    var total: Int { prompt + completion }
}

enum AppActionError: LocalizedError {
    case demoReadOnly
    case emptyName
    case emptyKey
    case invalidAmount
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .demoReadOnly: return "演示模式不可修改真实账户或凭证"
        case .emptyName: return "账户名称不能为空"
        case .emptyKey: return "API Key 不能为空"
        case .invalidAmount: return "请输入大于 0 的金额"
        case .storage(let message): return message
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var balances: [String: [String: BalanceSnapshot]] = [:]
    @Published private(set) var balanceHistory: [String: [String: [BalanceSnapshot]]] = [:]
    @Published private(set) var quotas: [String: QuotaSnapshot] = [:]
    @Published private(set) var usageRecords: [UsageRecord] = []
    @Published private(set) var alerts: [AlertEvent] = []
    @Published private(set) var settings = AppSettings()
    @Published private(set) var isDemo = false
    @Published private(set) var syncingAccountIds: Set<String> = []
    @Published private(set) var now = Date()
    @Published private(set) var banner: Banner?
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var initializationWarning: String?
    @Published private(set) var showOnboarding = false
    @Published private(set) var lastRefreshAllAt: Date?
    @Published var selectedTab: DashboardTab = .overview
    @Published var selectedPreset: AnalysisPreset = .thirty {
        didSet { validateUsageFilters() }
    }
    @Published var selectedCurrency: String?
    @Published var usageAccountFilter: String? {
        didSet { validateUsageFilters() }
    }
    @Published var usageModelFilter: String?

    var onStatusChanged: (() -> Void)?

    private let databaseURL: URL
    private let credentials: KeychainCredentialStore
    private let notifications = NotificationManager()
    private var realStore: OverplayStore?
    private var demoStore: OverplayStore?
    private var syncEngine: SyncEngine?
    private var transport: URLSessionTransport
    private var timer: Timer?
    private var bannerDismissTask: Task<Void, Never>?

    private static let demoFlagKey = "overplay.demoMode"
    private static let demoDisclaimerKey = "overplay.demoDisclaimerAccepted"

    init(dataDirectory: URL? = nil, forceDemo: Bool = false) {
        let directory = dataDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Overplay", isDirectory: true)
        self.databaseURL = directory.appendingPathComponent("overplay.sqlite")
        self.credentials = KeychainCredentialStore()
        self.transport = URLSessionTransport()

        let defaults = UserDefaults.standard
        let persistedDemo = defaults.bool(forKey: Self.demoFlagKey)
            && defaults.bool(forKey: Self.demoDisclaimerKey)
        if forceDemo || persistedDemo {
            if let demo = try? DemoData.makeStore() {
                demoStore = demo
                isDemo = true
            } else {
                initializationWarning = "演示数据初始化失败"
            }
        }
        if isDemo {
            settings = (try? demoStore?.settings()) ?? AppSettings()
        } else {
            openRealStoreIfNeeded()
        }
        reloadFromStore()
        showOnboarding = !isDemo && accounts.isEmpty
        Task { await refreshNotificationStatus() }
    }

    func start() {
        if !isDemo, let syncEngine {
            syncEngine.updateSettings(settings)
            syncEngine.bootstrap(accounts: accounts)
            evaluatePeriodicAlerts()
        }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        updateMenuBar()
    }

    func prepareForTermination() {
        timer?.invalidate()
        timer = nil
        syncEngine?.cancelAll()
    }

    // MARK: - Loading

    private var activeStore: OverplayStore? {
        isDemo ? demoStore : realStore
    }

    @discardableResult
    private func openRealStoreIfNeeded() -> Bool {
        if realStore != nil {
            syncEngine?.updateSettings(settings)
            return true
        }
        do {
            let store = try OverplayStore(path: databaseURL.path)
            realStore = store
            settings = try store.settings()
        } catch {
            do {
                let fallback = try OverplayStore.inMemory()
                realStore = fallback
                settings = (try? fallback.settings()) ?? AppSettings()
                initializationWarning = "无法打开本地数据库：\(error.localizedDescription)。当前数据不会持久化。"
            } catch {
                initializationWarning = "无法打开本地数据库：\(error.localizedDescription)"
                return false
            }
        }
        guard let realStore else { return false }
        let engine = SyncEngine(
            store: realStore,
            credentials: credentials,
            transport: transport,
            settings: settings
        )
        syncEngine = engine
        configureEngineCallbacks()
        return true
    }

    func reloadFromStore() {
        do {
            guard let store = activeStore else { return }
            settings = try store.settings()
            let loadedAccounts = try store.accounts()
            accounts = loadedAccounts
            var newBalances: [String: [String: BalanceSnapshot]] = [:]
            var newHistory: [String: [String: [BalanceSnapshot]]] = [:]
            var newQuotas: [String: QuotaSnapshot] = [:]
            let historyRange = CalendarDay.range(preset: .ninety, now: now)
            for account in loadedAccounts {
                let latest = try store.latestBalances(accountId: account.id)
                newBalances[account.id] = latest
                var accountHistory: [String: [BalanceSnapshot]] = [:]
                for currency in latest.keys {
                    accountHistory[currency] = try store.balanceSnapshots(
                        accountId: account.id, currency: currency, range: historyRange
                    )
                }
                newHistory[account.id] = accountHistory
                if let quota = try store.latestQuota(accountId: account.id) {
                    newQuotas[account.id] = quota
                }
            }
            balances = newBalances
            balanceHistory = newHistory
            quotas = newQuotas
            let range = CalendarDay.range(preset: .ninety, now: now)
            let ids = Set(loadedAccounts.map(\.id))
            usageRecords = try store.usage(range: range).filter { ids.contains($0.accountId) }
            let activeIds = Set(loadedAccounts.map(\.id))
            alerts = try store.alerts().filter { activeIds.contains($0.accountId) }
            if let selectedCurrency,
               !availableCurrencies.isEmpty,
               !availableCurrencies.contains(selectedCurrency) {
                self.selectedCurrency = nil
            }
            validateUsageFilters()
            showOnboarding = !isDemo && loadedAccounts.isEmpty
            now = Date()
        } catch {
            showBanner("读取本地数据失败：\(error.localizedDescription)", style: .error)
        }
        updateMenuBar()
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notifications.authorizationStatus()
    }

    // MARK: - Engine events

    private func configureEngineCallbacks() {
        syncEngine?.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleEngineEvent(event)
            }
        }
    }

    private func handleEngineEvent(_ event: SyncEvent) {
        switch event {
        case .started(let accountId):
            syncingAccountIds.insert(accountId)
            updateMenuBar()
        case .finished(let accountId, let outcome):
            syncingAccountIds.remove(accountId)
            lastRefreshAllAt = Date()
            if outcome.status == .invalidCredential {
                showBanner("\(outcome.error ?? "凭据失效")", style: .warning)
            }
            reloadFromStore()
        case .alerts(let events):
            reloadFromStore()
            deliverNotifications(for: events)
        case .scheduleChanged:
            updateMenuBar()
        }
    }

    private func tick() {
        now = Date()
        guard !isDemo, let syncEngine else {
            updateMenuBar()
            return
        }
        syncEngine.refreshDue(accounts: accounts)
        _ = evaluatePeriodicAlerts()
        updateMenuBar()
    }

    @discardableResult
    private func evaluatePeriodicAlerts() -> [AlertEvent] {
        guard !isDemo, let syncEngine else { return [] }
        return syncEngine.evaluatePeriodicAlerts(accounts: accounts, settings: settings, now: Date())
    }

    // MARK: - Refresh

    func refresh(account: Account) {
        guard !isDemo else {
            showBanner("演示模式使用固定演示数据，不发起网络请求", style: .info)
            return
        }
        guard account.enabled else {
            showBanner("该账户已禁用，请先启用", style: .info)
            return
        }
        guard let syncEngine else { return }
        Task {
            _ = await syncEngine.refresh(account: account, trigger: .manual)
            reloadFromStore()
        }
    }

    func refreshAll() {
        guard !isDemo else {
            showBanner("演示模式使用固定演示数据，不发起网络请求", style: .info)
            return
        }
        let enabled = accounts.filter(\.enabled)
        guard !enabled.isEmpty else {
            showBanner("没有可刷新的账户", style: .info)
            return
        }
        guard let syncEngine else { return }
        lastRefreshAllAt = Date()
        for (index, account) in enabled.enumerated() {
            Task {
                if index > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(index) * 150_000_000)
                }
                _ = await syncEngine.refresh(account: account, trigger: .manual)
            }
        }
        showBanner("已开始刷新 \(enabled.count) 个账户", style: .info)
    }

    func isSyncing(_ account: Account) -> Bool {
        syncingAccountIds.contains(account.id)
    }

    // MARK: - Account management

    func saveNewAccount(provider: ProviderKind, name: String, apiKey: String) throws -> Account {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage("本地数据库不可用") }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw AppActionError.emptyKey }
        let account = Account(
            provider: provider,
            name: trimmedName.isEmpty ? provider.displayName : trimmedName
        )
        try credentials.setCredential(trimmedKey, accountId: account.id)
        do {
            try realStore.insertAccount(account)
        } catch {
            try? credentials.deleteCredential(accountId: account.id)
            throw AppActionError.storage("保存账户失败：\(error.localizedDescription)")
        }
        reloadFromStore()
        syncEngine?.resetSchedule(accountId: account.id)
        if let refreshed = accounts.first(where: { $0.id == account.id }) {
            refresh(account: refreshed)
        }
        showBanner("已添加 \(account.displayName)，正在测试连接与能力", style: .success)
        return account
    }

    func updateAccount(_ account: Account, name: String, newAPIKey: String?) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage("本地数据库不可用") }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? account.provider.displayName : trimmedName
        try realStore.updateProfile(id: account.id, name: resolvedName)
        let trimmedKey = newAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedKey.isEmpty {
            try credentials.setCredential(trimmedKey, accountId: account.id)
            try realStore.resetSyncFailures(id: account.id)
            syncEngine?.resetSchedule(accountId: account.id)
        }
        reloadFromStore()
        if let refreshed = accounts.first(where: { $0.id == account.id }), refreshed.enabled {
            if !trimmedKey.isEmpty {
                refresh(account: refreshed)
            }
        }
        showBanner("账户信息已更新", style: .success)
    }

    func setAccountEnabled(_ account: Account, enabled: Bool) {
        guard !isDemo else {
            showBanner("演示模式下账户不可禁用", style: .info)
            return
        }
        guard let realStore else { return }
        do {
            try realStore.setAccountEnabled(id: account.id, enabled: enabled)
            if !enabled {
                syncEngine?.cancel(accountId: account.id)
            } else {
                syncEngine?.resetSchedule(accountId: account.id)
            }
            reloadFromStore()
            if enabled, let refreshed = accounts.first(where: { $0.id == account.id }) {
                refresh(account: refreshed)
            }
        } catch {
            showBanner("更新账户状态失败：\(error.localizedDescription)", style: .error)
        }
    }

    func deleteAccount(_ account: Account, removeHistory: Bool) {
        guard !isDemo else {
            showBanner("演示模式下账户为固定演示数据", style: .info)
            return
        }
        guard let realStore else { return }
        do {
            syncEngine?.cancel(accountId: account.id)
            try credentials.deleteCredential(accountId: account.id)
            try realStore.deleteAccount(id: account.id, removeHistory: removeHistory)
            reloadFromStore()
            showBanner(
                removeHistory ? "已删除账户与历史数据" : "已删除账户；历史数据已保留但不参与统计",
                style: .success
            )
        } catch {
            showBanner("删除账户失败：\(error.localizedDescription)", style: .error)
        }
    }

    func testConnection(provider: ProviderKind, apiKey: String) async -> ConnectionTestResult {
        let transport = URLSessionTransport()
        defer { transport.shutdown() }
        let connector = ConnectorFactory.make(for: provider, transport: transport)
        return await connector.testConnection(credential: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), now: Date())
    }

    // MARK: - Budget & thresholds

    func saveBudget(account: Account, amountText: String, currency: String) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage("本地数据库不可用") }
        guard let amount = Money.parse(amountText), amount > 0 else {
            throw AppActionError.invalidAmount
        }
        try realStore.setBudget(
            accountId: account.id,
            budget: Budget(amount: amount, currency: currency)
        )
        reloadFromStore()
        evaluateAndReloadAlerts()
        showBanner("已保存本地月度预算", style: .success)
    }

    func clearBudget(account: Account) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage("本地数据库不可用") }
        try realStore.setBudget(accountId: account.id, budget: nil)
        reloadFromStore()
        showBanner("已移除本地预算", style: .success)
    }

    func saveThreshold(account: Account, amountText: String, currency: String) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage("本地数据库不可用") }
        guard let amount = Money.parse(amountText), amount > 0 else {
            throw AppActionError.invalidAmount
        }
        try realStore.setBalanceThreshold(
            accountId: account.id,
            threshold: BalanceThreshold(amount: amount, currency: currency)
        )
        reloadFromStore()
        evaluateAndReloadAlerts()
        showBanner("已保存余额低水位阈值", style: .success)
    }

    func clearThreshold(account: Account) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage("本地数据库不可用") }
        try realStore.setBalanceThreshold(accountId: account.id, threshold: nil)
        reloadFromStore()
        showBanner("已移除余额阈值", style: .success)
    }

    private func evaluateAndReloadAlerts() {
        _ = evaluatePeriodicAlerts()
    }

    // MARK: - Derived metrics

    var currentRange: DayRange {
        CalendarDay.range(preset: selectedPreset, now: now)
    }

    func records(for preset: AnalysisPreset) -> [UsageRecord] {
        let range = CalendarDay.range(preset: preset, now: now)
        return usageRecords.filter { range.contains($0.day) }
    }

    var unfilteredRecords: [UsageRecord] {
        records(for: selectedPreset)
    }

    var currentRecords: [UsageRecord] {
        var records = unfilteredRecords
        if let usageAccountFilter {
            records = records.filter { $0.accountId == usageAccountFilter }
        }
        if let usageModelFilter {
            records = records.filter { $0.model == usageModelFilter }
        }
        return records
    }

    var filterAccounts: [(id: String, name: String)] {
        var seen: [String: String] = [:]
        for record in unfilteredRecords where seen[record.accountId] == nil {
            seen[record.accountId] = record.accountName
        }
        return seen.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var filterModels: [String] {
        var records = unfilteredRecords
        if let usageAccountFilter {
            records = records.filter { $0.accountId == usageAccountFilter }
        }
        return Array(Set(records.map(\.model))).sorted()
    }

    private func validateUsageFilters() {
        if let usageAccountFilter, !filterAccounts.contains(where: { $0.id == usageAccountFilter }) {
            self.usageAccountFilter = nil
        }
        if let usageModelFilter, !filterModels.contains(usageModelFilter) {
            self.usageModelFilter = nil
        }
    }

    var hasUsageFilters: Bool {
        usageAccountFilter != nil || usageModelFilter != nil
    }

    func resetUsageFilters() {
        usageAccountFilter = nil
        usageModelFilter = nil
    }

    var availableCurrencies: [String] {
        Array(Set(currentRecords.compactMap(\.currency))).sorted()
    }

    var effectiveCurrency: String? {
        if let selectedCurrency, availableCurrencies.contains(selectedCurrency) {
            return selectedCurrency
        }
        if availableCurrencies.contains("USD") { return "USD" }
        return availableCurrencies.first
    }

    func costs(_ records: [UsageRecord]) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for record in records {
            guard let cost = record.cost, let currency = record.currency else { continue }
            result[currency, default: 0] += cost
        }
        return result
    }

    var todayCosts: [String: Decimal] {
        let today = CalendarDay.string(for: now, timeZone: CalendarDay.utc)
        return costs(usageRecords.filter { $0.day == today })
    }

    var monthCosts: [String: Decimal] {
        let (_, range) = CalendarDay.monthRange(now: now)
        return costs(usageRecords.filter { range.contains($0.day) })
    }

    var tokenSummary: (total: Int, totalAccounts: Int, providersWithTokens: Int) {
        let range = CalendarDay.range(preset: .thirty, now: now)
        let records = usageRecords.filter { range.contains($0.day) }
        let total = records.reduce(0) { $0 + ($1.totalTokens ?? 0) }
        let providers = Set(records.filter { $0.totalTokens != nil }.map(\.accountId)).count
        return (total, accounts.count, providers)
    }

    var officialCreditsRemaining: [String: Decimal] {
        var result: [String: Decimal] = [:]
        for quota in quotas.values {
            result[quota.currency, default: 0] += quota.remaining
        }
        return result
    }

    var officialBalances: [String: Decimal] {
        var result: [String: Decimal] = [:]
        for accountBalances in balances.values {
            for balance in accountBalances.values {
                result[balance.currency, default: 0] += balance.total
            }
        }
        return result
    }

    func budgetSpend(for account: Account) -> Decimal? {
        guard let budget = account.budget, account.lastSuccessAt != nil else { return nil }
        let (_, range) = CalendarDay.monthRange(now: now)
        return BudgetMath.spend(
            records: usageRecords,
            accountId: account.id,
            currency: budget.currency,
            range: range
        )
    }

    func budgetRatio(for account: Account) -> Decimal? {
        BudgetMath.ratio(spend: budgetSpend(for: account), budget: account.budget)
    }

    func budgetRemaining(for account: Account) -> Decimal? {
        BudgetMath.remaining(budget: account.budget, spend: budgetSpend(for: account))
    }

    func budgetForecast(for account: Account) -> Decimal? {
        BudgetMath.forecast(spend: budgetSpend(for: account), now: now)
    }

    func latestBalances(for account: Account) -> [BalanceSnapshot] {
        (balances[account.id] ?? [:]).values.sorted { $0.currency < $1.currency }
    }

    func latestQuota(for account: Account) -> QuotaSnapshot? {
        quotas[account.id]
    }

    func health(for account: Account) -> AccountHealth {
        if !account.enabled { return .disabled }
        if isSyncing(account) { return .syncing }
        if account.credentialInvalid { return .invalidCredential }
        if account.consecutiveFailures > 0 { return .failed }
        if let lastSuccess = account.lastSuccessAt {
            if now.timeIntervalSince(lastSuccess) > settings.refreshInterval * 2 { return .stale }
            if account.lastError != nil { return .partial }
            return .healthy
        }
        if account.lastError != nil { return .failed }
        return .neverSynced
    }

    func isStale(_ account: Account) -> Bool {
        guard let lastSuccess = account.lastSuccessAt else { return false }
        return now.timeIntervalSince(lastSuccess) > settings.refreshInterval * 2
    }

    func capabilitySummary(for account: Account) -> String {
        if !account.enabled { return "已禁用" }
        if account.credentialInvalid {
            return account.provider == .openrouter
                ? "凭据失效 · 需要 Management Key"
                : "凭据失效 · 需要重新输入 API Key"
        }
        guard account.lastSuccessAt != nil else {
            if account.lastError != nil { return "能力未验证（同步失败）" }
            return "等待连接测试"
        }
        if account.lastError != nil {
            return account.provider == .openrouter
                ? "credits 可用；用量接口暂时不可用"
                : "部分成功"
        }
        switch account.provider {
        case .deepseek:
            return "余额可用 · 官方无历史用量 / 费用"
        case .openrouter:
            return "credits / 额度 / 用量 / 费用可用"
        }
    }

    func lastSyncText(for account: Account) -> String {
        if let lastSuccess = account.lastSuccessAt {
            let text = DateFormatters.mediumDateTime.string(from: lastSuccess)
            return isStale(account) ? "已过期 · 最后成功 \(text)" : "最后成功 \(text)"
        }
        return "尚未成功同步"
    }

    var unacknowledgedAlerts: [AlertEvent] {
        alerts.filter { !$0.acknowledged }
    }

    var hasCriticalAlert: Bool {
        alerts.contains {
            !$0.acknowledged && [.budgetExceeded, .credentialInvalid, .syncFailed, .dataStale].contains($0.kind)
        }
    }

    func acknowledge(_ alert: AlertEvent) {
        guard let store = activeStore else { return }
        do {
            try store.acknowledgeAlert(id: alert.id)
            reloadFromStore()
        } catch {
            showBanner("确认告警失败：\(error.localizedDescription)", style: .error)
        }
    }

    func dailyCostSeries(records: [UsageRecord], currency: String) -> [DailyCostPoint] {
        var grouped: [String: Decimal] = [:]
        for record in records where record.currency == currency {
            guard let cost = record.cost else { continue }
            let key = "\(record.day)|\(record.provider.displayName)"
            grouped[key, default: 0] += cost
        }
        return grouped.compactMap { key, value -> DailyCostPoint? in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return DailyCostPoint(
                day: parts[0],
                provider: parts[1],
                cost: NSDecimalNumber(decimal: value).doubleValue,
                currency: currency
            )
        }
        .sorted { $0.day < $1.day }
    }

    func dailyTokenSeries(records: [UsageRecord]) -> [DailyTokenPoint] {
        var grouped: [String: (prompt: Int, completion: Int, promptAvailable: Bool, completionAvailable: Bool)] = [:]
        for record in records {
            guard record.promptTokens != nil || record.completionTokens != nil else { continue }
            var entry = grouped[record.day] ?? (0, 0, false, false)
            if let prompt = record.promptTokens {
                entry.prompt += prompt
                entry.promptAvailable = true
            }
            if let completion = record.completionTokens {
                entry.completion += completion
                entry.completionAvailable = true
            }
            grouped[record.day] = entry
        }
        return grouped.map {
            DailyTokenPoint(
                day: $0.key,
                prompt: $0.value.prompt,
                completion: $0.value.completion,
                promptAvailable: $0.value.promptAvailable,
                completionAvailable: $0.value.completionAvailable
            )
        }
        .sorted { $0.day < $1.day }
    }

    func balanceSnapshots(for account: Account) -> [(currency: String, snapshots: [BalanceSnapshot])] {
        let history = balanceHistory[account.id] ?? [:]
        return history.keys.sorted().map { ($0, history[$0] ?? []) }
    }

    func modelUsage(records: [UsageRecord], currency: String?) -> [ModelUsage] {
        let filtered = records.filter { currency == nil || $0.currency == currency }
        return UsageMath.groupByModel(filtered)
    }

    var dataFileDisplayPath: String {
        if isDemo { return "演示数据（内存命名空间，不读写真实数据库）" }
        guard let realStore else { return databaseURL.path }
        return realStore.isInMemory ? "内存数据库（不可持久化）" : realStore.path
    }

    var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "尚未请求"
        case .ephemeral: return "临时授权"
        @unknown default: return "未知"
        }
    }

    // MARK: - Settings & demo

    func setRefreshInterval(_ minutes: Int) {
        let clamped = max(5, min(60, minutes))
        var updated = settings
        updated.refreshIntervalMinutes = clamped
        guard let store = activeStore else { return }
        do {
            try store.saveSettings(updated)
            settings = updated
            if !isDemo {
                syncEngine?.updateSettings(updated)
            }
            updateMenuBar()
        } catch {
            showBanner("保存刷新间隔失败：\(error.localizedDescription)", style: .error)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if isDemo {
            showBanner("演示模式不读取系统通知权限，也不发送通知", style: .info)
            return
        }
        Task {
            if enabled {
                let status = await notifications.requestAuthorizationIfNeeded()
                notificationStatus = status
                guard status == .authorized || status == .provisional else {
                    showBanner("通知权限未开启。应用内告警仍可用，可在系统设置中授权通知。", style: .warning)
                    return
                }
            }
            var updated = settings
            updated.notificationsEnabled = enabled
            guard let store = activeStore else { return }
            do {
                try store.saveSettings(updated)
                settings = updated
            } catch {
                showBanner("保存通知设置失败：\(error.localizedDescription)", style: .error)
            }
        }
    }

    func sendTestNotification() {
        if isDemo {
            showBanner("演示模式不发送系统通知；告警仅显示在应用内", style: .info)
            return
        }
        Task {
            let status = await notifications.requestAuthorizationIfNeeded()
            notificationStatus = status
            guard status == .authorized || status == .provisional else {
                showBanner("通知权限未开启，无法发送测试通知", style: .warning)
                return
            }
            let sent = await notifications.post(
                title: "Overplay 测试通知",
                body: "通知功能正常。告警内容不会包含 API Key。"
            )
            if sent {
                showBanner("测试通知已发送", style: .success)
            } else {
                showBanner("测试通知发送失败，请检查系统通知设置", style: .error)
            }
        }
    }

    func openNotificationSettings() {
        notifications.openSystemNotificationSettings()
    }

    func requestEnterDemoMode() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "进入演示模式"
        alert.informativeText = DemoMode.disclaimer
        alert.addButton(withTitle: "进入演示模式")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            enterDemoMode()
        }
    }

    func showDemoDisclaimer() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "演示模式说明"
        alert.informativeText = DemoMode.disclaimer
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func enterDemoMode(acceptingDisclaimer: Bool = true) {
        guard !isDemo else { return }
        do {
            let demo = try DemoData.makeStore(now: Date())
            syncEngine?.cancelAllAccounts()
            syncEngine = nil
            realStore = nil
            syncingAccountIds.removeAll()
            demoStore = demo
            isDemo = true
            UserDefaults.standard.set(true, forKey: Self.demoFlagKey)
            if acceptingDisclaimer {
                UserDefaults.standard.set(true, forKey: Self.demoDisclaimerKey)
            }
            selectedTab = .overview
            selectedCurrency = nil
            usageAccountFilter = nil
            usageModelFilter = nil
            reloadFromStore()
            showOnboarding = false
            showBanner("已进入演示模式：所有数据均为模拟数据", style: .info)
        } catch {
            showBanner("演示数据初始化失败：\(error.localizedDescription)", style: .error)
        }
    }

    func exitDemoMode() {
        guard isDemo else { return }
        guard openRealStoreIfNeeded() else {
            showBanner("无法打开真实数据库，仍停留在演示模式", style: .error)
            return
        }
        isDemo = false
        demoStore = nil
        UserDefaults.standard.set(false, forKey: Self.demoFlagKey)
        selectedCurrency = nil
        usageAccountFilter = nil
        usageModelFilter = nil
        reloadFromStore()
        syncEngine?.updateSettings(settings)
        syncEngine?.bootstrap(accounts: accounts)
        showOnboarding = accounts.isEmpty
        showBanner("已退出演示模式", style: .info)
    }

    func clearAllData() {
        if isDemo {
            exitDemoMode()
            showBanner("演示数据已清除", style: .success)
            return
        }
        guard let realStore else { return }
        do {
            for account in accounts {
                syncEngine?.cancel(accountId: account.id)
            }
            try credentials.deleteAll()
            try realStore.clearAllData()
            notifications.clearDelivered()
            UserDefaults.standard.removeObject(forKey: Self.demoFlagKey)
            UserDefaults.standard.removeObject(forKey: Self.demoDisclaimerKey)
            selectedTab = .overview
            selectedCurrency = nil
            settings = AppSettings()
            syncEngine?.updateSettings(settings)
            reloadFromStore()
            showOnboarding = true
            showBanner("已清除账户、凭证、历史用量、告警记录与设置", style: .success)
        } catch {
            showBanner("清除数据失败：\(error.localizedDescription)", style: .error)
        }
    }

    func confirmClearAllData() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "清除全部本地数据？"
        alert.informativeText = "将删除所有账户、Keychain 凭证、历史用量、余额快照、告警记录与设置。此操作不可撤销。"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let second = NSAlert()
        second.alertStyle = .critical
        second.messageText = "再次确认：删除后无法恢复"
        second.informativeText = "如果只是想重置演示数据，请在演示模式中使用“退出演示模式”。"
        second.addButton(withTitle: "清除全部数据")
        second.addButton(withTitle: "取消")
        if second.runModal() == .alertFirstButtonReturn {
            clearAllData()
        }
    }

    func csvExportData() -> (filename: String, data: Data)? {
        var records = currentRecords
        if let effectiveCurrency, availableCurrencies.count > 0 {
            records = records.filter { $0.currency == effectiveCurrency }
        }
        let csv = CSVExport.makeCSV(
            records: records,
            range: currentRange,
            generatedAt: now,
            isDemo: isDemo
        )
        let filename = CSVExport.suggestedFilename(
            range: currentRange,
            generatedAt: now,
            isDemo: isDemo
        )
        return (filename, Data(csv.utf8))
    }

    // MARK: - Notifications & banners

    private func deliverNotifications(for events: [AlertEvent]) {
        guard !isDemo, !events.isEmpty, settings.notificationsEnabled else { return }
        let activeIds = Set(accounts.map(\.id))
        let relevant = events.filter { activeIds.contains($0.accountId) }
        guard !relevant.isEmpty else { return }
        Task {
            let status = await notifications.requestAuthorizationIfNeeded()
            notificationStatus = status
            guard status == .authorized || status == .provisional else {
                showBanner("通知权限未开启，告警已记录在应用内告警中心", style: .warning)
                return
            }
            await notifications.post(events: relevant)
        }
    }

    func showBanner(_ message: String, style: BannerStyle) {
        banner = Banner(style: style, message: message)
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: style == .error ? 7_000_000_000 : 4_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.banner?.message == message {
                self?.banner = nil
            }
        }
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        banner = nil
    }

    private func updateMenuBar() {
        onStatusChanged?()
    }

    var statusBarTooltip: String {
        if isDemo { return "Overplay · 演示数据" }
        if hasCriticalAlert {
            return "Overplay · 有未确认告警（\(unacknowledgedAlerts.count)）"
        }
        if !accounts.isEmpty {
            return "Overplay · \(accounts.count) 个账户"
        }
        return "Overplay"
    }
}
