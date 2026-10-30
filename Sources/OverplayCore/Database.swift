import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct DatabaseError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }

    init(_ message: String) {
        self.message = message
    }
}

final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var database: OpaquePointer?
        let result = sqlite3_open_v2(path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let database { sqlite3_close(database) }
            throw DatabaseError("数据库打开失败：\(message)")
        }
        handle = database
        sqlite3_busy_timeout(database, 3_000)
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" {
            try execute("PRAGMA journal_mode = WAL")
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func execute(_ sql: String, _ parameters: [Any?] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw DatabaseError("SQL 执行失败：\(errorMessage) [\(sql)]")
        }
    }

    func query(_ sql: String, _ parameters: [Any?] = []) throws -> [[String: Any]] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: Any]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                var row: [String: Any] = [:]
                let count = sqlite3_column_count(statement)
                for index in 0..<count {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    row[name] = columnValue(statement, index: index)
                }
                rows.append(row)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw DatabaseError("SQL 查询失败：\(errorMessage) [\(sql)]")
            }
        }
        return rows
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }

    private var errorMessage: String {
        guard let handle else { return "数据库未打开" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func prepare(_ sql: String, _ parameters: [Any?]) throws -> OpaquePointer {
        guard let handle else { throw DatabaseError("数据库未打开") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError("SQL 预处理失败：\(errorMessage) [\(sql)]")
        }
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let bindResult: Int32
            switch normalize(parameter) {
            case nil, is NSNull:
                bindResult = sqlite3_bind_null(statement, index)
            case let value as String:
                bindResult = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case let value as Int:
                bindResult = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case let value as Int64:
                bindResult = sqlite3_bind_int64(statement, index, value)
            case let value as Double:
                bindResult = sqlite3_bind_double(statement, index, value)
            case let value as Bool:
                bindResult = sqlite3_bind_int(statement, index, value ? 1 : 0)
            case let value as Decimal:
                bindResult = sqlite3_bind_text(statement, index, NSDecimalNumber(decimal: value).stringValue, -1, SQLITE_TRANSIENT)
            default:
                bindResult = sqlite3_bind_text(statement, index, String(describing: normalize(parameter)!), -1, SQLITE_TRANSIENT)
            }
            guard bindResult == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw DatabaseError("SQL 参数绑定失败：\(errorMessage)")
            }
        }
        return statement
    }

    private func normalize(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return nil }
            return normalize(child.value)
        }
        return value
    }

    private func columnValue(_ statement: OpaquePointer, index: Int32) -> Any {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return sqlite3_column_double(statement, index)
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return NSNull() }
            return String(cString: text)
        default:
            return NSNull()
        }
    }
}

public final class OverplayStore {
    private let connection: SQLiteConnection
    private let lock = NSRecursiveLock()
    public let path: String
    public let isInMemory: Bool

    private static let schemaVersion = 1

    public init(path: String) throws {
        self.path = path
        self.isInMemory = path == ":memory:"
        if !isInMemory {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        connection = try SQLiteConnection(path: path)
        try migrate()
    }

    public static func inMemory() throws -> OverplayStore {
        try OverplayStore(path: ":memory:")
    }


    private func migrate() throws {
        lock.lock()
        defer { lock.unlock() }
        try connection.execute("PRAGMA user_version")
        let rows = try connection.query("PRAGMA user_version")
        let version = (rows.first?.values.first as? Int) ?? 0
        guard version <= Self.schemaVersion else {
            throw DatabaseError("数据库版本 \(version) 高于当前应用支持的版本 \(Self.schemaVersion)")
        }
        if version < 1 {
            try connection.transaction {
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS accounts (
                    id TEXT PRIMARY KEY,
                    provider TEXT NOT NULL,
                    name TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    created_at REAL NOT NULL,
                    last_success_at REAL,
                    last_attempt_at REAL,
                    consecutive_failures INTEGER NOT NULL DEFAULT 0,
                    credential_invalid INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    is_demo INTEGER NOT NULL DEFAULT 0
                )
                """)
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS budgets (
                    account_id TEXT PRIMARY KEY,
                    amount TEXT NOT NULL,
                    currency TEXT NOT NULL,
                    period TEXT NOT NULL DEFAULT 'month',
                    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
                )
                """)
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS balance_thresholds (
                    account_id TEXT PRIMARY KEY,
                    amount TEXT NOT NULL,
                    currency TEXT NOT NULL,
                    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
                )
                """)
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS usage_records (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    day TEXT NOT NULL,
                    model TEXT NOT NULL,
                    provider_name TEXT NOT NULL DEFAULT '',
                    prompt_tokens INTEGER,
                    completion_tokens INTEGER,
                    reasoning_tokens INTEGER,
                    cached_tokens INTEGER,
                    requests INTEGER,
                    cost TEXT,
                    byok_cost TEXT,
                    currency TEXT,
                    source TEXT NOT NULL,
                    updated_at REAL NOT NULL,
                    UNIQUE(account_id, day, model, provider_name)
                )
                """)
                try connection.execute("CREATE INDEX IF NOT EXISTS usage_day_idx ON usage_records(day)")
                try connection.execute("CREATE INDEX IF NOT EXISTS usage_account_idx ON usage_records(account_id, day)")
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS balance_snapshots (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    currency TEXT NOT NULL,
                    total TEXT NOT NULL,
                    granted TEXT,
                    topped_up TEXT,
                    is_available INTEGER,
                    as_of REAL NOT NULL,
                    source TEXT NOT NULL,
                    UNIQUE(account_id, currency, as_of)
                )
                """)
                try connection.execute("CREATE INDEX IF NOT EXISTS balance_account_idx ON balance_snapshots(account_id, as_of)")
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS quota_snapshots (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    total_credits TEXT NOT NULL,
                    total_usage TEXT NOT NULL,
                    remaining TEXT NOT NULL,
                    currency TEXT NOT NULL,
                    as_of REAL NOT NULL,
                    source TEXT NOT NULL,
                    UNIQUE(account_id, as_of)
                )
                """)
                try connection.execute("CREATE INDEX IF NOT EXISTS quota_account_idx ON quota_snapshots(account_id, as_of)")
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS alert_events (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    account_name TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    fired_at REAL NOT NULL,
                    value TEXT NOT NULL,
                    threshold TEXT NOT NULL,
                    metric TEXT NOT NULL,
                    period_key TEXT NOT NULL,
                    acknowledged INTEGER NOT NULL DEFAULT 0,
                    is_demo INTEGER NOT NULL DEFAULT 0
                )
                """)
                try connection.execute("CREATE INDEX IF NOT EXISTS alert_fired_idx ON alert_events(fired_at)")
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS alert_states (
                    key TEXT PRIMARY KEY,
                    active INTEGER NOT NULL,
                    last_fired_at REAL,
                    last_value TEXT
                )
                """)
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS sync_runs (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    started_at REAL NOT NULL,
                    finished_at REAL,
                    status TEXT NOT NULL,
                    error TEXT,
                    trigger TEXT NOT NULL
                )
                """)
                try connection.execute("""
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """)
                try connection.execute("PRAGMA user_version = \(Self.schemaVersion)")
            }
        } else if version < Self.schemaVersion {
            throw DatabaseError("缺少数据库迁移步骤：\(version) -> \(Self.schemaVersion)")
        }
        try connection.execute("""
        CREATE TABLE IF NOT EXISTS account_profiles (
            account_id TEXT PRIMARY KEY,
            official_name TEXT,
            icon_name TEXT,
            generic_config TEXT,
            alert_config TEXT,
            FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
        )
        """)
    }

    public func clearAllData() throws {
        try withLock {
            try connection.transaction {
                for table in [
                    "alert_states", "alert_events", "sync_runs", "quota_snapshots",
                    "balance_snapshots", "usage_records", "budgets", "balance_thresholds",
                    "account_profiles", "accounts", "settings"
                ] {
                    try connection.execute("DELETE FROM \(table)")
                }
            }
        }
    }

    // MARK: - Accounts

    public func accounts(includeDeleted: Bool = false) throws -> [Account] {
        try withLock {
            let rows = try connection.query(
                includeDeleted
                    ? "SELECT * FROM accounts ORDER BY created_at ASC"
                    : "SELECT * FROM accounts WHERE is_deleted = 0 ORDER BY created_at ASC"
            )
            let budgets = try loadBudgets()
            let thresholds = try loadThresholds()
            let profiles = try loadAccountProfiles()
            return rows.compactMap { row in
                guard let account = account(from: row) else { return nil }
                var copy = account
                copy.budget = budgets[account.id]
                copy.balanceThreshold = thresholds[account.id]
                apply(profile: profiles[account.id], to: &copy)
                return copy
            }
        }
    }

    public func account(id: String) throws -> Account? {
        try withLock {
            let rows = try connection.query(
                "SELECT * FROM accounts WHERE id = ? AND is_deleted = 0 LIMIT 1", [id]
            )
            guard let row = rows.first, var account = account(from: row) else { return nil }
            account.budget = try loadBudget(accountId: id)
            account.balanceThreshold = try loadThreshold(accountId: id)
            apply(profile: try accountProfile(accountId: id), to: &account)
            return account
        }
    }

    public struct AccountProfile: Equatable, Sendable {
        public var officialName: String?
        public var iconName: String?
        public var genericConfig: GenericHTTPConfig?
        public var alertConfig: AccountAlertConfig?

        public init(
            officialName: String? = nil,
            iconName: String? = nil,
            genericConfig: GenericHTTPConfig? = nil,
            alertConfig: AccountAlertConfig? = nil
        ) {
            self.officialName = officialName
            self.iconName = iconName
            self.genericConfig = genericConfig
            self.alertConfig = alertConfig
        }

        public var isEmpty: Bool {
            officialName == nil && iconName == nil && genericConfig == nil && alertConfig == nil
        }
    }

    public func accountProfile(accountId: String) throws -> AccountProfile? {
        try withLock {
            let rows = try connection.query(
                "SELECT * FROM account_profiles WHERE account_id = ? LIMIT 1", [accountId]
            )
            return rows.first.flatMap(profile(from:))
        }
    }

    public func saveAccountProfile(accountId: String, profile: AccountProfile) throws {
        try withLock {
            try saveAccountProfileLocked(accountId: accountId, profile: profile)
        }
    }

    private func loadAccountProfiles() throws -> [String: AccountProfile] {
        let rows = try connection.query("SELECT * FROM account_profiles")
        var result: [String: AccountProfile] = [:]
        for row in rows {
            guard let accountId = row["account_id"] as? String,
                  let profile = profile(from: row) else { continue }
            result[accountId] = profile
        }
        return result
    }

    private func profile(from row: [String: Any]) -> AccountProfile? {
        guard let accountId = row["account_id"] as? String, !accountId.isEmpty else { return nil }
        let decoder = JSONDecoder()
        let generic = (row["generic_config"] as? String)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? decoder.decode(GenericHTTPConfig.self, from: $0) }
        let alert = (row["alert_config"] as? String)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? decoder.decode(AccountAlertConfig.self, from: $0) }
        return AccountProfile(
            officialName: row["official_name"] as? String,
            iconName: row["icon_name"] as? String,
            genericConfig: generic,
            alertConfig: alert
        )
    }

    private func apply(profile: AccountProfile?, to account: inout Account) {
        guard let profile else { return }
        account.officialName = profile.officialName
        account.iconName = profile.iconName
        account.genericConfig = profile.genericConfig
        account.alertConfig = profile.alertConfig
    }

    private func saveAccountProfileLocked(accountId: String, account: Account) throws {
        try saveAccountProfileLocked(accountId: accountId, profile: AccountProfile(
            officialName: account.officialName,
            iconName: account.iconName,
            genericConfig: account.genericConfig,
            alertConfig: account.alertConfig
        ))
    }

    private func saveAccountProfileLocked(accountId: String, profile: AccountProfile) throws {
        if profile.isEmpty {
            try connection.execute("DELETE FROM account_profiles WHERE account_id = ?", [accountId])
            return
        }
        let encoder = JSONEncoder()
        let generic = profile.genericConfig
            .flatMap { try? encoder.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        let alert = profile.alertConfig
            .flatMap { try? encoder.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        try connection.execute("""
        INSERT INTO account_profiles (
            account_id, official_name, icon_name, generic_config, alert_config
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(account_id) DO UPDATE SET
            official_name = excluded.official_name,
            icon_name = excluded.icon_name,
            generic_config = excluded.generic_config,
            alert_config = excluded.alert_config
        """, [accountId, profile.officialName, profile.iconName, generic, alert])
    }

    public func updateAccountProfile(
        id: String,
        name: String,
        profile: AccountProfile
    ) throws {
        try withLock {
            try connection.transaction {
                try connection.execute("UPDATE accounts SET name = ? WHERE id = ?", [name, id])
                try saveAccountProfileLocked(accountId: id, profile: profile)
            }
        }
    }

    public func insertAccount(_ account: Account) throws {
        try withLock {
            try connection.execute("""
            INSERT INTO accounts (
                id, provider, name, enabled, created_at, last_success_at, last_attempt_at,
                consecutive_failures, credential_invalid, last_error, is_deleted, is_demo
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """, [
                account.id, account.provider.rawValue, account.name, account.enabled ? 1 : 0,
                account.createdAt.timeIntervalSince1970,
                account.lastSuccessAt?.timeIntervalSince1970,
                account.lastAttemptAt?.timeIntervalSince1970,
                account.consecutiveFailures, account.credentialInvalid ? 1 : 0,
                account.lastError, account.isDemo ? 1 : 0
            ])
            if let budget = account.budget {
                try setBudgetLocked(accountId: account.id, budget: budget)
            }
            if let threshold = account.balanceThreshold {
                try setBalanceThresholdLocked(accountId: account.id, threshold: threshold)
            }
            try saveAccountProfileLocked(accountId: account.id, account: account)
        }
    }

    public func renameAccount(id: String, name: String) throws {
        try withLock {
            try connection.execute("UPDATE accounts SET name = ? WHERE id = ?", [name, id])
        }
    }

    public func setAccountEnabled(id: String, enabled: Bool) throws {
        try withLock {
            try connection.execute(
                "UPDATE accounts SET enabled = ?, last_error = ?, consecutive_failures = 0 WHERE id = ?",
                [enabled ? 1 : 0, enabled ? nil : "已禁用", id]
            )
        }
    }

    public func updateSyncState(
        id: String,
        lastSuccessAt: Date?,
        lastAttemptAt: Date,
        consecutiveFailures: Int,
        credentialInvalid: Bool,
        lastError: String?
    ) throws {
        try withLock {
            try connection.execute("""
            UPDATE accounts SET
                last_success_at = ?,
                last_attempt_at = ?,
                consecutive_failures = ?,
                credential_invalid = ?,
                last_error = ?
            WHERE id = ?
            """, [
                lastSuccessAt?.timeIntervalSince1970, lastAttemptAt.timeIntervalSince1970,
                consecutiveFailures, credentialInvalid ? 1 : 0, lastError, id
            ])
        }
    }

    public func updateProfile(id: String, name: String) throws {
        try withLock {
            try connection.execute("UPDATE accounts SET name = ? WHERE id = ?", [name, id])
        }
    }

    public func resetSyncFailures(id: String) throws {
        try withLock {
            try connection.execute(
                "UPDATE accounts SET consecutive_failures = 0, credential_invalid = 0, last_error = NULL WHERE id = ?",
                [id]
            )
        }
    }

    public func deleteAccount(id: String, removeHistory: Bool) throws {
        try withLock {
            try connection.transaction {
                if removeHistory {
                    for table in ["usage_records", "balance_snapshots", "quota_snapshots", "sync_runs", "alert_events"] {
                        try connection.execute("DELETE FROM \(table) WHERE account_id = ?", [id])
                    }
                    try connection.execute("DELETE FROM alert_states WHERE key LIKE ?", ["%\(id)%"])
                    try connection.execute("DELETE FROM budgets WHERE account_id = ?", [id])
                    try connection.execute("DELETE FROM balance_thresholds WHERE account_id = ?", [id])
                    try connection.execute("DELETE FROM account_profiles WHERE account_id = ?", [id])
                    try connection.execute("DELETE FROM accounts WHERE id = ?", [id])
                } else {
                    try connection.execute(
                        "UPDATE accounts SET is_deleted = 1, enabled = 0, last_error = ? WHERE id = ?",
                        ["账户已删除", id]
                    )
                    try connection.execute("DELETE FROM budgets WHERE account_id = ?", [id])
                    try connection.execute("DELETE FROM balance_thresholds WHERE account_id = ?", [id])
                    try connection.execute("DELETE FROM account_profiles WHERE account_id = ?", [id])
                    try connection.execute("DELETE FROM alert_states WHERE key LIKE ?", ["%\(id)%"])
                }
            }
        }
    }

    public func setBudget(accountId: String, budget: Budget?) throws {
        try withLock {
            try setBudgetLocked(accountId: accountId, budget: budget)
        }
    }

    public func setBalanceThreshold(accountId: String, threshold: BalanceThreshold?) throws {
        try withLock {
            try setBalanceThresholdLocked(accountId: accountId, threshold: threshold)
        }
    }

    private func setBudgetLocked(accountId: String, budget: Budget?) throws {
        if let budget {
            try connection.execute("""
            INSERT INTO budgets (account_id, amount, currency, period)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(account_id) DO UPDATE SET amount = excluded.amount,
                currency = excluded.currency, period = excluded.period
            """, [accountId, budget.amount, budget.currency, budget.period])
        } else {
            try connection.execute("DELETE FROM budgets WHERE account_id = ?", [accountId])
        }
    }

    private func setBalanceThresholdLocked(accountId: String, threshold: BalanceThreshold?) throws {
        if let threshold {
            try connection.execute("""
            INSERT INTO balance_thresholds (account_id, amount, currency)
            VALUES (?, ?, ?)
            ON CONFLICT(account_id) DO UPDATE SET amount = excluded.amount, currency = excluded.currency
            """, [accountId, threshold.amount, threshold.currency])
        } else {
            try connection.execute("DELETE FROM balance_thresholds WHERE account_id = ?", [accountId])
        }
    }

    private func loadBudgets() throws -> [String: Budget] {
        let rows = try connection.query("SELECT * FROM budgets")
        var result: [String: Budget] = [:]
        for row in rows {
            guard let accountId = row["account_id"] as? String,
                  let amountText = row["amount"] as? String,
                  let amount = Decimal(string: amountText),
                  let currency = row["currency"] as? String else { continue }
            result[accountId] = Budget(
                amount: amount,
                currency: currency,
                period: (row["period"] as? String) ?? "month"
            )
        }
        return result
    }

    private func loadThresholds() throws -> [String: BalanceThreshold] {
        let rows = try connection.query("SELECT * FROM balance_thresholds")
        var result: [String: BalanceThreshold] = [:]
        for row in rows {
            guard let accountId = row["account_id"] as? String,
                  let amountText = row["amount"] as? String,
                  let amount = Decimal(string: amountText),
                  let currency = row["currency"] as? String else { continue }
            result[accountId] = BalanceThreshold(amount: amount, currency: currency)
        }
        return result
    }

    private func loadBudget(accountId: String) throws -> Budget? {
        let rows = try connection.query("SELECT * FROM budgets WHERE account_id = ? LIMIT 1", [accountId])
        guard let row = rows.first,
              let amountText = row["amount"] as? String,
              let amount = Decimal(string: amountText),
              let currency = row["currency"] as? String else { return nil }
        return Budget(amount: amount, currency: currency, period: (row["period"] as? String) ?? "month")
    }

    private func loadThreshold(accountId: String) throws -> BalanceThreshold? {
        let rows = try connection.query(
            "SELECT * FROM balance_thresholds WHERE account_id = ? LIMIT 1", [accountId]
        )
        guard let row = rows.first,
              let amountText = row["amount"] as? String,
              let amount = Decimal(string: amountText),
              let currency = row["currency"] as? String else { return nil }
        return BalanceThreshold(amount: amount, currency: currency)
    }

    private func account(from row: [String: Any]) -> Account? {
        guard let id = row["id"] as? String,
              let providerText = row["provider"] as? String,
              let provider = ProviderKind(rawValue: providerText),
              let name = row["name"] as? String,
              let createdAtValue = row["created_at"] as? Double else { return nil }
        return Account(
            id: id,
            provider: provider,
            name: name,
            enabled: (row["enabled"] as? Int ?? 1) != 0,
            createdAt: Date(timeIntervalSince1970: createdAtValue),
            lastSuccessAt: (row["last_success_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
            lastAttemptAt: (row["last_attempt_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
            consecutiveFailures: row["consecutive_failures"] as? Int ?? 0,
            credentialInvalid: (row["credential_invalid"] as? Int ?? 0) != 0,
            lastError: row["last_error"] as? String,
            isDemo: (row["is_demo"] as? Int ?? 0) != 0
        )
    }

    // MARK: - Usage

    public func upsertUsage(_ records: [UsageRecord], accountName: String) throws {
        guard !records.isEmpty else { return }
        try withLock {
            try connection.transaction {
                for record in records {
                    try connection.execute("""
                    INSERT INTO usage_records (
                        id, account_id, day, model, provider_name, prompt_tokens,
                        completion_tokens, reasoning_tokens, cached_tokens, requests,
                        cost, byok_cost, currency, source, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(account_id, day, model, provider_name) DO UPDATE SET
                        prompt_tokens = excluded.prompt_tokens,
                        completion_tokens = excluded.completion_tokens,
                        reasoning_tokens = excluded.reasoning_tokens,
                        cached_tokens = excluded.cached_tokens,
                        requests = excluded.requests,
                        cost = excluded.cost,
                        byok_cost = excluded.byok_cost,
                        currency = excluded.currency,
                        source = excluded.source,
                        updated_at = excluded.updated_at
                    """, [
                        record.uniqueKey, record.accountId, record.day, record.model,
                        record.providerName, record.promptTokens, record.completionTokens,
                        record.reasoningTokens, record.cachedTokens, record.requests,
                        record.cost.map { NSDecimalNumber(decimal: $0).stringValue },
                        record.byokCost.map { NSDecimalNumber(decimal: $0).stringValue },
                        record.currency, record.source, record.updatedAt.timeIntervalSince1970
                    ])
                }
            }
        }
    }

    public func usage(accountId: String? = nil, range: DayRange? = nil) throws -> [UsageRecord] {
        try withLock {
            var sql = "SELECT * FROM usage_records"
            var parameters: [Any?] = []
            var conditions: [String] = []
            if let accountId {
                conditions.append("account_id = ?")
                parameters.append(accountId)
            }
            if let range {
                conditions.append("day >= ? AND day <= ?")
                parameters.append(range.startDay)
                parameters.append(range.endDay)
            }
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += " ORDER BY day ASC, model ASC"
            let rows = try connection.query(sql, parameters)
            let accounts = try loadAccountIdentities()
            return rows.compactMap { row -> UsageRecord? in
                guard let id = row["id"] as? String,
                      let recordAccountId = row["account_id"] as? String,
                      let day = row["day"] as? String,
                      let model = row["model"] as? String,
                      let source = row["source"] as? String,
                      let updatedAtValue = row["updated_at"] as? Double else { return nil }
                let identity = accounts[recordAccountId]
                let accountName = identity?.name ?? recordAccountId
                let provider = identity?.provider ?? .openrouter
                return UsageRecord(
                    id: id,
                    accountId: recordAccountId,
                    accountName: accountName,
                    provider: provider,
                    day: day,
                    model: model,
                    providerName: (row["provider_name"] as? String) ?? "",
                    promptTokens: row["prompt_tokens"] as? Int,
                    completionTokens: row["completion_tokens"] as? Int,
                    reasoningTokens: row["reasoning_tokens"] as? Int,
                    cachedTokens: row["cached_tokens"] as? Int,
                    requests: row["requests"] as? Int,
                    cost: (row["cost"] as? String).flatMap { Decimal(string: $0) },
                    byokCost: (row["byok_cost"] as? String).flatMap { Decimal(string: $0) },
                    currency: row["currency"] as? String,
                    source: source,
                    updatedAt: Date(timeIntervalSince1970: updatedAtValue)
                )
            }
        }
    }

    private func loadAccountIdentities() throws -> [String: (name: String, provider: ProviderKind)] {
        let rows = try connection.query("SELECT id, name, provider FROM accounts WHERE is_deleted = 0")
        var identities: [String: (name: String, provider: ProviderKind)] = [:]
        for row in rows {
            guard let id = row["id"] as? String,
                  let name = row["name"] as? String,
                  let providerText = row["provider"] as? String,
                  let provider = ProviderKind(rawValue: providerText) else { continue }
            identities[id] = (name.isEmpty ? id : name, provider)
        }
        return identities
    }

    public func monthSpend(accountId: String, currency: String, now: Date = Date()) throws -> Decimal {
        let (_, range) = CalendarDay.monthRange(now: now)
        let records = try usage(accountId: accountId, range: range)
        return records.reduce(Decimal(0)) { partial, record in
            guard record.currency == currency, let cost = record.cost else { return partial }
            return partial + cost
        }
    }

    public func latestUsageUpdate(accountId: String) throws -> Date? {
        try withLock {
            let rows = try connection.query(
                "SELECT MAX(updated_at) AS latest FROM usage_records WHERE account_id = ?", [accountId]
            )
            guard let value = rows.first?["latest"] as? Double else { return nil }
            return Date(timeIntervalSince1970: value)
        }
    }

    // MARK: - Snapshots

    public func insertBalanceSnapshots(_ snapshots: [BalanceSnapshot]) throws {
        guard !snapshots.isEmpty else { return }
        try withLock {
            try connection.transaction {
                for snapshot in snapshots {
                    try connection.execute("""
                    INSERT INTO balance_snapshots (
                        id, account_id, currency, total, granted, topped_up, is_available, as_of, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(account_id, currency, as_of) DO UPDATE SET
                        total = excluded.total, granted = excluded.granted,
                        topped_up = excluded.topped_up, is_available = excluded.is_available,
                        source = excluded.source
                    """, [
                        snapshot.id, snapshot.accountId, snapshot.currency, snapshot.total,
                        snapshot.granted, snapshot.toppedUp,
                        snapshot.isAvailable.map { $0 ? 1 : 0 },
                        snapshot.asOf.timeIntervalSince1970, snapshot.source
                    ])
                }
            }
        }
    }

    public func latestBalances(accountId: String) throws -> [String: BalanceSnapshot] {
        try withLock {
            let rows = try connection.query(
                "SELECT * FROM balance_snapshots WHERE account_id = ? ORDER BY as_of DESC", [accountId]
            )
            var result: [String: BalanceSnapshot] = [:]
            for row in rows {
                guard let snapshot = balanceSnapshot(from: row) else { continue }
                if result[snapshot.currency] == nil {
                    result[snapshot.currency] = snapshot
                }
            }
            return result
        }
    }

    public func balanceSnapshots(accountId: String, currency: String, range: DayRange? = nil) throws -> [BalanceSnapshot] {
        try withLock {
            var sql = "SELECT * FROM balance_snapshots WHERE account_id = ? AND currency = ?"
            var parameters: [Any?] = [accountId, currency]
            if let range {
                let start = CalendarDay.date(from: range.startDay, timeZone: CalendarDay.utc, calendar: {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = CalendarDay.utc
                    return calendar
                }())
                let end = CalendarDay.date(from: range.endDay, timeZone: CalendarDay.utc, calendar: {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = CalendarDay.utc
                    return calendar
                }())
                if let start, let end {
                    let endExclusive = end.addingTimeInterval(86_400)
                    sql += " AND as_of >= ? AND as_of < ?"
                    parameters.append(start.timeIntervalSince1970)
                    parameters.append(endExclusive.timeIntervalSince1970)
                }
            }
            sql += " ORDER BY as_of ASC"
            return try connection.query(sql, parameters).compactMap(balanceSnapshot)
        }
    }

    private func balanceSnapshot(from row: [String: Any]) -> BalanceSnapshot? {
        guard let id = row["id"] as? String,
              let accountId = row["account_id"] as? String,
              let currency = row["currency"] as? String,
              let totalText = row["total"] as? String,
              let total = Decimal(string: totalText),
              let asOf = row["as_of"] as? Double,
              let source = row["source"] as? String else { return nil }
        return BalanceSnapshot(
            id: id,
            accountId: accountId,
            currency: currency,
            total: total,
            granted: (row["granted"] as? String).flatMap { Decimal(string: $0) },
            toppedUp: (row["topped_up"] as? String).flatMap { Decimal(string: $0) },
            isAvailable: (row["is_available"] as? Int).map { $0 != 0 },
            asOf: Date(timeIntervalSince1970: asOf),
            source: source
        )
    }

    public func insertQuotaSnapshot(_ snapshot: QuotaSnapshot) throws {
        try withLock {
            try connection.execute("""
            INSERT INTO quota_snapshots (
                id, account_id, total_credits, total_usage, remaining, currency, as_of, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, as_of) DO UPDATE SET
                total_credits = excluded.total_credits,
                total_usage = excluded.total_usage,
                remaining = excluded.remaining,
                currency = excluded.currency,
                source = excluded.source
            """, [
                snapshot.id, snapshot.accountId, snapshot.totalCredits, snapshot.totalUsage,
                snapshot.remaining, snapshot.currency, snapshot.asOf.timeIntervalSince1970,
                snapshot.source
            ])
        }
    }

    public func latestQuota(accountId: String) throws -> QuotaSnapshot? {
        try withLock {
            let rows = try connection.query(
                "SELECT * FROM quota_snapshots WHERE account_id = ? ORDER BY as_of DESC LIMIT 1",
                [accountId]
            )
            guard let row = rows.first,
                  let id = row["id"] as? String,
                  let accountId = row["account_id"] as? String,
                  let totalCreditsText = row["total_credits"] as? String,
                  let totalUsageText = row["total_usage"] as? String,
                  let remainingText = row["remaining"] as? String,
                  let totalCredits = Decimal(string: totalCreditsText),
                  let totalUsage = Decimal(string: totalUsageText),
                  let remaining = Decimal(string: remainingText),
                  let currency = row["currency"] as? String,
                  let asOf = row["as_of"] as? Double,
                  let source = row["source"] as? String else { return nil }
            return QuotaSnapshot(
                id: id, accountId: accountId, totalCredits: totalCredits,
                totalUsage: totalUsage, remaining: remaining, currency: currency,
                asOf: Date(timeIntervalSince1970: asOf), source: source
            )
        }
    }

    // MARK: - Alerts

    public func insertAlerts(_ events: [AlertEvent]) throws {
        guard !events.isEmpty else { return }
        try withLock {
            try connection.transaction {
                for event in events {
                    try connection.execute("""
                    INSERT INTO alert_events (
                        id, account_id, account_name, kind, fired_at, value,
                        threshold, metric, period_key, acknowledged, is_demo
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                        event.id, event.accountId, event.accountName, event.kind.rawValue,
                        event.firedAt.timeIntervalSince1970, event.value, event.threshold,
                        event.metric, event.periodKey, event.acknowledged ? 1 : 0,
                        event.isDemo ? 1 : 0
                    ])
                }
            }
        }
    }

    public func alerts(limit: Int = 200) throws -> [AlertEvent] {
        try withLock {
            let rows = try connection.query(
                "SELECT * FROM alert_events ORDER BY fired_at DESC LIMIT ?", [limit]
            )
            return rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let accountId = row["account_id"] as? String,
                      let accountName = row["account_name"] as? String,
                      let kindText = row["kind"] as? String,
                      let kind = AlertKind(rawValue: kindText),
                      let firedAt = row["fired_at"] as? Double,
                      let value = row["value"] as? String,
                      let threshold = row["threshold"] as? String,
                      let metric = row["metric"] as? String,
                      let periodKey = row["period_key"] as? String else { return nil }
                return AlertEvent(
                    id: id, accountId: accountId, accountName: accountName, kind: kind,
                    firedAt: Date(timeIntervalSince1970: firedAt), value: value,
                    threshold: threshold, metric: metric, periodKey: periodKey,
                    acknowledged: (row["acknowledged"] as? Int ?? 0) != 0,
                    isDemo: (row["is_demo"] as? Int ?? 0) != 0
                )
            }
        }
    }

    public func acknowledgeAlert(id: String) throws {
        try withLock {
            try connection.execute("UPDATE alert_events SET acknowledged = 1 WHERE id = ?", [id])
        }
    }

    public func deleteAlertStates(like pattern: String) throws {
        try withLock {
            try connection.execute("DELETE FROM alert_states WHERE key LIKE ?", [pattern])
        }
    }

    public func alertState(key: String) throws -> AlertState? {
        try withLock {
            let rows = try connection.query("SELECT * FROM alert_states WHERE key = ?", [key])
            guard let row = rows.first, let key = row["key"] as? String else { return nil }
            return AlertState(
                key: key,
                active: (row["active"] as? Int ?? 0) != 0,
                lastFiredAt: (row["last_fired_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                lastValue: row["last_value"] as? String
            )
        }
    }

    public func upsertAlertState(_ state: AlertState) throws {
        try withLock {
            try connection.execute("""
            INSERT INTO alert_states (key, active, last_fired_at, last_value)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET active = excluded.active,
                last_fired_at = COALESCE(excluded.last_fired_at, alert_states.last_fired_at),
                last_value = excluded.last_value
            """, [state.key, state.active ? 1 : 0, state.lastFiredAt?.timeIntervalSince1970, state.lastValue])
        }
    }

    // MARK: - Sync runs

    public func startSyncRun(id: String, accountId: String, trigger: String, at date: Date) throws {
        try withLock {
            try connection.execute("""
            INSERT INTO sync_runs (id, account_id, started_at, status, trigger)
            VALUES (?, ?, ?, 'running', ?)
            """, [id, accountId, date.timeIntervalSince1970, trigger])
        }
    }

    public func finishSyncRun(id: String, status: String, error: String?, at date: Date) throws {
        try withLock {
            try connection.execute(
                "UPDATE sync_runs SET finished_at = ?, status = ?, error = ? WHERE id = ?",
                [date.timeIntervalSince1970, status, error, id]
            )
        }
    }

    // MARK: - Settings

    public func settings() throws -> AppSettings {
        try withLock {
            let rows = try connection.query("SELECT * FROM settings")
            var values: [String: String] = [:]
            for row in rows {
                if let key = row["key"] as? String, let value = row["value"] as? String {
                    values[key] = value
                }
            }
            let interval = Int(values["refresh_interval_minutes"] ?? "") ?? 15
            let notifications = (values["notifications_enabled"] ?? "1") != "0"
            let publicAlertConfig = (values["public_alert_config"] ?? "")
                .data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(PublicAlertConfig.self, from: $0) }
                ?? PublicAlertConfig()
            return AppSettings(
                refreshIntervalMinutes: max(5, min(60, interval)),
                notificationsEnabled: notifications,
                publicAlertConfig: publicAlertConfig
            )
        }
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try withLock {
            try connection.transaction {
                try setSettingLocked("refresh_interval_minutes", String(settings.refreshIntervalMinutes))
                try setSettingLocked("notifications_enabled", settings.notificationsEnabled ? "1" : "0")
                let publicConfig = try JSONEncoder().encode(settings.publicAlertConfig)
                try setSettingLocked("public_alert_config", String(data: publicConfig, encoding: .utf8) ?? "{}")
            }
        }
    }

    private func setSettingLocked(_ key: String, _ value: String) throws {
        try connection.execute("""
        INSERT INTO settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, [key, value])
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
