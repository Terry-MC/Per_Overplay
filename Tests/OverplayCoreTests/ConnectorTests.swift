import XCTest
@testable import OverplayCore

final class ConnectorTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)
    private let account = Account(id: "acct", provider: .deepseek, name: "DeepSeek")

    func testDeepSeekBalanceParsesCurrenciesAndOptionalFields() async {
        let transport = FakeHTTPTransport([
            response(200, body: """
            {"is_available":true,"balance_infos":[
              {"currency":"CNY","total_balance":"123.45","granted_balance":"10.00","topped_up_balance":"113.45"},
              {"currency":"USD","total_balance":"2.50"}
            ]}
            """)
        ])
        let connector = DeepSeekConnector(transport: transport)
        let outcome = await connector.sync(account: account, credential: "sk-test", now: now)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.balanceSnapshots.count, 2)
        let cny = outcome.balanceSnapshots.first { $0.currency == "CNY" }
        XCTAssertEqual(cny?.total, Decimal(string: "123.45"))
        XCTAssertEqual(cny?.granted, Decimal(string: "10.00"))
        XCTAssertEqual(cny?.isAvailable, true)
        let usd = outcome.balanceSnapshots.first { $0.currency == "USD" }
        XCTAssertNil(usd?.granted)
        XCTAssertNil(usd?.toppedUp)
        XCTAssertEqual(outcome.capabilities.balance, true)
        XCTAssertEqual(outcome.capabilities.usage, false)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.headers["Authorization"], "Bearer sk-test")
    }

    func testDeepSeekInvalidKeyAndPermission() async {
        let invalid = DeepSeekConnector(transport: FakeHTTPTransport([response(401)]))
        var outcome = await invalid.sync(account: account, credential: "secret-key", now: now)
        XCTAssertEqual(outcome.status, .invalidCredential)
        XCTAssertEqual(outcome.failureCategory, .invalidCredential)
        XCTAssertEqual(outcome.httpStatus, 401)
        XCTAssertFalse(outcome.error?.contains("secret-key") ?? true)

        let forbidden = DeepSeekConnector(transport: FakeHTTPTransport([response(403)]))
        outcome = await forbidden.sync(account: account, credential: "secret-key", now: now)
        XCTAssertEqual(outcome.status, .invalidCredential)
        XCTAssertEqual(outcome.failureCategory, .permission)
    }

    func testDeepSeekRateLimitHonorsRetryAfter() async {
        let connector = DeepSeekConnector(transport: FakeHTTPTransport([
            response(429, headers: ["Retry-After": "120"])
        ]))
        let outcome = await connector.sync(account: account, credential: "sk", now: now)
        XCTAssertEqual(outcome.status, .rateLimited)
        XCTAssertEqual(outcome.retryAfter, 120)
        XCTAssertEqual(outcome.failureCategory, .rateLimited)
    }

    func testDeepSeekTimeoutAndEmptyAndMalformed() async {
        let timeout = DeepSeekConnector(transport: FakeHTTPTransport([.failure(.timedOut)]))
        var outcome = await timeout.sync(account: account, credential: "sk", now: now)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.failureCategory, .timeout)

        let empty = DeepSeekConnector(transport: FakeHTTPTransport([response(200)]))
        outcome = await empty.sync(account: account, credential: "sk", now: now)
        XCTAssertEqual(outcome.failureCategory, .malformed)

        let malformed = DeepSeekConnector(transport: FakeHTTPTransport([response(200, body: "not-json")]))
        outcome = await malformed.sync(account: account, credential: "sk", now: now)
        XCTAssertEqual(outcome.failureCategory, .malformed)

        let noBalances = DeepSeekConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"is_available":true,"balance_infos":[]}"#)
        ]))
        outcome = await noBalances.sync(account: account, credential: "sk", now: now)
        XCTAssertEqual(outcome.failureCategory, .malformed)
    }

    func testServerErrorMessageDoesNotLeakCredential() async {
        let secret = "sk-leak-me-please"
        let connector = DeepSeekConnector(transport: FakeHTTPTransport([
            response(400, body: #"{"error":{"message":"invalid key sk-leak-me-please"}}"#)
        ]))
        let outcome = await connector.sync(account: account, credential: secret, now: now)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertFalse(outcome.error?.contains(secret) ?? true)
        XCTAssertTrue(outcome.error?.contains("•••") ?? false)
    }

    func testDeepSeekConnectionTest() async {
        let transport = FakeHTTPTransport([
            response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1.00"}]}"#)
        ])
        let result = await DeepSeekConnector(transport: transport).testConnection(
            credential: "sk", now: now
        )
        XCTAssertEqual(result.category, .success)
        XCTAssertTrue(result.message.contains("余额可用"))
        XCTAssertTrue(result.message.contains("不提供历史用量"))
    }

    func testOpenRouterSyncParsesCreditsAndActivity() async {
        let openRouterAccount = Account(id: "or", provider: .openrouter, name: "OR")
        let transport = FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":100.5,"total_usage":25.75}}"#),
            response(200, body: """
            {"data":[
              {"date":"2026-10-27","model":"openai/gpt-5.2","provider_name":"OpenAI",
               "usage":0.42,"byok_usage_inference":0.1,"requests":3,
               "prompt_tokens":100,"completion_tokens":50,"reasoning_tokens":20,"cached_tokens":5},
              {"date":"2026-10-26","model":"anthropic/claude","provider_name":"Anthropic",
               "usage":1.2,"requests":2,"prompt_tokens":200,"completion_tokens":80}
            ]}
            """)
        ])
        let outcome = await OpenRouterConnector(transport: transport).sync(
            account: openRouterAccount, credential: "mgmt-key", now: now
        )
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.quotaSnapshot?.totalCredits, Decimal(string: "100.5"))
        XCTAssertEqual(outcome.quotaSnapshot?.totalUsage, Decimal(string: "25.75"))
        XCTAssertEqual(outcome.quotaSnapshot?.remaining, Decimal(string: "74.75"))
        XCTAssertEqual(outcome.usageRecords.count, 2)
        let first = outcome.usageRecords.first { $0.model == "openai/gpt-5.2" }
        XCTAssertEqual(first?.promptTokens, 100)
        XCTAssertEqual(first?.completionTokens, 50)
        XCTAssertEqual(first?.reasoningTokens, 20)
        XCTAssertEqual(first?.cost, Decimal(string: "0.42"))
        XCTAssertEqual(first?.byokCost, Decimal(string: "0.1"))
        XCTAssertEqual(first?.currency, "USD")
        XCTAssertTrue(first?.source.contains("OpenRouter") ?? false)
        let second = outcome.usageRecords.first { $0.model == "anthropic/claude" }
        XCTAssertNil(second?.reasoningTokens)
        XCTAssertNil(second?.byokCost)
    }

    func testOpenRouterEmptyActivityIsSuccess() async {
        let openRouterAccount = Account(id: "or", provider: .openrouter, name: "OR")
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(200, body: #"{"data":[]}"#)
        ]))
        let outcome = await connector.sync(account: openRouterAccount, credential: "mgmt", now: now)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.usageRecords.count, 0)
        XCTAssertNotNil(outcome.quotaSnapshot)
    }

    func testOpenRouterMissingFieldsAreNotZero() async {
        let openRouterAccount = Account(id: "or", provider: .openrouter, name: "OR")
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(200, body: #"{"data":[{"date":"2026-10-27","model":"m"}]}"#)
        ]))
        let outcome = await connector.sync(account: openRouterAccount, credential: "mgmt", now: now)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertNil(outcome.usageRecords.first?.promptTokens)
        XCTAssertNil(outcome.usageRecords.first?.completionTokens)
        XCTAssertNil(outcome.usageRecords.first?.cost)
        XCTAssertNil(outcome.usageRecords.first?.totalTokens)
    }

    func testOpenRouterPartialWhenActivityFails() async {
        let openRouterAccount = Account(id: "or", provider: .openrouter, name: "OR")
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(500, body: "oops")
        ]))
        let outcome = await connector.sync(account: openRouterAccount, credential: "mgmt", now: now)
        XCTAssertEqual(outcome.status, .partial)
        XCTAssertNotNil(outcome.quotaSnapshot)
        XCTAssertTrue(outcome.usageRecords.isEmpty)
        XCTAssertTrue(outcome.error?.contains("activity") ?? false)
    }

    func testOpenRouterMalformedCreditsFails() async {
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":"oops"}}"#)
        ]))
        let outcome = await connector.sync(
            account: Account(id: "or", provider: .openrouter, name: "OR"),
            credential: "mgmt", now: now
        )
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.failureCategory, .malformed)
    }

    func testOpenRouterManagementKeyHintOn401And403() async {
        for status in [401, 403] {
            let connector = OpenRouterConnector(transport: FakeHTTPTransport([response(status)]))
            let outcome = await connector.sync(
                account: Account(id: "or", provider: .openrouter, name: "OR"),
                credential: "normal-key", now: now
            )
            XCTAssertEqual(outcome.status, .invalidCredential)
            XCTAssertTrue(outcome.error?.contains("Management Key") ?? false)
            XCTAssertEqual(outcome.failureCategory, status == 401 ? .invalidCredential : .permission)
        }
    }

    func testOpenRouterActivityRateLimitReturnsPartial() async {
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(429, headers: ["Retry-After": "30"])
        ]))
        let outcome = await connector.sync(
            account: Account(id: "or", provider: .openrouter, name: "OR"),
            credential: "mgmt", now: now
        )
        XCTAssertEqual(outcome.status, .partial)
        XCTAssertTrue(outcome.error?.contains("限流") ?? false)
    }

    func testOpenRouterConnectionTestSuccess() async {
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(200, body: #"{"data":[]}"#)
        ]))
        let result = await connector.testConnection(credential: "mgmt", now: now)
        XCTAssertEqual(result.category, .success)
        XCTAssertTrue(result.message.contains("credits"))
    }

    func testCapabilityMatrixBranches() {
        XCTAssertTrue(ProviderKind.deepseek.capabilities.balance)
        XCTAssertFalse(ProviderKind.deepseek.capabilities.usage)
        XCTAssertFalse(ProviderKind.deepseek.capabilities.cost)
        XCTAssertFalse(ProviderKind.deepseek.capabilities.credits)
        XCTAssertTrue(ProviderKind.openrouter.capabilities.balance == false)
        XCTAssertTrue(ProviderKind.openrouter.capabilities.usage)
        XCTAssertTrue(ProviderKind.openrouter.capabilities.cost)
        XCTAssertTrue(ProviderKind.openrouter.capabilities.credits)
    }
}

extension ConnectorTests {
    func testOpenRouterAggregatesDuplicateDayModelProviderRows() async {
        let openRouterAccount = Account(id: "or", provider: .openrouter, name: "OR")
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(200, body: """
            {"data":[
              {"date":"2026-10-27","model":"m","provider_name":"P","usage":0.10,"requests":2,
               "prompt_tokens":100,"completion_tokens":20,"reasoning_tokens":5,"byok_usage_inference":0.01},
              {"date":"2026-10-27","model":"m","provider_name":"P","usage":0.20,"requests":3,
               "prompt_tokens":50,"completion_tokens":10}
            ]}
            """)
        ]))
        let outcome = await connector.sync(account: openRouterAccount, credential: "mgmt", now: now)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.usageRecords.count, 1)
        let record = outcome.usageRecords[0]
        XCTAssertEqual(record.promptTokens, 150)
        XCTAssertEqual(record.completionTokens, 30)
        XCTAssertEqual(record.reasoningTokens, 5)
        XCTAssertEqual(record.requests, 5)
        XCTAssertEqual(record.cost, Decimal(string: "0.30"))
        XCTAssertEqual(record.byokCost, Decimal(string: "0.01"))
    }

    func testOpenRouterAggregationKeepsMissingFieldsMissing() async throws {
        let openRouterAccount = Account(id: "or", provider: .openrouter, name: "OR")
        let connector = OpenRouterConnector(transport: FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#),
            response(200, body: """
            {"data":[
              {"date":"2026-10-27","model":"m","provider_name":"P","usage":0.10},
              {"date":"2026-10-27","model":"m","provider_name":"P","prompt_tokens":5}
            ]}
            """)
        ]))
        let outcome = await connector.sync(account: openRouterAccount, credential: "mgmt", now: now)
        let record = try XCTUnwrap(outcome.usageRecords.first)
        XCTAssertEqual(record.promptTokens, 5)
        XCTAssertNil(record.completionTokens)
        XCTAssertEqual(record.cost, Decimal(string: "0.10"))
    }
}
