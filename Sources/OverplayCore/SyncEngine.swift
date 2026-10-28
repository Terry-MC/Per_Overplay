import Foundation

public enum SyncTrigger: String {
    case manual
    case auto
    case startup
}

private enum SyncAbort: Error {
    case cancelled
    case accountUnavailable
}

public enum SyncEvent {
    case started(accountId: String)
    case finished(accountId: String, outcome: SyncOutcome)
    case cancelled(accountId: String)
    case alerts([AlertEvent])
    case scheduleChanged
}

public final class SyncEngine {
    private let store: OverplayStore
    private let credentials: CredentialStore
    private let transport: HTTPTransport
    private let alertEngine: AlertEngine
    private let lock = NSLock()
    private var inFlight: Set<String> = []
    private var nextDue: [String: Date] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var cancelled = false
    private var settings: AppSettings

    public var onEvent: ((SyncEvent) -> Void)?

    public init(
        store: OverplayStore,
        credentials: CredentialStore,
        transport: HTTPTransport,
        settings: AppSettings
    ) {
        self.store = store
        self.credentials = credentials
        self.transport = transport
        self.settings = settings
        self.alertEngine = AlertEngine(store: store)
    }

    public func updateSettings(_ settings: AppSettings) {
        withLock { self.settings = settings }
        emit(.scheduleChanged)
    }

    public func bootstrap(accounts: [Account], now: Date = Date()) {
        withLock {
            for (index, account) in accounts.enumerated() where nextDue[account.id] == nil {
                nextDue[account.id] = now.addingTimeInterval(Double(index) * 4)
            }
            tasks.keys.forEach { id in
                if !accounts.contains(where: { $0.id == id && $0.enabled }) {
                    nextDue[id] = nil
                }
            }
        }
        emit(.scheduleChanged)
    }

    public func isInFlight(accountId: String) -> Bool {
        withLock { inFlight.contains(accountId) }
    }

    public func resetSchedule(accountId: String, now: Date = Date()) {
        withLock {
            nextDue[accountId] = now
        }
        emit(.scheduleChanged)
    }

    public func cancel(accountId: String) {
        let task = withLock { () -> Task<Void, Never>? in
            nextDue[accountId] = nil
            return tasks.removeValue(forKey: accountId)
        }
        task?.cancel()
    }

    public func cancelAll() {
        let all = withLock { () -> [Task<Void, Never>] in
            cancelled = true
            let values = Array(tasks.values)
            tasks.removeAll()
            nextDue.removeAll()
            inFlight.removeAll()
            return values
        }
        all.forEach { $0.cancel() }
        transport.shutdown()
    }

    public func refreshDue(accounts: [Account], now: Date = Date()) {
        let due = withLock { () -> [Account] in
            guard !cancelled else { return [] }
            for (index, account) in accounts.enumerated() where nextDue[account.id] == nil {
                nextDue[account.id] = now.addingTimeInterval(Double(index) * 4)
            }
            return accounts.filter { account in
                guard account.enabled, !account.credentialInvalid else { return false }
                guard let next = nextDue[account.id] else { return false }
                return next <= now && !inFlight.contains(account.id)
            }
        }
        for account in due {
            withLock {
                nextDue[account.id] = now.addingTimeInterval(settings.refreshInterval)
            }
            enqueue(account: account, trigger: .auto, now: now)
        }
    }

    @discardableResult
    public func startManualRefresh(account: Account, now: Date = Date()) -> Bool {
        enqueue(account: account, trigger: .manual, now: now)
    }

    @discardableResult
    public func refresh(
        account: Account,
        trigger: SyncTrigger = .manual,
        now: Date = Date()
    ) async -> SyncOutcome? {
        guard markInFlight(account.id) else { return nil }
        defer { markFinished(account.id) }
        emit(.started(accountId: account.id))
        let runId = UUID().uuidString
        try? store.startSyncRun(id: runId, accountId: account.id, trigger: trigger.rawValue, at: now)

        let credential = (try? credentials.credential(accountId: account.id)) ?? nil
        guard let credential, !credential.isEmpty else {
            let outcome = missingCredentialOutcome(account: account)
            finish(
                account: account,
                outcome: outcome,
                trigger: trigger,
                runId: runId,
                now: now
            )
            return outcome
        }

        let connector = ConnectorFactory.make(for: account.provider, transport: transport)
        let outcome = await connector.sync(account: account, credential: credential, now: now)
        if Task.isCancelled || withLock({ cancelled }) {
            try? store.finishSyncRun(id: runId, status: "cancelled", error: nil, at: Date())
            emit(.cancelled(accountId: account.id))
            return nil
        }
        guard let liveAccount = (try? store.account(id: account.id)) ?? nil,
              liveAccount.enabled else {
            try? store.finishSyncRun(id: runId, status: "cancelled", error: "账户已删除或禁用", at: Date())
            emit(.cancelled(accountId: account.id))
            return nil
        }
        finish(
            account: account,
            outcome: outcome,
            trigger: trigger,
            runId: runId,
            now: now
        )
        return outcome
    }

    public func evaluatePeriodicAlerts(
        accounts: [Account],
        settings: AppSettings,
        now: Date = Date()
    ) -> [AlertEvent] {
        var all: [AlertEvent] = []
        for account in accounts where account.enabled {
            let latestBalance: BalanceSnapshot? = {
                guard let threshold = account.balanceThreshold else { return nil }
                return (try? store.latestBalances(accountId: account.id))?[threshold.currency]
            }()
            let monthSpend: Decimal? = {
                guard let budget = account.budget, providerSupportsBudget(account.provider) else { return nil }
                return try? store.monthSpend(accountId: account.id, currency: budget.currency, now: now)
            }()
            let usageFresh = isUsageFresh(account: account, settings: settings, now: now)
            let balanceFresh = isUsageFresh(account: account, settings: settings, now: now)
            let snapshot = AlertSnapshot(
                accountId: account.id,
                accountName: account.displayName,
                provider: account.provider,
                enabled: account.enabled,
                isDemo: account.isDemo,
                budget: account.budget,
                monthSpend: monthSpend,
                balanceThreshold: account.balanceThreshold,
                latestBalance: latestBalance,
                balanceIsFresh: balanceFresh,
                consecutiveFailures: account.consecutiveFailures,
                credentialInvalid: account.credentialInvalid,
                lastSuccessAt: account.lastSuccessAt,
                lastAttemptAt: account.lastAttemptAt,
                createdAt: account.createdAt,
                refreshInterval: settings.refreshInterval,
                usageIsFresh: usageFresh,
                now: now
            )
            if let events = try? alertEngine.evaluate(snapshot), !events.isEmpty {
                all.append(contentsOf: events)
            }
        }
        if !all.isEmpty {
            emit(.alerts(all))
        }
        return all
    }

    // MARK: - Internals

    private func finish(
        account: Account,
        outcome: SyncOutcome,
        trigger: SyncTrigger,
        runId: String,
        now: Date
    ) {
        do {
            try persist(account: account, outcome: outcome, trigger: trigger, now: now)
        } catch is SyncAbort {
            try? store.finishSyncRun(id: runId, status: "cancelled", error: nil, at: now)
            emit(.cancelled(accountId: account.id))
            return
        } catch {
            let errorOutcome = SyncOutcome(
                status: .failed,
                error: "本地数据写入失败：\(error.localizedDescription)",
                capabilities: account.capabilities,
                source: account.provider.displayName,
                failureCategory: .unknown
            )
            emit(.finished(accountId: account.id, outcome: errorOutcome))
            try? store.finishSyncRun(id: runId, status: "failed", error: error.localizedDescription, at: now)
            scheduleAfterFailure(accountId: account.id, outcome: errorOutcome, now: now)
            return
        }

        try? store.finishSyncRun(
            id: runId,
            status: outcome.status.rawValue,
            error: outcome.error,
            at: now
        )
        scheduleAfterOutcome(accountId: account.id, outcome: outcome, now: now)
        emit(.finished(accountId: account.id, outcome: outcome))
        evaluateAlerts(accountId: account.id, outcome: outcome, now: now)
    }

    private func persist(account: Account, outcome: SyncOutcome, trigger: SyncTrigger, now: Date) throws {
        guard !Task.isCancelled, !withLock({ cancelled }) else { throw SyncAbort.cancelled }
        guard let liveAccount = try store.account(id: account.id), liveAccount.enabled else {
            throw SyncAbort.accountUnavailable
        }
        if !outcome.usageRecords.isEmpty {
            try store.upsertUsage(outcome.usageRecords, accountName: account.displayName)
        }
        if !outcome.balanceSnapshots.isEmpty {
            try store.insertBalanceSnapshots(outcome.balanceSnapshots)
        }
        if let quota = outcome.quotaSnapshot {
            try store.insertQuotaSnapshot(quota)
        }

        let current = try store.account(id: account.id) ?? account
        let successAt: Date?
        let failures: Int
        let credentialInvalid: Bool
        let lastError: String?

        switch outcome.status {
        case .success:
            successAt = now
            failures = 0
            credentialInvalid = false
            lastError = nil
        case .partial:
            successAt = now
            failures = 0
            credentialInvalid = false
            lastError = outcome.error
        case .invalidCredential:
            successAt = current.lastSuccessAt
            failures = current.consecutiveFailures + 1
            credentialInvalid = true
            lastError = outcome.error
        case .rateLimited, .failed:
            successAt = current.lastSuccessAt
            failures = current.consecutiveFailures + 1
            credentialInvalid = false
            lastError = outcome.error
        }

        try store.updateSyncState(
            id: account.id,
            lastSuccessAt: successAt,
            lastAttemptAt: now,
            consecutiveFailures: failures,
            credentialInvalid: credentialInvalid,
            lastError: lastError
        )
    }

    private func evaluateAlerts(accountId: String, outcome: SyncOutcome, now: Date) {
        guard let account = (try? store.account(id: accountId)) ?? nil else { return }
        let currentSettings = withLock { settings }
        let latestBalance: BalanceSnapshot? = {
            guard let threshold = account.balanceThreshold else { return nil }
            return (try? store.latestBalances(accountId: account.id))?[threshold.currency]
        }()
        let monthSpend: Decimal? = {
            guard let budget = account.budget, providerSupportsBudget(account.provider) else { return nil }
            return try? store.monthSpend(accountId: account.id, currency: budget.currency, now: now)
        }()
        let usageFresh = outcome.status == .success
            && (account.lastSuccessAt.map { now.timeIntervalSince($0) <= currentSettings.refreshInterval * 2 } ?? false)
        let balanceFresh = outcome.status == .success
            && (account.lastSuccessAt.map { now.timeIntervalSince($0) <= currentSettings.refreshInterval * 2 } ?? false)
        let snapshot = AlertSnapshot(
            accountId: account.id,
            accountName: account.displayName,
            provider: account.provider,
            enabled: account.enabled,
            isDemo: account.isDemo,
            budget: account.budget,
            monthSpend: monthSpend,
            balanceThreshold: account.balanceThreshold,
            latestBalance: latestBalance,
            balanceIsFresh: balanceFresh,
            consecutiveFailures: account.consecutiveFailures,
            credentialInvalid: account.credentialInvalid,
            lastSuccessAt: account.lastSuccessAt,
            lastAttemptAt: account.lastAttemptAt,
            createdAt: account.createdAt,
            refreshInterval: currentSettings.refreshInterval,
            usageIsFresh: usageFresh,
            now: now
        )
        if let events = try? alertEngine.evaluate(snapshot), !events.isEmpty {
            emit(.alerts(events))
        }
    }

    @discardableResult
    private func enqueue(account: Account, trigger: SyncTrigger, now: Date) -> Bool {
        withLock {
            guard !cancelled, !inFlight.contains(account.id), tasks[account.id] == nil else {
                return false
            }
            let task = Task { [weak self] in
                guard let self else { return }
                _ = await self.refresh(account: account, trigger: trigger, now: now)
                self.withLock {
                    _ = self.tasks.removeValue(forKey: account.id)
                }
            }
            tasks[account.id] = task
            return true
        }
    }

    private func scheduleAfterOutcome(accountId: String, outcome: SyncOutcome, now: Date) {
        withLock {
            let interval = settings.refreshInterval
            switch outcome.status {
            case .success:
                nextDue[accountId] = now.addingTimeInterval(interval)
            case .partial:
                if let retryAfter = outcome.retryAfter {
                    nextDue[accountId] = now.addingTimeInterval(min(max(retryAfter, 60), 3600))
                } else {
                    nextDue[accountId] = now.addingTimeInterval(interval)
                }
            case .invalidCredential:
                nextDue[accountId] = .distantFuture
            case .rateLimited:
                let delay = max(outcome.retryAfter ?? 60, 60)
                nextDue[accountId] = now.addingTimeInterval(min(delay, 3600))
            case .failed:
                let failures = (try? store.account(id: accountId))?.consecutiveFailures ?? 1
                let exponent = min(Double(max(failures - 1, 0)), 10)
                let delay = min(60 * pow(2, exponent), 3600)
                nextDue[accountId] = now.addingTimeInterval(delay)
            }
        }
        emit(.scheduleChanged)
    }

    private func scheduleAfterFailure(accountId: String, outcome: SyncOutcome, now: Date) {
        scheduleAfterOutcome(accountId: accountId, outcome: outcome, now: now)
    }

    private func isUsageFresh(account: Account, settings: AppSettings, now: Date) -> Bool {
        guard let lastSuccess = account.lastSuccessAt else { return false }
        guard now.timeIntervalSince(lastSuccess) <= settings.refreshInterval * 2 else { return false }
        guard account.consecutiveFailures == 0 else { return false }
        guard !account.credentialInvalid, account.lastError == nil else { return false }
        return true
    }

    private func providerSupportsBudget(_ provider: ProviderKind) -> Bool {
        provider == .openrouter
    }

    private func missingCredentialOutcome(account: Account) -> SyncOutcome {
        SyncOutcome(
            status: .failed,
            error: "未找到该账户的 Keychain 凭据，请重新输入 API Key",
            capabilities: account.capabilities,
            source: account.provider.displayName,
            failureCategory: .unknown
        )
    }

    private func markInFlight(_ accountId: String) -> Bool {
        withLock {
            guard !cancelled, !inFlight.contains(accountId) else { return false }
            inFlight.insert(accountId)
            return true
        }
    }

    private func markFinished(_ accountId: String) {
        withLock {
            _ = inFlight.remove(accountId)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func emit(_ event: SyncEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
