import AppKit
import Combine
import Foundation
import UserNotifications
import OverplayCore

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case usage
    case quota
    case addProvider
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L10n.t("dashboard.overview")
        case .usage: return L10n.t("dashboard.usage")
        case .quota: return L10n.t("dashboard.quota")
        case .addProvider: return L10n.t("dashboard.addProvider")
        case .settings: return L10n.t("dashboard.settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .usage: return "chart.bar.xaxis"
        case .quota: return "gauge.with.dots.needle.50percent"
        case .addProvider: return "plus.rectangle.on.rectangle"
        case .settings: return "gearshape"
        }
    }
}

typealias BannerStyle = NoticeStyle

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
    case duplicateAccount
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .demoReadOnly: return L10n.t("app.cce1d224b1")
        case .emptyName: return L10n.t("app.5e146caa0a")
        case .emptyKey: return L10n.t("app.86d07b5fd4")
        case .invalidAmount: return L10n.t("app.4bf9dc1327")
        case .currencyMismatch(let currencies):
            return L10n.f("app.324c1f016d", currencies)
        case .duplicateAccount:
            return L10n.t("app.b1c29cc952")
        case .storage(let message): return message
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    @Published var rangePreset: AnalysisRangePreset = .last30Days {
        didSet { validateUsageFilters() }
    }
    @Published var customRangeStart = Date().addingTimeInterval(-7 * 86_400)
    @Published var customRangeEnd = Date()
    @Published var selectedGranularity: AnalysisGranularity = .automatic
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
    @Published var selectedProviderDetailAccountId: String?
    @Published var providerDetailVisible = false
    @Published var providerFormResetToken = UUID()
    @Published var debugDeleteAccountId: String?
    @Published var debugAlertLineAccountId: String?
    @Published var debugEditAccountId: String?
    @Published var showMessageCenter = false
    @Published var hasUnsavedChanges = false
    @Published private(set) var selectedLanguageIdentifier = AppLanguage.system.rawValue
    @Published private(set) var languageOptions: [LocalizedLanguage] = []
    @Published private(set) var localizationRevision = UUID()

    var onStatusChanged: (() -> Void)?

    private let databaseURL: URL
    private let credentials: KeychainCredentialStore
    private let notifications = NotificationManager()
    private let requestCounter: NetworkRequestCounter
    private var realStore: OverplayStore?
    private var demoStore: OverplayStore?
    private var syncEngine: SyncEngine?
    private var transport: HTTPTransport
    private(set) var refreshInvocationCount = 0
    private var timer: Timer?
    private var toastQueue = ToastQueue(maxVisible: 3)
    private var toastTasks: [String: Task<Void, Never>] = [:]
    private var shownAlertIds: Set<String> = []
    private var hasLoadedAlertHistory = false
    private var connectionTestTask: Task<ConnectionTestResult, Never>?
    private var connectionTestToken = 0

    private static let demoFlagKey = "overplay.demoMode"
    private static let demoDisclaimerKey = "overplay.demoDisclaimerAccepted"
    private static let languageKey = "overplay.language"

    init(dataDirectory: URL? = nil, forceDemo: Bool = false) {
        let directory = dataDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Overplay", isDirectory: true)
        self.databaseURL = directory.appendingPathComponent("overplay.sqlite")
        self.credentials = KeychainCredentialStore()
        let counter = NetworkRequestCounter()
        self.requestCounter = counter
        self.transport = RequestCountingTransport(
            base: URLSessionTransport(),
            counter: counter
        )

        let defaults = UserDefaults.standard
        let persistedDemo = defaults.bool(forKey: Self.demoFlagKey)
            && defaults.bool(forKey: Self.demoDisclaimerKey)
        if forceDemo || persistedDemo {
            if let demo = try? DemoData.makeStore() {
                demoStore = demo
                isDemo = true
            } else {
                initializationWarning = L10n.t("app.a46f3b95b7")
            }
        }
        if isDemo {
            settings = (try? demoStore?.settings()) ?? AppSettings()
        } else {
            openRealStoreIfNeeded()
        }
        loadLanguagePreference()
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

    private func makeTransport() -> HTTPTransport {
        RequestCountingTransport(base: URLSessionTransport(), counter: requestCounter)
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
                initializationWarning = L10n.f("app.aed83cf132", L10n.t(error.localizedDescription))
            } catch {
                initializationWarning = L10n.f("app.e066b3d4ed", L10n.t(error.localizedDescription))
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
            let retentionStart = Calendar.current.date(byAdding: .day, value: -365, to: now)
                ?? now.addingTimeInterval(-365 * 86_400)
            let historyRange = (try? AnalysisRange.make(
                preset: .custom,
                customStart: retentionStart,
                customEnd: now,
                now: now
            ))?.dayRange ?? CalendarDay.range(preset: .ninety, now: now)
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
            let range = historyRange
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
            showBanner(L10n.f("app.d8129eb99d", L10n.t(error.localizedDescription)), style: .error)
        }
        updateMenuBar()
    }

    func refreshNotificationStatus() async {
        var status = await notifications.authorizationStatus()
        if status == .notDetermined, !isDemo, settings.notificationsEnabled {
            status = await notifications.requestAuthorizationIfNeeded()
        }
        notificationStatus = status
        guard status == .denied, settings.notificationsEnabled else { return }
        var updated = settings
        updated.notificationsEnabled = false
        if let store = activeStore {
            try? store.saveSettings(updated)
        }
        settings = updated
        showBanner(L10n.t("app.notificationDeniedSetting"), style: .warning)
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
                showBanner("\(outcome.error ?? L10n.t("alert.credentialInvalid.title"))", style: .warning)
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

    var networkRequestCount: Int {
        requestCounter.count
    }

    func refresh(account: Account) {
        refreshInvocationCount += 1
        guard !isDemo else {
            showBanner(L10n.t("app.d92930761a"), style: .info)
            return
        }
        guard account.enabled else {
            showBanner(L10n.t("app.a0611669ad"), style: .info)
            return
        }
        if let reason = refreshBlockedReason(for: account) {
            showBanner(reason, style: .warning)
            return
        }
        guard let syncEngine else { return }
        if !syncEngine.startManualRefresh(account: account) {
            showBanner(L10n.t("app.e4336a9db8"), style: .info)
        }
    }

    func refreshAll() {
        refreshInvocationCount += 1
        guard !isDemo else {
            showBanner(L10n.t("app.d92930761a"), style: .info)
            return
        }
        let enabled = accounts.filter(\.enabled)
        guard !enabled.isEmpty else {
            showBanner(L10n.t("app.b6a3693bf9"), style: .info)
            return
        }
        guard let syncEngine else { return }
        lastRefreshAllAt = Date()
        let started = enabled.filter { syncEngine.startManualRefresh(account: $0) }.count
        if started == 0 {
            showBanner(L10n.t("app.a3365bf87d"), style: .info)
        } else {
            showBanner(L10n.f("app.a93ac6a57a", started), style: .info)
        }
    }

    func isSyncing(_ account: Account) -> Bool {
        syncingAccountIds.contains(account.id)
    }

    func refreshBlockedReason(for account: Account) -> String? {
        syncEngine?.manualRefreshBlockedReason(accountId: account.id, now: now)
    }

    func isRefreshCoolingDown(_ account: Account) -> Bool {
        refreshBlockedReason(for: account) != nil
    }

    /// 仅用于演示模式截图 / UI 验证，不会发起请求或写入真实数据。
    func injectDemoRefreshFailure(accountId: String?) {
        guard isDemo, let accountId,
              let index = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        accounts[index].lastError = L10n.t("app.3be09f2023")
        accounts[index].consecutiveFailures = 1
    }

    // MARK: - Account management

    func saveNewAccount(
        provider: ProviderKind,
        name: String,
        apiKey: String,
        officialName: String? = nil,
        iconName: String? = nil,
        genericConfig: GenericHTTPConfig? = nil,
        alertConfig: AccountAlertConfig? = nil
    ) throws -> Account {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage(L10n.t("app.90d3af5ba0")) }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = try AccountInputValidator.validateNewAccount(
            provider: provider,
            name: name,
            credential: trimmedKey,
            genericConfig: genericConfig,
            existingAccounts: accounts
        )
        let account = Account(
            provider: provider,
            name: resolvedName,
            isDemo: false,
            officialName: officialName?.nilIfBlank,
            iconName: AccountIconCatalog.normalized(iconName),
            genericConfig: genericConfig,
            alertConfig: alertConfig ?? .off
        )
        try credentials.setCredential(trimmedKey, accountId: account.id)
        do {
            try realStore.insertAccount(account)
        } catch {
            try? credentials.deleteCredential(accountId: account.id)
            throw AppActionError.storage(L10n.f("app.bef66819c9", L10n.t(error.localizedDescription)))
        }
        reloadFromStore()
        syncEngine?.resetSchedule(accountId: account.id)
        if let refreshed = accounts.first(where: { $0.id == account.id }) {
            refresh(account: refreshed)
        }
        showBanner(L10n.f("app.14ccf36645", account.displayName), style: .success)
        return account
    }

    func updateAccount(
        _ account: Account,
        name: String,
        newAPIKey: String?,
        officialName: String? = nil,
        iconName: String? = nil,
        genericConfig: GenericHTTPConfig? = nil,
        alertConfig: AccountAlertConfig? = nil
    ) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage(L10n.t("app.90d3af5ba0")) }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? account.provider.displayName : trimmedName
        if accounts.contains(where: {
            $0.id != account.id && $0.provider == account.provider
                && $0.displayName.caseInsensitiveCompare(resolvedName) == .orderedSame
        }) {
            throw AppActionError.duplicateAccount
        }
        let resolvedGeneric = genericConfig ?? account.genericConfig
        if account.provider == .genericHTTP, let resolvedGeneric {
            _ = try resolvedGeneric.requestURL()
        }
        let profile = OverplayStore.AccountProfile(
            officialName: officialName.map { $0.nilIfBlank } ?? account.officialName,
            iconName: iconName.map { AccountIconCatalog.normalized($0) } ?? account.iconName,
            genericConfig: resolvedGeneric,
            alertConfig: alertConfig ?? account.alertConfig
        )
        try realStore.updateAccountProfile(id: account.id, name: resolvedName, profile: profile)
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
        showBanner(L10n.t("app.f407e6d344"), style: .success)
    }

    func savePublicAlertConfig(_ config: PublicAlertConfig) {
        guard !isDemo else { return }
        var updated = settings
        updated.publicAlertConfig = config
        guard let store = activeStore else { return }
        do {
            try store.saveSettings(updated)
            settings = updated
            syncEngine?.updateSettings(updated)
            for account in accounts {
                guard let config = account.alertConfig else { continue }
                for (severity, rule) in [("warning", config.warning), ("critical", config.critical)]
                where rule.mode == .followPublic && rule.metric.usesPercent {
                    try? store.deleteAlertStates(
                        like: "line:\(account.id):\(severity):\(rule.metric.rawValue):%"
                    )
                }
            }
            evaluateAndReloadAlerts()
            showBanner(L10n.t("app.49f7ea146e"), style: .success)
        } catch {
            showBanner(L10n.f("app.7d24b91ec0", L10n.t(error.localizedDescription)), style: .error)
        }
    }

    func saveAccountAlertConfig(_ account: Account, config: AccountAlertConfig) {
        guard !isDemo else {
            showBanner(L10n.t("app.25085a984a"), style: .info)
            return
        }
        guard let store = activeStore else { return }
        do {
            var profile = try store.accountProfile(accountId: account.id)
                ?? OverplayStore.AccountProfile()
            profile.alertConfig = config
            try store.saveAccountProfile(accountId: account.id, profile: profile)
            try? store.deleteAlertStates(like: "line:\(account.id):%")
            reloadFromStore()
            evaluateAndReloadAlerts()
            showBanner(L10n.t("app.c7f21a9e7b"), style: .success)
        } catch {
            showBanner(L10n.f("app.b744c0cb74", L10n.t(error.localizedDescription)), style: .error)
        }
    }

    func setAccountEnabled(_ account: Account, enabled: Bool) {
        guard !isDemo else {
            showBanner(L10n.t("app.e7e2cc04f7"), style: .info)
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
            showBanner(L10n.f("app.8900ae3902", L10n.t(error.localizedDescription)), style: .error)
        }
    }

    func deleteAccount(_ account: Account, removeHistory: Bool) {
        guard !isDemo else {
            showBanner(L10n.t("app.7706a15cb9"), style: .info)
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
                removeHistory ? L10n.t("app.a244cfb7c3") : L10n.t("app.87c6a95777"),
                style: .success
            )
        } catch {
            showBanner(L10n.f("app.461fd2bb32", L10n.t(error.localizedDescription)), style: .error)
        }
    }

    func testConnection(
        provider: ProviderKind,
        apiKey: String,
        genericConfig: GenericHTTPConfig? = nil
    ) async -> ConnectionTestResult {
        cancelConnectionTest()
        connectionTestToken += 1
        let token = connectionTestToken
        let credential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let transport = URLSessionTransport()
        let task = Task {
            let connector = ConnectorFactory.make(
                for: provider,
                transport: transport,
                genericConfig: genericConfig
            )
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
        guard let realStore else { throw AppActionError.storage(L10n.t("app.90d3af5ba0")) }
        guard let amount = Money.parse(amountText), amount > 0 else {
            throw AppActionError.invalidAmount
        }
        try realStore.setBudget(
            accountId: account.id,
            budget: Budget(amount: amount, currency: currency)
        )
        reloadFromStore()
        evaluateAndReloadAlerts()
        showBanner(L10n.t("app.cec864b86a"), style: .success)
    }

    func clearBudget(account: Account) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage(L10n.t("app.90d3af5ba0")) }
        try realStore.setBudget(accountId: account.id, budget: nil)
        reloadFromStore()
        showBanner(L10n.t("app.603b334e22"), style: .success)
    }

    func saveThreshold(account: Account, amountText: String, currency: String) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage(L10n.t("app.90d3af5ba0")) }
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
        showBanner(L10n.t("app.8480c2ad39"), style: .success)
    }

    func clearThreshold(account: Account) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        guard let realStore else { throw AppActionError.storage(L10n.t("app.90d3af5ba0")) }
        try realStore.setBalanceThreshold(accountId: account.id, threshold: nil)
        reloadFromStore()
        showBanner(L10n.t("app.df1bb175e4"), style: .success)
    }

    private func evaluateAndReloadAlerts() {
        _ = evaluatePeriodicAlerts()
    }

    // MARK: - Derived metrics

    var analysisRange: AnalysisRange {
        if let range = try? AnalysisRange.make(
            preset: rangePreset,
            customStart: customRangeStart,
            customEnd: customRangeEnd,
            now: now
        ) {
            return range
        }
        return AnalysisRange(
            preset: .last30Days,
            start: now.addingTimeInterval(-30 * 86_400),
            end: now,
            dayRange: CalendarDay.range(preset: .thirty, now: now),
            isCustom: false
        )
    }

    var analysisRangeError: AnalysisRangeError? {
        guard rangePreset == .custom else { return nil }
        do {
            _ = try AnalysisRange.make(
                preset: .custom,
                customStart: customRangeStart,
                customEnd: customRangeEnd,
                now: now
            )
            return nil
        } catch let error as AnalysisRangeError {
            return error
        } catch {
            return nil
        }
    }

    var currentRange: DayRange {
        analysisRange.dayRange
    }

    var unfilteredRecords: [UsageRecord] {
        usageRecords.filter { currentRange.contains($0.day) }
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

    var overviewScope: OverviewScope {
        OverviewScope(platform: overviewPlatformFilter, accountId: overviewAccountFilter)
    }

    private func ensureBalanceCurrencyFilter() {
        let available = availableBalanceCurrencies
        let preferred = BalanceCurrencyPolicy.preferred(
            options: available,
            current: balanceCurrencyFilter
        )
        if balanceCurrencyFilter != preferred {
            balanceCurrencyFilter = preferred
        }
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
        let scoped = overviewAccountsToShow.filter { $0.capabilities.usage }
        return DashboardMetrics.usageRecords(usageRecords, for: scoped)
    }

    var todayCosts: [String: Decimal] {
        let today = CalendarDay.string(for: now, timeZone: CalendarDay.utc)
        return DashboardMetrics.costs(overviewUsageRecords, onDay: today)
    }

    var monthCosts: [String: Decimal] {
        let (_, range) = CalendarDay.monthRange(now: now)
        return DashboardMetrics.costs(overviewUsageRecords, in: range)
    }

    var tokenSummary: (total: Int, totalAccounts: Int, providersWithTokens: Int) {
        let stats = DashboardMetrics.tokenStats(
            records: overviewUsageRecords,
            range: currentRange,
            totalAccounts: overviewAccountsToShow.count
        )
        return (stats.totalTokens, stats.totalAccounts, stats.accountsWithTokens)
    }

    var analysisAccounts: [Account] {
        overviewAccountsToShow
    }

    var analysisRecords: [UsageRecord] {
        let ids = Set(analysisAccounts.map(\.id))
        return unfilteredRecords.filter { ids.contains($0.accountId) }
    }

    func analysisRecords(for account: Account) -> [UsageRecord] {
        unfilteredRecords.filter { $0.accountId == account.id }
    }

    func providerTotals(for account: Account) -> ProviderUsageTotals {
        ProviderAnalysisMetrics.totals(records: unfilteredRecords, account: account)
    }

    var analysisProviderTotals: [(account: Account, totals: ProviderUsageTotals)] {
        analysisAccounts.map { ($0, providerTotals(for: $0)) }
    }

    var analysisTokenTotal: Int {
        analysisProviderTotals.reduce(0) { total, item in
            total + (item.totals.tokensAvailable ? item.totals.totalTokens : 0)
        }
    }

    var analysisCosts: [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for item in analysisProviderTotals {
            for (currency, value) in item.totals.costs {
                totals[currency, default: 0] += value
            }
        }
        return totals
    }

    var analysisRequestTotal: Int? {
        let values = analysisProviderTotals.compactMap { item in
            item.totals.requestsAvailable ? item.totals.requests : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var analysisTokenCoverage: TokenCoverage {
        ProviderAnalysisMetrics.coverage(accounts: analysisAccounts, records: analysisRecords)
    }

    func analysisGranularities(for account: Account) -> [AnalysisGranularity] {
        AnalysisGranularitySupport.available(
            for: account.provider,
            isDemo: isDemo || account.isDemo
        )
    }

    func usageSegments(
        for account: Account,
        metric: UsageMetric,
        granularity: AnalysisGranularity
    ) -> [[UsageChartPoint]] {
        let effective: AnalysisGranularity = granularity == .automatic ? .day : granularity
        guard AnalysisChartMath.granuleSupportsUsage(effective) else { return [] }
        let records = analysisRecords(for: account)
        let currency = records.compactMap(\.currency).first
        let values = AnalysisChartMath.dailyValues(
            records: records,
            metric: metric,
            currency: currency
        )
        return AnalysisChartMath.segments(
            days: CalendarDay.days(from: currentRange),
            values: values,
            granularity: effective
        )
    }

    func balanceChartPoints(
        for account: Account,
        granularity: AnalysisGranularity
    ) -> [BalanceChartPoint] {
        let snapshots = balanceSnapshots(for: account)
            .flatMap(\.snapshots)
            .filter { analysisRange.interval.contains($0.asOf) }
        let effective: AnalysisGranularity = granularity == .automatic ? .day : granularity
        return AnalysisChartMath.balancePoints(
            snapshots: snapshots,
            granularity: effective
        )
    }

    var officialCreditsRemaining: [String: Decimal] {
        let scoped = overviewAccountsToShow.filter { $0.capabilities.credits }
        return DashboardMetrics.creditsRemaining(accounts: scoped, quotas: quotas)
    }

    var balanceAccounts: [Account] {
        accounts.filter { $0.provider == .deepseek }
    }

    var overviewPlatformAccounts: [Account] {
        overviewScope.platformAccounts(in: accounts)
    }

    var selectedOverviewAccount: Account? {
        guard let overviewAccountFilter else { return nil }
        return accounts.first { $0.id == overviewAccountFilter }
    }

    var overviewAccountsToShow: [Account] {
        overviewScope.accounts(in: accounts)
    }

    var availableBalanceCurrencies: [String] {
        let scoped = overviewAccountsToShow.filter { $0.capabilities.balance }
        return DashboardMetrics.balanceCurrencies(accounts: scoped, balances: balances)
    }

    var showsBalanceCurrencyPicker: Bool {
        BalanceCurrencyPolicy.shouldShowPicker(options: availableBalanceCurrencies)
    }

    var officialBalances: [String: Decimal] {
        guard let balanceCurrencyFilter else { return [:] }
        let scoped = overviewAccountsToShow.filter { $0.capabilities.balance }
        guard let total = DashboardMetrics.balanceTotal(
            accounts: scoped,
            balances: balances,
            currency: balanceCurrencyFilter
        ) else { return [:] }
        return [balanceCurrencyFilter: total]
    }

    func balanceCurrencies(for account: Account) -> [String] {
        BalanceSummary.currencies(for: latestBalances(for: account))
    }

    func currencyLabel(for account: Account) -> String {
        if account.capabilities.balance {
            let currencies = balanceCurrencies(for: account)
            if currencies.isEmpty {
                return account.lastSuccessAt == nil ? L10n.t("app.e20ea04d1a") : L10n.t("app.4fb783cbf3")
            }
            return currencies.joined(separator: " / ")
        }
        return latestQuota(for: account)?.currency ?? account.provider.defaultCurrency
    }

    var usageAccounts: [Account] {
        accounts.filter { $0.capabilities.usage }
    }

    var creditAccounts: [Account] {
        accounts.filter { $0.capabilities.credits }
    }

    var activeDeepSeekAccounts: [Account] {
        balanceAccounts.filter(\.enabled)
    }

    func accountAbnormalReason(for account: Account) -> String? {
        guard account.provider == .deepseek else { return nil }
        let unavailable = latestBalances(for: account).filter { $0.isAvailable == false }
        guard !unavailable.isEmpty else { return nil }
        let codes = unavailable.map(\.currency).sorted().joined(separator: " / ")
        return L10n.f("app.95d17bb9b5", codes)
    }

    func dataIssue(for account: Account) -> String? {
        var reasons: [String] = []
        if account.credentialInvalid {
            reasons.append(L10n.f("app.29dd8b4768", L10n.t(account.lastError ?? L10n.t("credential.fallback.managementKey"))))
        } else if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !error.isEmpty {
            reasons.append(L10n.f("app.b3c04fc986", L10n.t(error)))
        }
        if let abnormal = accountAbnormalReason(for: account) {
            reasons.append(L10n.f("app.50cb69aa73", abnormal))
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: L10n.t("common.listSeparator"))
    }

    private func usageRecordsStatus(for accounts: [Account], emptyReason: String) -> DataStatus {
        AccountDataStatus.usage(
            accounts: accounts,
            records: usageRecords,
            emptyReason: emptyReason
        )
    }

    private func allUsageDataStatus() -> DataStatus {
        usageRecordsStatus(
            for: usageAccounts,
            emptyReason: L10n.t("app.5232d4224a")
        )
    }

    private var scopedUsageAccounts: [Account] {
        overviewAccountsToShow.filter { $0.capabilities.usage }
    }

    private func overviewUsageDataStatus() -> DataStatus {
        if let selectedOverviewAccount, !selectedOverviewAccount.capabilities.usage {
            return .unavailable(L10n.f("app.4a457dd1a3", selectedOverviewAccount.provider.displayName))
        }
        if let platform = overviewPlatformFilter, platform != .genericHTTP, !platform.capabilities.usage {
            return .unavailable(L10n.f("app.6ce20d545d", platform.displayName))
        }
        return usageRecordsStatus(
            for: scopedUsageAccounts,
            emptyReason: L10n.t("app.c1e0045f5d")
        )
    }

    func costDataStatus(forToday: Bool) -> DataStatus {
        let base = overviewUsageDataStatus()
        guard base.isActual else { return base }
        let values = forToday ? todayCosts : monthCosts
        guard values.isEmpty else { return .actual }
        if forToday {
            return .missing(L10n.t("app.1af3d1c790"))
        }
        return .missing(L10n.t("app.9e33a4d6ea"))
    }

    func tokenDataStatus() -> DataStatus {
        let base = overviewUsageDataStatus()
        guard base.isActual else { return base }
        if tokenSummary.providersWithTokens == 0 {
            return .missing(L10n.t("app.6b70c00827"))
        }
        return .actual
    }

    func creditDataStatus() -> DataStatus {
        if let selectedOverviewAccount {
            guard selectedOverviewAccount.capabilities.credits else {
                return .unavailable(L10n.f("app.cbe588fbcb", selectedOverviewAccount.provider.displayName))
            }
            return creditDataStatus(for: selectedOverviewAccount)
        }
        if let platform = overviewPlatformFilter, platform != .genericHTTP, !platform.capabilities.credits {
            return .unavailable(L10n.f("app.c75c91a987", platform.displayName))
        }
        let scoped = overviewAccountsToShow.filter { $0.capabilities.credits }
        guard !scoped.isEmpty else {
            return .missing(L10n.t("app.b438c0b2ae"))
        }
        let statuses = scoped.map {
            AccountDataStatus.quota(account: $0, quota: latestQuota(for: $0))
        }
        return AccountDataStatus.aggregate(statuses, emptyReason: L10n.t("app.2535677dec"))
    }

    func creditDataStatus(for account: Account) -> DataStatus {
        AccountDataStatus.quota(account: account, quota: latestQuota(for: account))
    }

    func balanceDataStatus(for account: Account? = nil) -> DataStatus {
        if let account {
            return AccountDataStatus.balance(
                account: account,
                balances: latestBalances(for: account)
            )
        }
        if let platform = overviewPlatformFilter, platform != .genericHTTP, !platform.capabilities.balance {
            return .unavailable(L10n.f("app.c5df6d01ed", platform.displayName))
        }
        let scoped = overviewAccountsToShow.filter { $0.capabilities.balance }
        guard !scoped.isEmpty else {
            return .missing(L10n.t("app.2333ef4627"))
        }
        let statuses = scoped.map {
            AccountDataStatus.balance(account: $0, balances: latestBalances(for: $0))
        }
        return AccountDataStatus.aggregate(statuses, emptyReason: L10n.t("app.33200f6386"))
    }

    func budgetSpendDataStatus(for account: Account) -> DataStatus {
        AccountDataStatus.budget(account: account, spend: budgetSpend(for: account))
    }

    func budgetRemainingDataStatus() -> DataStatus {
        let budgetAccounts: [Account]
        if let selectedOverviewAccount {
            budgetAccounts = selectedOverviewAccount.budget == nil ? [] : [selectedOverviewAccount]
        } else {
            budgetAccounts = overviewAccountsToShow.filter { $0.budget != nil }
        }
        guard !budgetAccounts.isEmpty else {
            return .unavailable(L10n.t("app.942f33f6b8"))
        }
        let statuses = budgetAccounts.map {
            AccountDataStatus.budget(account: $0, spend: budgetSpend(for: $0))
        }
        return AccountDataStatus.aggregate(statuses, emptyReason: L10n.t("app.942f33f6b8"))
    }

    func usageDataStatus() -> DataStatus {
        let base = allUsageDataStatus()
        guard base.isActual else { return base }
        if unfilteredRecords.isEmpty {
            return .missing(L10n.t("app.48749e1eb8"))
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
            if account.capabilities.balance, latestBalances(for: account).isEmpty {
                return .connectedNoData
            }
            if account.capabilities.credits, latestQuota(for: account) == nil {
                return .connectedNoData
            }
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
        if !account.enabled { return L10n.t("health.disabled") }
        if account.credentialInvalid {
            return account.provider == .openrouter
                ? L10n.t("app.764db3aa2c")
                : L10n.t("app.3c6fe7e071")
        }
        if accountAbnormalReason(for: account) != nil {
            return L10n.t("app.93f4323a20")
        }
        guard account.lastSuccessAt != nil else {
            if account.lastError != nil { return L10n.t("app.3a9de991cc") }
            return L10n.t("app.6f55e284a4")
        }
        let capabilities = account.capabilities
        if account.lastError != nil {
            if capabilities.credits {
                return latestQuota(for: account) == nil
                    ? L10n.t("app.eed9badd64")
                    : L10n.t("app.ab3f84c0a2")
            }
            if capabilities.balance {
                return latestBalances(for: account).isEmpty
                    ? L10n.t("app.c65cc67930")
                    : L10n.t("app.2f2b7e05e3")
            }
            return L10n.t("app.2f2b7e05e3")
        }
        if capabilities.credits {
            if latestQuota(for: account) == nil {
                return L10n.t("app.90dfb262ae")
            }
            return account.isDemo
                ? L10n.t("app.329a2b591b")
                : L10n.t("app.69afcf03fd")
        }
        if capabilities.balance {
            if latestBalances(for: account).isEmpty {
                return L10n.t("app.342072942c")
            }
            return L10n.t("app.76c7681fd9")
        }
        return L10n.t("app.65fe35c45e")
    }

    func lastSyncText(for account: Account) -> String {
        if let lastSuccess = account.lastSuccessAt {
            let text = DateFormatters.mediumDateTime.string(from: lastSuccess)
            return isStale(account) ? L10n.f("app.ea6f4c8653", text) : L10n.f("app.27f3a215af", text)
        }
        return L10n.t("app.52e38de1f4")
    }

    var unacknowledgedAlerts: [AlertEvent] {
        alerts.filter { !$0.acknowledged }
    }

    var unacknowledgedAlertCount: Int {
        MessageCenter.unacknowledgedCount(alerts)
    }

    var hasCriticalAlert: Bool {
        alerts.contains {
            !$0.acknowledged && [.budgetExceeded, .balanceLow, .credentialInvalid, .syncFailed, .lineCritical].contains($0.kind)
        }
    }

    var hasWarningAlert: Bool {
        alerts.contains {
            !$0.acknowledged && [.budgetWarning, .dataStale, .lineWarning].contains($0.kind)
        }
    }

    func acknowledge(_ alert: AlertEvent) {
        guard let store = activeStore else { return }
        do {
            try store.acknowledgeAlert(id: alert.id)
            let removedIds = toastQueue.visible
                .filter { $0.alertId == alert.id }
                .map(\.id)
            for id in removedIds {
                toastTasks[id]?.cancel()
                toastTasks.removeValue(forKey: id)
            }
            syncVisibleToasts(toastQueue.removeAlert(alertId: alert.id, now: Date()))
            reloadFromStore()
        } catch {
            showBanner(L10n.f("app.3ec8c19e6f", L10n.t(error.localizedDescription)), style: .error)
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
        if isDemo { return L10n.t("app.294780b3f2") }
        guard let realStore else { return databaseURL.path }
        return realStore.isInMemory ? L10n.t("app.87dd7c08e3") : realStore.path
    }

    var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional: return L10n.t("app.284cc0bae1")
        case .denied: return L10n.t("app.4c7c52c706")
        case .notDetermined: return L10n.t("app.452e30d1df")
        case .ephemeral: return L10n.t("app.6645a29821")
        @unknown default: return L10n.t("app.d9c32a4c3d")
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
            showBanner(L10n.f("app.bbdaf20d6a", L10n.t(error.localizedDescription)), style: .error)
        }
    }

    // MARK: - Language

    var effectiveLocale: Locale { LocalizationStore.shared.currentLocale }
    var effectiveLocaleIdentifier: String { LocalizationStore.shared.effectiveLocale }
    var selectedImportedLanguagePack: LocalizedLanguagePack? {
        LocalizationStore.shared.selectedPack
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func loadLanguagePreference() {
        let saved = isDemo ? nil : UserDefaults.standard.string(forKey: Self.languageKey)
        let store = LocalizationStore.shared
        if let saved, saved != AppLanguage.system.rawValue {
            store.select(locale: saved)
        } else {
            store.select(locale: nil)
        }
        if store.selectedIdentifier != saved, !isDemo {
            UserDefaults.standard.removeObject(forKey: Self.languageKey)
        }
        selectedLanguageIdentifier = store.selectedIdentifier
        languageOptions = store.availableLanguages
        localizationRevision = UUID()
    }

    func setLanguage(identifier: String) {
        let store = LocalizationStore.shared
        if identifier == AppLanguage.system.rawValue {
            store.select(locale: nil)
        } else {
            store.select(locale: identifier)
        }
        selectedLanguageIdentifier = store.selectedIdentifier
        languageOptions = store.availableLanguages
        if !isDemo {
            if selectedLanguageIdentifier == AppLanguage.system.rawValue {
                UserDefaults.standard.removeObject(forKey: Self.languageKey)
            } else {
                UserDefaults.standard.set(selectedLanguageIdentifier, forKey: Self.languageKey)
            }
        }
        localizationRevision = UUID()
        refreshLocalizedContent()
    }

    @discardableResult
    func importLanguagePack(data: Data, sourceFileName: String?) throws -> LocalizedLanguagePack {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        let pack = try LocalizationStore.shared.importPack(
            data: data,
            appVersion: Self.appVersion,
            sourceFileName: sourceFileName
        )
        languageOptions = LocalizationStore.shared.availableLanguages
        setLanguage(identifier: pack.locale)
        showBanner(L10n.f("app.languagePackImported", pack.displayName), style: .success)
        return pack
    }

    func removeLanguagePack(locale: String) throws {
        guard !isDemo else { throw AppActionError.demoReadOnly }
        let wasSelected = selectedLanguageIdentifier == locale
        try LocalizationStore.shared.removePack(locale: locale)
        languageOptions = LocalizationStore.shared.availableLanguages
        if wasSelected {
            setLanguage(identifier: AppLanguage.system.rawValue)
        } else {
            localizationRevision = UUID()
        }
        showBanner(L10n.t("app.languagePackRemoved"), style: .info)
    }

    private func refreshLocalizedContent() {
        updateMenuBar()
        guard !alerts.isEmpty else { return }
        for task in toastTasks.values { task.cancel() }
        toastTasks.removeAll()
        toastQueue = ToastQueue(maxVisible: 3)
        shownAlertIds.removeAll()
        enqueueAlertToasts(alerts.filter { !$0.acknowledged })
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if isDemo {
            showBanner(L10n.t("app.9d48fbb9e2"), style: .info)
            return
        }
        Task {
            if enabled {
                let status = await notifications.requestAuthorizationIfNeeded()
                notificationStatus = status
                guard status == .authorized || status == .provisional else {
                    showBanner(L10n.t("app.67dc5ac899"), style: .warning)
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
                showBanner(L10n.f("app.36652fd1cb", L10n.t(error.localizedDescription)), style: .error)
            }
        }
    }

    func sendTestNotification() {
        if isDemo {
            showBanner(L10n.t("app.c8e02b47fa"), style: .info)
            return
        }
        Task {
            let status = await notifications.requestAuthorizationIfNeeded()
            notificationStatus = status
            guard status == .authorized || status == .provisional else {
                showBanner(L10n.t("app.a96c46f300"), style: .warning)
                return
            }
            let sent = await notifications.post(
                title: L10n.t("app.4644dc5b14"),
                body: L10n.t("app.9efc8a8e3f")
            )
            if sent {
                showBanner(L10n.t("app.2d55ddbd5a"), style: .success)
            } else {
                showBanner(L10n.t("app.6fcc25f83d"), style: .error)
            }
        }
    }

    func openNotificationSettings() {
        notifications.openSystemNotificationSettings()
    }

    func requestEnterDemoMode() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("app.fb7f73f291")
        alert.informativeText = DemoMode.disclaimer
        alert.addButton(withTitle: L10n.t("app.fb7f73f291"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            enterDemoMode()
        }
    }

    func showDemoDisclaimer() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.t("app.d0f838a6b6")
        alert.informativeText = DemoMode.disclaimer
        alert.addButton(withTitle: L10n.t("app.cb63c62e50"))
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
            transport = makeTransport()
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
            showBanner(L10n.t("app.7e96362ee7"), style: .info)
        } catch {
            showBanner(L10n.f("app.7b6c04f5ba", L10n.t(error.localizedDescription)), style: .error)
        }
    }

    func exitDemoMode() {
        guard isDemo else { return }
        guard openRealStoreIfNeeded() else {
            showBanner(L10n.t("app.fce85267ff"), style: .error)
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
        loadLanguagePreference()
        reloadFromStore()
        syncEngine?.updateSettings(settings)
        syncEngine?.bootstrap(accounts: accounts)
        showOnboarding = accounts.isEmpty
        showBanner(L10n.t("app.fa39045beb"), style: .info)
    }

    func clearAllData(removeLanguagePacks: Bool = false) {
        if isDemo {
            exitDemoMode()
            showBanner(L10n.t("app.1b8dc501c3"), style: .success)
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
            errors.append(L10n.f("app.74c945eebf", L10n.t(error.localizedDescription)))
        }
        do { try realStore.clearAllData() } catch {
            errors.append(L10n.f("app.3f22758230", L10n.t(error.localizedDescription)))
        }
        notifications.clearDelivered()
        UserDefaults.standard.removeObject(forKey: Self.demoFlagKey)
        UserDefaults.standard.removeObject(forKey: Self.demoDisclaimerKey)
        UserDefaults.standard.removeObject(forKey: Self.languageKey)
        FloatingWindowStateStore().clear()
        if removeLanguagePacks {
            try? LocalizationStore.shared.clearPacks()
        }
        LocalizationStore.shared.setLanguage(.system)
        selectedLanguageIdentifier = AppLanguage.system.rawValue
        languageOptions = LocalizationStore.shared.availableLanguages
        localizationRevision = UUID()
        selectedTab = .overview
        selectedCurrency = nil
        overviewPlatformFilter = nil
        overviewAccountFilter = nil
        balanceCurrencyFilter = nil
        resetToastState()
        syncingAccountIds.removeAll()
        settings = AppSettings()
        transport = makeTransport()
        _ = openRealStoreIfNeeded()
        syncEngine?.updateSettings(settings)
        reloadFromStore()
        showOnboarding = true
        if errors.isEmpty {
            showBanner(L10n.t("app.027cb2a187"), style: .success)
        } else {
            showBanner(errors.joined(separator: L10n.t("common.listSeparator")), style: .error)
        }
    }

    func confirmClearAllData() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.t("app.c0c098d6ac")
        alert.informativeText = L10n.t("app.8b14fe5802")
        alert.addButton(withTitle: L10n.t("app.1fc1afc5c5"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let second = NSAlert()
        second.alertStyle = .critical
        second.messageText = L10n.t("app.1ec2117faf")
        second.informativeText = L10n.t("app.64746971b6")
        second.addButton(withTitle: L10n.t("app.04c3cd821d"))
        second.addButton(withTitle: L10n.t("common.cancel"))
        let removePacks = NSButton(
            checkboxWithTitle: L10n.t("app.clearLanguagePacks"),
            target: nil,
            action: nil
        )
        removePacks.state = .off
        second.accessoryView = removePacks
        if second.runModal() == .alertFirstButtonReturn {
            clearAllData(removeLanguagePacks: removePacks.state == .on)
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
                showBanner(L10n.t("app.ca9251b558"), style: .warning)
                return
            }
            await notifications.post(events: relevant)
        }
    }

    private func handleLoadedAlerts(_ loaded: [AlertEvent], previousIds: Set<String>) {
        let loadedIds = Set(loaded.map(\.id))
        let staleVisibleIds = toasts.compactMap { toast -> String? in
            guard let alertId = toast.alertId, !loadedIds.contains(alertId) else { return nil }
            return toast.id
        }
        for id in staleVisibleIds {
            toastTasks[id]?.cancel()
            toastTasks.removeValue(forKey: id)
        }
        syncVisibleToasts(toastQueue.removeAlerts(notIn: loadedIds, now: Date()))

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
            enqueueToast(AlertNoticePolicy.toast(for: alert))
        }
    }

    private func bannerTitle(for style: BannerStyle) -> String {
        switch style {
        case .info: return L10n.t("common.info")
        case .success: return L10n.t("common.success")
        case .warning: return L10n.t("common.info")
        case .error: return L10n.t("common.error")
        }
    }

    private func enqueueToast(_ toast: ToastMessage) {
        let promoted = toastQueue.enqueue(toast, now: Date())
        syncVisibleToasts(promoted)
    }

    private func syncVisibleToasts(_ promoted: [ToastMessage]) {
        toasts = toastQueue.visible
        for toast in promoted where toast.autoDismiss {
            scheduleExpiry(for: toast)
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
        guard toastQueue.visible.contains(where: { $0.id == id }) else { return }
        let promoted = toastQueue.expire(id: id, now: Date())
        toastTasks[id]?.cancel()
        toastTasks.removeValue(forKey: id)
        syncVisibleToasts(promoted)
    }

    func dismissToast(_ id: String) {
        let promoted = toastQueue.dismiss(id: id, now: Date())
        toastTasks[id]?.cancel()
        toastTasks.removeValue(forKey: id)
        syncVisibleToasts(promoted)
    }

    func dismissAllToasts() {
        toastTasks.values.forEach { $0.cancel() }
        toastTasks.removeAll()
        toastQueue.dismissAll()
        toasts = []
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
        var parts: [String] = [isDemo ? L10n.t("app.2b6bb70c85") : "Overplay"]
        if unacknowledgedAlertCount > 0 {
            parts.append(hasCriticalAlert ? L10n.f("app.146e97f7da", unacknowledgedAlertCount) : L10n.f("app.4c3b9d5adf", unacknowledgedAlertCount))
        } else if hasWarningAlert {
            parts.append(L10n.t("app.df356025b3"))
        } else if !accounts.isEmpty {
            parts.append(L10n.f("app.e8b079e0f6", accounts.count))
        }
        return parts.joined(separator: " · ")
    }
}
