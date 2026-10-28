import AppKit
import Combine
import Foundation
import UserNotifications
import OverplayCore

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case usage
    case quota
    case messages
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .usage: return "用量"
        case .quota: return "额度"
        case .messages: return "消息"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .usage: return "chart.bar.xaxis"
        case .quota: return "gauge.with.dots.needle.50percent"
        case .messages: return "bell"
        case .settings: return "gearshape"
        }
    }
}

enum BannerStyle: Equatable {
    case info
    case success
    case warning
    case error
}

struct ToastMessage: Identifiable, Equatable {
    var id: String
    var title: String
    var message: String
    var style: BannerStyle
    var alertId: String?
    var isDemo: Bool
    var duration: TimeInterval
    var expiresAt: Date?
    var autoDismiss: Bool

    var isAlert: Bool { alertId != nil }
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
    case currencyMismatch(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .demoReadOnly: return "演示模式不可修改真实账户或凭证"
        case .emptyName: return "账户名称不能为空"
        case .emptyKey: return "API Key 不能为空"
        case .invalidAmount: return "请输入大于 0 的金额"
        case .currencyMismatch(let currencies):
            return "该账户的余额币种为 \(currencies)，请选择对应币种"
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
    @Published private(set) var toasts: [ToastMessage] = []
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
    @Published var overviewPlatformFilter: ProviderKind? {
        didSet {
            overviewAccountFilter = nil
            ensureBalanceCurrencyFilter()
        }
    }
    @Published var overviewAccountFilter: String? {
        didSet { ensureBalanceCurrencyFilter() }
    }
    @Published var balanceCurrencyFilter: String?

    var onStatusChanged: (() -> Void)?

    private let databaseURL: URL
    private let credentials: KeychainCredentialStore
    private let notifications = NotificationManager()
    private var realStore: OverplayStore?
    private var demoStore: OverplayStore?
    private var syncEngine: SyncEngine?
    private var transport: URLSessionTransport
    private var timer: Timer?
    private var toastQueue: [ToastMessage] = []
    private var toastTasks: [String: Task<Void, Never>] = [:]
    private var shownAlertIds: Set<String> = []
    private var hasLoadedAlertHistory = false
    private var connectionTestTask: Task<ConnectionTestResult, Never>?
    private var connectionTestToken = 0

    private static let maxVisibleToasts = 3
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
        cancelConnectionTest()
        syncEngine?.cancelAll()
        syncEngine?.onEvent = nil
        syncEngine = nil
        transport.shutdown()
    }

    // MARK: - Loading

    private var activeStore: OverplayStore? {
        isDemo ? demoStore : realStore
    }

    @discardableResult
    private func openRealStoreIfNeeded() -> Bool {
        if let realStore {
            if syncEngine == nil {
                let engine = SyncEngine(
                    store: realStore,
                    credentials: credentials,
                    transport: transport,
                    settings: settings
                )
                syncEngine = engine
                configureEngineCallbacks()
            } else {
                syncEngine?.updateSettings(settings)
            }
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
            if let accountId = overviewAccountFilter,
               !loadedAccounts.contains(where: {
                   $0.id == accountId && (overviewPlatformFilter == nil || $0.provider == overviewPlatformFilter)
               }) {
                overviewAccountFilter = nil
            }
            let activeIds = Set(loadedAccounts.map(\.id))
            let previousAlertIds = Set(alerts.map(\.id))
            let loadedAlerts = try store.alerts().filter { activeIds.contains($0.accountId) }
            alerts = loadedAlerts
            handleLoadedAlerts(loadedAlerts, previousIds: previousAlertIds)
            if let selectedCurrency,
               !availableCurrencies.isEmpty,
               !availableCurrencies.contains(selectedCurrency) {
                self.selectedCurrency = nil
            }
            validateUsageFilters()
            ensureBalanceCurrencyFilter()
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
        case .cancelled(let accountId):
            syncingAccountIds.remove(accountId)
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
        if !syncEngine.startManualRefresh(account: account) {
            showBanner("该账户正在同步中，请等待当前请求结束", style: .info)
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
        let started = enabled.filter { syncEngine.startManualRefresh(account: $0) }.count
        if started == 0 {
            showBanner("所有账户都在同步中，请等待当前请求结束", style: .info)
        } else {
            showBanner("已开始刷新 \(started) 个账户", style: .info)
        }
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
        cancelConnectionTest()
        do {
            syncEngine?.cancel(accountId: account.id)
            syncingAccountIds.remove(account.id)
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
        cancelConnectionTest()
        connectionTestToken += 1
        let token = connectionTestToken
        let credential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let transport = URLSessionTransport()
        let task = Task {
            let connector = ConnectorFactory.make(for: provider, transport: transport)
            let result = await connector.testConnection(credential: credential, now: Date())
            transport.shutdown()
            return result
        }
        connectionTestTask = task
        let result = await task.value
        if connectionTestToken == token {
            connectionTestTask = nil
        }
        return result
    }

    private func cancelConnectionTest() {
        connectionTestTask?.cancel()
        connectionTestTask = nil
        connectionTestToken += 1
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
        let accountCurrencies = Set(balanceCurrencies(for: account))
        if !accountCurrencies.isEmpty, !accountCurrencies.contains(currency) {
            throw AppActionError.currencyMismatch(accountCurrencies.sorted().joined(separator: " / "))
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

    private func ensureBalanceCurrencyFilter() {
        let available = availableBalanceCurrencies
        if available.isEmpty {
            if balanceCurrencyFilter != nil {
                balanceCurrencyFilter = nil
            }
            return
        }
        if let balanceCurrencyFilter, available.contains(balanceCurrencyFilter) {
            return
        }
        balanceCurrencyFilter = available.contains("CNY") ? "CNY" : available.first
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

    var overviewUsageRecords: [UsageRecord] {
        if let selectedOverviewAccount {
            return usageRecords.filter { $0.accountId == selectedOverviewAccount.id }
        }
        guard let overviewPlatformFilter else { return usageRecords }
        if overviewPlatformFilter == .deepseek { return [] }
        return usageRecords.filter { $0.provider == overviewPlatformFilter }
    }

    var todayCosts: [String: Decimal] {
        let today = CalendarDay.string(for: now, timeZone: CalendarDay.utc)
        return costs(overviewUsageRecords.filter { $0.day == today })
    }

    var monthCosts: [String: Decimal] {
        let (_, range) = CalendarDay.monthRange(now: now)
        return costs(overviewUsageRecords.filter { range.contains($0.day) })
    }

    var tokenSummary: (total: Int, totalAccounts: Int, providersWithTokens: Int) {
        let range = CalendarDay.range(preset: .thirty, now: now)
        let records = overviewUsageRecords.filter { range.contains($0.day) }
        let total = records.reduce(0) { $0 + ($1.totalTokens ?? 0) }
        let providers = Set(records.filter { $0.totalTokens != nil }.map(\.accountId)).count
        let totalAccounts = overviewAccountsToShow.count
        return (total, totalAccounts, providers)
    }

    var officialCreditsRemaining: [String: Decimal] {
        if let selectedOverviewAccount {
            guard selectedOverviewAccount.provider == .openrouter,
                  let quota = quotas[selectedOverviewAccount.id] else { return [:] }
            return [quota.currency: quota.remaining]
        }
        guard overviewPlatformFilter != .deepseek else { return [:] }
        var result: [String: Decimal] = [:]
        for account in accounts where account.enabled && account.provider == .openrouter {
            guard let quota = quotas[account.id] else { continue }
            result[quota.currency, default: 0] += quota.remaining
        }
        return result
    }

    var balanceAccounts: [Account] {
        accounts.filter { $0.provider == .deepseek }
    }

    var overviewPlatformAccounts: [Account] {
        guard let overviewPlatformFilter else { return accounts }
        return accounts.filter { $0.provider == overviewPlatformFilter }
    }

    var selectedOverviewAccount: Account? {
        guard let overviewAccountFilter else { return nil }
        return accounts.first { $0.id == overviewAccountFilter }
    }

    var overviewAccountsToShow: [Account] {
        if let selectedOverviewAccount { return [selectedOverviewAccount] }
        return overviewPlatformAccounts
    }

    var availableBalanceCurrencies: [String] {
        if let selectedOverviewAccount {
            return selectedOverviewAccount.provider == .deepseek
                ? balanceCurrencies(for: selectedOverviewAccount)
                : []
        }
        guard overviewPlatformFilter != .openrouter else { return [] }
        let codes = activeDeepSeekAccounts.flatMap { balanceCurrencies(for: $0) }
        return Array(Set(codes)).sorted()
    }

    var officialBalances: [String: Decimal] {
        if let selectedOverviewAccount {
            guard selectedOverviewAccount.provider == .deepseek else { return [:] }
            let totals = BalanceSummary.totalsByCurrency(
                balances: balances,
                accountIds: [selectedOverviewAccount.id]
            )
            guard let balanceCurrencyFilter else { return [:] }
            return totals.filter { $0.key == balanceCurrencyFilter }
        }
        guard overviewPlatformFilter != .openrouter else { return [:] }
        let ids = Set(activeDeepSeekAccounts.map(\.id))
        let totals = BalanceSummary.totalsByCurrency(balances: balances, accountIds: ids)
        guard let balanceCurrencyFilter else { return [:] }
        return totals.filter { $0.key == balanceCurrencyFilter }
    }

    func balanceCurrencies(for account: Account) -> [String] {
        BalanceSummary.currencies(for: latestBalances(for: account))
    }

    func currencyLabel(for account: Account) -> String {
        switch account.provider {
        case .deepseek:
            let currencies = balanceCurrencies(for: account)
            if currencies.isEmpty {
                return account.lastSuccessAt == nil ? "币种待同步" : "币种未知"
            }
            return currencies.joined(separator: " / ")
        case .openrouter:
            return latestQuota(for: account)?.currency ?? account.provider.defaultCurrency
        }
    }

    var openRouterAccounts: [Account] {
        accounts.filter { $0.provider == .openrouter }
    }

    var activeDeepSeekAccounts: [Account] {
        balanceAccounts.filter(\.enabled)
    }

    func accountAbnormalReason(for account: Account) -> String? {
        guard account.provider == .deepseek else { return nil }
        let unavailable = latestBalances(for: account).filter { $0.isAvailable == false }
        guard !unavailable.isEmpty else { return nil }
        let codes = unavailable.map(\.currency).sorted().joined(separator: " / ")
        return "DeepSeek 官方标记 \(codes) 余额不可用；请检查账户状态（欠费、风控或权限）"
    }

    func dataIssue(for account: Account) -> String? {
        var reasons: [String] = []
        if account.credentialInvalid {
            reasons.append("凭据失效：\(account.lastError ?? "需要重新输入 API Key / Management Key")")
        } else if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !error.isEmpty {
            reasons.append("同步失败：\(error)")
        }
        if let abnormal = accountAbnormalReason(for: account) {
            reasons.append("账户异常：\(abnormal)")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "；")
    }

    private func openRouterDataStatus() -> DataStatus {
        if openRouterAccounts.isEmpty {
            return .missing("暂无 OpenRouter 账户；DeepSeek 官方不提供历史费用 / 用量接口")
        }
        let enabled = openRouterAccounts.filter(\.enabled)
        if enabled.isEmpty {
            return .missing("OpenRouter 账户均已禁用；0 仅为占位")
        }
        let issues = enabled.compactMap { dataIssue(for: $0) }
        if !issues.isEmpty {
            return .anomaly(issues.joined(separator: "；"))
        }
        let unsynced = enabled.filter { $0.lastSuccessAt == nil }
        if unsynced.count == enabled.count {
            return .missing("OpenRouter 尚未成功同步；0 仅为占位，不代表真实消费")
        }
        if !unsynced.isEmpty {
            return .anomaly(
                "\(unsynced.map(\.displayName).joined(separator: "、")) 尚未成功同步，当前汇总可能不完整"
            )
        }
        return .actual
    }

    private func overviewOpenRouterDataStatus() -> DataStatus {
        if let selectedOverviewAccount {
            switch selectedOverviewAccount.provider {
            case .deepseek:
                return .missing("所选账户为 DeepSeek，不提供历史费用 / 用量；0 仅为占位")
            case .openrouter:
                if let issue = dataIssue(for: selectedOverviewAccount) { return .anomaly(issue) }
                if !selectedOverviewAccount.enabled { return .missing("该账户已禁用；0 仅为占位") }
                if selectedOverviewAccount.lastSuccessAt == nil {
                    return .missing("该账户尚未成功同步；0 仅为占位")
                }
                return .actual
            }
        }
        if overviewPlatformFilter == .deepseek {
            return .missing("DeepSeek 平台不提供历史费用 / 用量；0 仅为占位")
        }
        return openRouterDataStatus()
    }

    func costDataStatus(forToday: Bool) -> DataStatus {
        let base = overviewOpenRouterDataStatus()
        guard case .actual = base else { return base }
        let values = forToday ? todayCosts : monthCosts
        guard values.isEmpty else { return .actual }
        if forToday {
            return .missing("OpenRouter 官方活动窗口仅覆盖完整 UTC 日，今日数据将在下一 UTC 日回填；0 仅为占位")
        }
        return .missing("本机自然月内暂无 OpenRouter activity 费用记录，可能不含今天或超出约 30 天窗口；0 仅为占位")
    }

    func tokenDataStatus() -> DataStatus {
        let base = overviewOpenRouterDataStatus()
        guard case .actual = base else { return base }
        if tokenSummary.providersWithTokens == 0 {
            return .missing("所选范围没有可用的 token 数据；DeepSeek 官方不提供历史 token，OpenRouter 仅覆盖约 30 个 UTC 日；0 仅为占位")
        }
        return .actual
    }

    func creditDataStatus() -> DataStatus {
        if let selectedOverviewAccount {
            if selectedOverviewAccount.provider == .deepseek {
                return .missing("所选账户为 DeepSeek，不提供 credits；0 仅为占位")
            }
            return creditDataStatus(for: selectedOverviewAccount)
        }
        if overviewPlatformFilter == .deepseek {
            return .missing("DeepSeek 平台不提供 credits；0 仅为占位")
        }
        if openRouterAccounts.isEmpty {
            return .missing("暂无 OpenRouter 账户；0 仅为占位")
        }
        let enabled = openRouterAccounts.filter(\.enabled)
        if enabled.isEmpty {
            return .missing("OpenRouter 账户均已禁用；0 仅为占位")
        }
        let issues = enabled.compactMap { dataIssue(for: $0) }
        if !issues.isEmpty {
            return .anomaly(issues.joined(separator: "；"))
        }
        let unsynced = enabled.filter { $0.lastSuccessAt == nil }
        let withQuota = enabled.filter { latestQuota(for: $0) != nil }
        if withQuota.isEmpty {
            if unsynced.count == enabled.count {
                return .missing("OpenRouter 尚未成功同步 credits；0 仅为占位")
            }
            return .missing("厂商未返回 credits 数据；0 仅为占位")
        }
        let missing = enabled.filter { latestQuota(for: $0) == nil }
        if !missing.isEmpty {
            return .anomaly(
                "\(missing.map(\.displayName).joined(separator: "、")) 尚未返回 credits，汇总可能不完整"
            )
        }
        return .actual
    }

    func creditDataStatus(for account: Account) -> DataStatus {
        if let issue = dataIssue(for: account) { return .anomaly(issue) }
        if latestQuota(for: account) == nil {
            if !account.enabled { return .missing("该账户已禁用；0 仅为占位") }
            if account.lastSuccessAt == nil { return .missing("该账户尚未成功同步 credits；0 仅为占位") }
            return .missing("该账户厂商未返回 credits 数据；0 仅为占位")
        }
        return .actual
    }

    func balanceDataStatus(for account: Account? = nil) -> DataStatus {
        if let account {
            if let issue = dataIssue(for: account) { return .anomaly(issue) }
            if latestBalances(for: account).isEmpty {
                if !account.enabled { return .missing("该账户已禁用；0 仅为占位") }
                if account.lastSuccessAt == nil { return .missing("该账户尚未成功同步余额；0 仅为占位") }
                return .missing("该账户厂商未返回余额数据；0 仅为占位")
            }
            return .actual
        }
        if balanceAccounts.isEmpty {
            return .missing("暂无 DeepSeek 账户；0 仅为占位")
        }
        let enabled = activeDeepSeekAccounts
        if enabled.isEmpty {
            return .missing("DeepSeek 账户均已禁用；0 仅为占位")
        }
        let issues = enabled.compactMap { dataIssue(for: $0) }
        if !issues.isEmpty {
            return .anomaly(issues.joined(separator: "；"))
        }
        let withBalances = enabled.filter { !latestBalances(for: $0).isEmpty }
        if withBalances.isEmpty {
            let unsynced = enabled.filter { $0.lastSuccessAt == nil }
            if unsynced.count == enabled.count {
                return .missing("DeepSeek 尚未成功同步余额；0 仅为占位")
            }
            return .missing("厂商未返回余额数据；0 仅为占位")
        }
        let missing = enabled.filter { latestBalances(for: $0).isEmpty }
        if !missing.isEmpty {
            return .anomaly(
                "\(missing.map(\.displayName).joined(separator: "、")) 尚未返回余额，汇总可能不完整"
            )
        }
        return .actual
    }

    func budgetSpendDataStatus(for account: Account) -> DataStatus {
        guard account.budget != nil else { return .missing("未设置本地预算；0 仅为占位") }
        if let issue = dataIssue(for: account) { return .anomaly(issue) }
        if budgetSpend(for: account) == nil {
            return .anomaly("预算已设置，但本月 activity 数据不完整，暂不能计算使用量；0 仅为占位")
        }
        return .actual
    }

    func budgetRemainingDataStatus() -> DataStatus {
        let budgetAccounts: [Account]
        if let selectedOverviewAccount {
            guard selectedOverviewAccount.budget != nil else {
                return .missing("所选账户没有本地预算；0 仅为占位")
            }
            budgetAccounts = [selectedOverviewAccount]
        } else {
            if overviewPlatformFilter == .deepseek {
                return .missing("DeepSeek 平台没有本地预算；0 仅为占位")
            }
            budgetAccounts = accounts.filter {
                (overviewPlatformFilter == nil || $0.provider == overviewPlatformFilter) && $0.budget != nil
            }
        }
        if budgetAccounts.isEmpty {
            return .missing("未设置本地预算；0 仅为占位")
        }
        let issues = budgetAccounts.compactMap { dataIssue(for: $0) }
        if !issues.isEmpty {
            return .anomaly(issues.joined(separator: "；"))
        }
        let missing = budgetAccounts.filter { budgetRemaining(for: $0) == nil }
        if missing.count == budgetAccounts.count {
            return .anomaly("预算已设置，但本月用量数据不完整，暂不能计算剩余；0 仅为占位")
        }
        if !missing.isEmpty {
            return .anomaly(
                "\(missing.map(\.displayName).joined(separator: "、")) 缺少完整本月用量，剩余汇总可能不完整"
            )
        }
        return .actual
    }

    func usageDataStatus() -> DataStatus {
        let base = openRouterDataStatus()
        if case .anomaly = base { return base }
        if hasUsageFilters, !unfilteredRecords.isEmpty { return .actual }
        guard case .actual = base else { return base }
        if unfilteredRecords.isEmpty {
            return .missing("所选范围没有 OpenRouter activity 记录；DeepSeek 官方不提供历史用量；0 仅为占位")
        }
        return .actual
    }

    func budgetSpend(for account: Account) -> Decimal? {
        let (_, range) = CalendarDay.monthRange(now: now)
        return BudgetMath.availableSpend(
            account: account,
            records: usageRecords,
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
        if accountAbnormalReason(for: account) != nil { return .accountAbnormal }
        if account.consecutiveFailures > 0 { return .failed }
        if let lastSuccess = account.lastSuccessAt {
            if now.timeIntervalSince(lastSuccess) > settings.refreshInterval * 2 { return .stale }
            if account.lastError != nil { return .partial }
            switch account.provider {
            case .deepseek where latestBalances(for: account).isEmpty:
                return .connectedNoData
            case .openrouter where latestQuota(for: account) == nil:
                return .connectedNoData
            default:
                return .healthy
            }
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
        if accountAbnormalReason(for: account) != nil {
            return "账户异常 · 官方标记余额不可用"
        }
        guard account.lastSuccessAt != nil else {
            if account.lastError != nil { return "能力未验证（同步失败）" }
            return "等待连接测试"
        }
        if account.lastError != nil {
            switch account.provider {
            case .deepseek:
                return latestBalances(for: account).isEmpty
                    ? "同步异常 · 余额不可用"
                    : "部分成功"
            case .openrouter:
                return latestQuota(for: account) == nil
                    ? "同步异常 · credits 不可用"
                    : "credits 可用；用量接口暂时不可用"
            }
        }
        switch account.provider {
        case .deepseek:
            if latestBalances(for: account).isEmpty {
                return "厂商未返回余额"
            }
            return "余额可用 · 官方无历史用量 / 费用"
        case .openrouter:
            if latestQuota(for: account) == nil {
                return "厂商未返回 credits"
            }
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
            toastQueue.removeAll { $0.alertId == alert.id }
            toasts.filter { $0.alertId == alert.id }.forEach { dismissToast($0.id) }
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
            cancelConnectionTest()
            syncEngine?.cancelAll()
            syncEngine?.onEvent = nil
            syncEngine = nil
            realStore = nil
            transport = URLSessionTransport()
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
            overviewPlatformFilter = nil
            overviewAccountFilter = nil
            balanceCurrencyFilter = nil
            resetToastState()
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
        overviewPlatformFilter = nil
        overviewAccountFilter = nil
        balanceCurrencyFilter = nil
        resetToastState()
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
        cancelConnectionTest()
        for account in accounts {
            syncEngine?.cancel(accountId: account.id)
        }
        syncEngine?.cancelAll()
        syncEngine?.onEvent = nil
        syncEngine = nil
        transport.shutdown()
        var errors: [String] = []
        do { try credentials.deleteAll() } catch {
            errors.append("凭证删除失败：\(error.localizedDescription)")
        }
        do { try realStore.clearAllData() } catch {
            errors.append("数据库清理失败：\(error.localizedDescription)")
        }
        notifications.clearDelivered()
        UserDefaults.standard.removeObject(forKey: Self.demoFlagKey)
        UserDefaults.standard.removeObject(forKey: Self.demoDisclaimerKey)
        selectedTab = .overview
        selectedCurrency = nil
        overviewPlatformFilter = nil
        overviewAccountFilter = nil
        balanceCurrencyFilter = nil
        resetToastState()
        syncingAccountIds.removeAll()
        settings = AppSettings()
        transport = URLSessionTransport()
        _ = openRealStoreIfNeeded()
        syncEngine?.updateSettings(settings)
        reloadFromStore()
        showOnboarding = true
        if errors.isEmpty {
            showBanner("已清除账户、凭证、历史用量、告警记录与设置", style: .success)
        } else {
            showBanner(errors.joined(separator: "；"), style: .error)
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

    private func handleLoadedAlerts(_ loaded: [AlertEvent], previousIds: Set<String>) {
        let loadedIds = Set(loaded.map(\.id))
        toastQueue.removeAll { toast in
            guard let alertId = toast.alertId else { return false }
            return !loadedIds.contains(alertId)
        }
        let staleToastIds = toasts.compactMap { toast -> String? in
            guard let alertId = toast.alertId, !loadedIds.contains(alertId) else { return nil }
            return toast.id
        }
        staleToastIds.forEach(dismissToast)

        let unacknowledged = loaded.filter { !$0.acknowledged }
        if !hasLoadedAlertHistory {
            hasLoadedAlertHistory = true
            guard isDemo else { return }
            enqueueAlertToasts(unacknowledged)
            return
        }
        let newAlerts = unacknowledged.filter { !previousIds.contains($0.id) }
        enqueueAlertToasts(newAlerts)
    }

    private func enqueueAlertToasts(_ alerts: [AlertEvent]) {
        guard !alerts.isEmpty else { return }
        for alert in alerts.sorted(by: { $0.firedAt > $1.firedAt }) {
            guard !shownAlertIds.contains(alert.id) else { continue }
            shownAlertIds.insert(alert.id)
            let style = toastStyle(for: alert.kind)
            enqueueToast(ToastMessage(
                id: "alert-\(alert.id)",
                title: alert.kind.title,
                message: "\(alert.accountName) · 当前 \(alert.value) · 阈值 \(alert.threshold)",
                style: style,
                alertId: alert.id,
                isDemo: alert.isDemo,
                duration: 8,
                expiresAt: nil,
                autoDismiss: style != .error
            ))
        }
    }

    private func toastStyle(for kind: AlertKind) -> BannerStyle {
        switch kind {
        case .budgetExceeded, .balanceLow, .credentialInvalid, .syncFailed:
            return .error
        case .budgetWarning:
            return .info
        case .dataStale:
            return .warning
        }
    }

    private func bannerTitle(for style: BannerStyle) -> String {
        switch style {
        case .info: return "提示"
        case .success: return "成功"
        case .warning: return "提示"
        case .error: return "错误"
        }
    }

    private func enqueueToast(_ toast: ToastMessage) {
        if toast.style == .error {
            toastQueue.insert(toast, at: 0)
        } else {
            toastQueue.append(toast)
        }
        pumpToasts()
    }

    private func pumpToasts() {
        while toasts.count < Self.maxVisibleToasts, !toastQueue.isEmpty {
            var toast = toastQueue.removeFirst()
            if toast.autoDismiss {
                toast.expiresAt = Date().addingTimeInterval(toast.duration)
            }
            toasts.append(toast)
            if toast.autoDismiss {
                scheduleExpiry(for: toast)
            }
        }
    }

    private func scheduleExpiry(for toast: ToastMessage) {
        toastTasks[toast.id]?.cancel()
        toastTasks[toast.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expireToast(toast.id)
        }
    }

    private func expireToast(_ id: String) {
        guard toasts.contains(where: { $0.id == id }) else { return }
        toasts.removeAll { $0.id == id }
        toastTasks[id]?.cancel()
        toastTasks.removeValue(forKey: id)
        pumpToasts()
    }

    func dismissToast(_ id: String) {
        toasts.removeAll { $0.id == id }
        toastTasks[id]?.cancel()
        toastTasks.removeValue(forKey: id)
        pumpToasts()
    }

    func dismissAllToasts() {
        toastTasks.values.forEach { $0.cancel() }
        toastTasks.removeAll()
        toasts.removeAll()
        toastQueue.removeAll()
    }

    private func resetToastState() {
        dismissAllToasts()
        shownAlertIds.removeAll()
        hasLoadedAlertHistory = false
    }

    func showBanner(_ message: String, style: BannerStyle) {
        enqueueToast(ToastMessage(
            id: "banner-\(UUID().uuidString)",
            title: bannerTitle(for: style),
            message: message,
            style: style,
            alertId: nil,
            isDemo: isDemo,
            duration: style == .error ? 8 : style == .warning ? 7 : 5,
            expiresAt: nil,
            autoDismiss: style != .error
        ))
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
