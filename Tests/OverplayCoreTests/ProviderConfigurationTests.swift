import XCTest
@testable import OverplayCore

final class ProviderConfigurationTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    private var genericConfig: GenericHTTPConfig {
        GenericHTTPConfig(
            baseURL: "https://api.example.com",
            endpointPath: "/summary",
            authMode: .bearer,
            mapping: GenericFieldMapping(
                balanceTotal: "data.balance.total",
                balanceCurrency: "data.balance.currency",
                creditsTotal: "data.credits.total",
                creditsUsed: "data.credits.used",
                creditsCurrency: "data.credits.currency"
            )
        )
    }

    func testGenericURLValidationBlocksUnsafeHosts() {
        XCTAssertEqual(
            GenericHTTPURLValidator.validate(URL(string: "http://api.example.com")!),
            .requiresHTTPS
        )
        XCTAssertEqual(
            GenericHTTPURLValidator.validate(URL(string: "https://localhost/summary")!),
            .localhost
        )
        XCTAssertEqual(
            GenericHTTPURLValidator.validate(URL(string: "https://10.0.0.8/summary")!),
            .privateAddress
        )
        XCTAssertNotNil(
            GenericHTTPURLValidator.validate(URL(string: "https://169.254.169.254/latest")!)
        )
        XCTAssertNil(
            GenericHTTPURLValidator.validate(URL(string: "https://api.example.com/summary")!)
        )
    }

    func testJSONPathResolverSupportsNestedObjectsAndArrays() {
        let payload: [String: Any] = [
            "data": [
                "balance": ["total": 42.5, "currency": "USD"],
                "items": [["tokens": 12]]
            ]
        ]
        XCTAssertEqual(
            JSONPathResolver.decimal(at: "data.balance.total", in: payload),
            Decimal(string: "42.5")
        )
        XCTAssertEqual(JSONPathResolver.string(at: "data.balance.currency", in: payload), "USD")
        XCTAssertEqual(JSONPathResolver.int(at: "data.items.0.tokens", in: payload), 12)
        XCTAssertNil(JSONPathResolver.value(at: "data.missing", in: payload))
    }

    func testGenericConnectorTestsAndSyncsBalance() async throws {
        let config = genericConfig
        let transport = FakeHTTPTransport([
            response(200, body: #"{"data":{"balance":{"total":"88.50","currency":"usd"},"credits":{"total":100,"used":10,"currency":"USD"}}}"#),
            response(200, body: #"{"data":{"balance":{"total":"88.50","currency":"usd"},"credits":{"total":100,"used":10,"currency":"USD"}}}"#)
        ])
        let connector = GenericHTTPConnector(config: config, transport: transport)
        let test = await connector.testConnection(credential: "secret", now: now)
        XCTAssertEqual(test.category, .success)
        XCTAssertTrue(test.capabilities?.balance ?? false)

        let account = Account(
            provider: .genericHTTP,
            name: "Generic",
            genericConfig: config
        )
        let outcome = await connector.sync(account: account, credential: "secret", now: now)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.balanceSnapshots.first?.total, Decimal(string: "88.50"))
        XCTAssertEqual(outcome.balanceSnapshots.first?.currency, "USD")
        XCTAssertEqual(outcome.quotaSnapshot?.remaining, 90)
    }

    func testGenericConnectorBuildsUsageRecord() async {
        let config = GenericHTTPConfig(
            baseURL: "https://api.example.com",
            endpointPath: "/usage",
            mapping: GenericFieldMapping(
                usageDay: "day",
                promptTokens: "tokens.prompt",
                completionTokens: "tokens.completion",
                requests: "requests",
                cost: "cost",
                usageCurrency: "currency"
            )
        )
        let transport = FakeHTTPTransport([
            response(200, body: #"{"day":"2026-10-27","tokens":{"prompt":100,"completion":50},"requests":3,"cost":"0.25","currency":"USD"}"#)
        ])
        let connector = GenericHTTPConnector(config: config, transport: transport)
        let account = Account(provider: .genericHTTP, name: "Generic", genericConfig: config)
        let outcome = await connector.sync(account: account, credential: "secret", now: now)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.usageRecords.first?.promptTokens, 100)
        XCTAssertEqual(outcome.usageRecords.first?.completionTokens, 50)
        XCTAssertEqual(outcome.usageRecords.first?.requests, 3)
        XCTAssertEqual(outcome.usageRecords.first?.cost, Decimal(string: "0.25"))
        XCTAssertEqual(outcome.usageRecords.first?.currency, "USD")
    }

    func testGenericConnectorClassifiesFailures() async {
        let account = Account(provider: .genericHTTP, name: "Generic", genericConfig: genericConfig)

        let unauthorized = GenericHTTPConnector(
            config: genericConfig,
            transport: FakeHTTPTransport([response(401)])
        )
        let unauthorizedOutcome = await unauthorized.sync(account: account, credential: "secret", now: now)
        XCTAssertEqual(unauthorizedOutcome.failureCategory, .invalidCredential)

        let malformed = GenericHTTPConnector(
            config: genericConfig,
            transport: FakeHTTPTransport([response(200, body: "not json")])
        )
        let malformedOutcome = await malformed.sync(account: account, credential: "secret", now: now)
        XCTAssertEqual(malformedOutcome.failureCategory, .malformed)
    }

    func testGenericConnectorClassifiesAllHTTPFailureCategories() async {
        let account = Account(provider: .genericHTTP, name: "Generic", genericConfig: genericConfig)

        func outcome(_ response: HTTPResponse) async -> SyncOutcome {
            let connector = GenericHTTPConnector(
                config: genericConfig,
                transport: FakeHTTPTransport([response])
            )
            return await connector.sync(account: account, credential: "secret", now: now)
        }

        var result = await outcome(response(403))
        XCTAssertEqual(result.failureCategory, .permission)
        XCTAssertEqual(result.status, .failed, "403 不应永久标记凭据失效")

        result = await outcome(response(429, headers: ["Retry-After": "30"]))
        XCTAssertEqual(result.failureCategory, .rateLimited)
        XCTAssertEqual(result.retryAfter, 30)

        for status in [400, 404, 405] {
            result = await outcome(response(status))
            XCTAssertEqual(result.failureCategory, .address, "HTTP \(status) 应归类为地址 / 端点错误")
        }
    }

    func testGenericConnectorClassifiesTransportFailures() async {
        let account = Account(provider: .genericHTTP, name: "Generic", genericConfig: genericConfig)

        func outcome(_ error: HTTPTransportError) async -> SyncOutcome {
            let connector = GenericHTTPConnector(
                config: genericConfig,
                transport: FakeHTTPTransport([Result<HTTPResponse, HTTPTransportError>.failure(error)])
            )
            return await connector.sync(account: account, credential: "secret", now: now)
        }

        let timeoutOutcome = await outcome(.timedOut)
        XCTAssertEqual(timeoutOutcome.failureCategory, .timeout)
        let offlineOutcome = await outcome(.offline)
        XCTAssertEqual(offlineOutcome.failureCategory, .network)
        let redirectOutcome = await outcome(.redirectRejected)
        XCTAssertEqual(redirectOutcome.failureCategory, .address)
    }

    func testAccountInputValidation() throws {
        let existing = Account(provider: .deepseek, name: "主账户")
        XCTAssertEqual(
            try AccountInputValidator.validateNewAccount(
                provider: .deepseek,
                name: "  新账户 ",
                credential: "key",
                genericConfig: nil,
                existingAccounts: [existing]
            ),
            "新账户"
        )
        XCTAssertThrowsError(
            try AccountInputValidator.validateNewAccount(
                provider: .deepseek,
                name: "",
                credential: "  ",
                genericConfig: nil,
                existingAccounts: []
            )
        ) { error in
            XCTAssertEqual(error as? AccountValidationError, .emptyCredential)
        }
        XCTAssertThrowsError(
            try AccountInputValidator.validateNewAccount(
                provider: .deepseek,
                name: "主账户",
                credential: "key",
                genericConfig: nil,
                existingAccounts: [existing]
            )
        ) { error in
            XCTAssertEqual(error as? AccountValidationError, .duplicateName)
        }
        XCTAssertThrowsError(
            try AccountInputValidator.validateNewAccount(
                provider: .genericHTTP,
                name: "Custom",
                credential: "key",
                genericConfig: nil,
                existingAccounts: []
            )
        ) { error in
            XCTAssertEqual(error as? AccountValidationError, .missingGenericConfig)
        }
        XCTAssertThrowsError(
            try AccountInputValidator.validateNewAccount(
                provider: .genericHTTP,
                name: "Custom",
                credential: "key",
                genericConfig: GenericHTTPConfig(baseURL: "https://api.example.com"),
                existingAccounts: []
            )
        ) { error in
            XCTAssertEqual(error as? AccountValidationError, .missingMapping)
        }
        XCTAssertThrowsError(
            try AccountInputValidator.validateNewAccount(
                provider: .genericHTTP,
                name: "Custom",
                credential: "key",
                genericConfig: GenericHTTPConfig(
                    baseURL: "http://api.example.com",
                    mapping: GenericFieldMapping(balanceTotal: "total", balanceCurrency: "currency")
                ),
                existingAccounts: []
            )
        ) { error in
            XCTAssertEqual(
                error as? AccountValidationError,
                .invalidGenericConfig(.requiresHTTPS)
            )
        }
    }

    func testGenericConnectorRejectsSSRFBeforeNetwork() async {
        let config = GenericHTTPConfig(
            baseURL: "https://127.0.0.1",
            endpointPath: "/secret",
            mapping: GenericFieldMapping(balanceTotal: "total", balanceCurrency: "currency")
        )
        let transport = FakeHTTPTransport()
        let connector = GenericHTTPConnector(config: config, transport: transport)
        let result = await connector.testConnection(credential: "secret", now: now)
        XCTAssertEqual(result.category, .address)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
