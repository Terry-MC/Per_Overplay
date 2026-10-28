import Foundation

public protocol ProviderConnector {
    var provider: ProviderKind { get }
    func testConnection(credential: String, now: Date) async -> ConnectionTestResult
    func sync(account: Account, credential: String, now: Date) async -> SyncOutcome
}

public enum ConnectorFactory {
    public static func make(for provider: ProviderKind, transport: HTTPTransport) -> ProviderConnector {
        switch provider {
        case .deepseek: return DeepSeekConnector(transport: transport)
        case .openrouter: return OpenRouterConnector(transport: transport)
        }
    }
}

public enum ProviderEndpoints {
    public static let deepSeekBalance = URL(string: "https://api.deepseek.com/user/balance")!
    public static let openRouterCredits = URL(string: "https://openrouter.ai/api/v1/credits")!
    public static let openRouterActivity = URL(string: "https://openrouter.ai/api/v1/activity")!
}

private struct FlexibleString: Decodable {
    let text: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = nil
        } else if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode(Decimal.self) {
            text = NSDecimalNumber(decimal: value).stringValue
        } else if let value = try? container.decode(Int.self) {
            text = String(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected string or number"
            )
        }
    }
}

private struct FlexibleDecimal: Decodable {
    let value: Decimal?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let decimal = try? container.decode(Decimal.self) {
            value = decimal
        } else if let text = try? container.decode(String.self) {
            value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected decimal or numeric string"
            )
        }
    }
}

private struct FlexibleInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let integer = try? container.decode(Int.self) {
            value = integer
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else if let text = try? container.decode(String.self) {
            value = Int(text)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected integer"
            )
        }
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    struct BalanceInfo: Decodable {
        let currency: String
        let total_balance: FlexibleString?
        let granted_balance: FlexibleString?
        let topped_up_balance: FlexibleString?
    }

    let is_available: Bool?
    let balance_infos: [BalanceInfo]?
}

private struct OpenRouterCreditsResponse: Decodable {
    struct Credits: Decodable {
        let total_credits: FlexibleDecimal?
        let total_usage: FlexibleDecimal?
    }

    let data: Credits?
}

private struct OpenRouterActivityEnvelope: Decodable {
    let data: [OpenRouterActivityItem]?
}

private struct OpenRouterActivityItem: Decodable {
    let date: String?
    let model: String?
    let provider_name: String?
    let usage: FlexibleDecimal?
    let byok_usage_inference: FlexibleDecimal?
    let requests: FlexibleInt?
    let prompt_tokens: FlexibleInt?
    let completion_tokens: FlexibleInt?
    let reasoning_tokens: FlexibleInt?
    let cached_tokens: FlexibleInt?
}

public final class DeepSeekConnector: ProviderConnector {
    public let provider: ProviderKind = .deepseek
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func testConnection(credential: String, now: Date = Date()) async -> ConnectionTestResult {
        let outcome = await sync(
            account: Account(provider: .deepseek, name: "连接测试"),
            credential: credential,
            now: now
        )
        if outcome.status == .success {
            return ConnectionTestResult(
                category: .success,
                message: "连接成功。DeepSeek：余额可用，官方不提供历史用量 / 费用。",
                capabilities: outcome.capabilities
            )
        }
        return ConnectionTestResult(
            category: outcome.failureCategory ?? .unknown,
            message: outcome.error ?? "连接失败",
            capabilities: outcome.capabilities,
            retryAfter: outcome.retryAfter
        )
    }

    public func sync(account: Account, credential: String, now: Date) async -> SyncOutcome {
        let request = HTTPRequest(
            url: ProviderEndpoints.deepSeekBalance,
            headers: [
                "Authorization": "Bearer \(credential)",
                "Accept": "application/json"
            ]
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as HTTPTransportError {
            return failure(
                message: error.description,
                category: error.isTimeout ? .timeout : .network,
                credential: credential
            )
        } catch {
            return failure(message: "网络错误", category: .network, credential: credential)
        }

        guard response.status == 200 else {
            return httpFailure(response, credential: credential)
        }
        guard !response.body.isEmpty else {
            return failure(message: "DeepSeek 返回空响应", category: .malformed, credential: credential, status: response.status)
        }
        let decoded: DeepSeekBalanceResponse
        do {
            decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: response.body)
        } catch {
            return failure(message: "DeepSeek 返回格式异常", category: .malformed, credential: credential, status: response.status)
        }
        guard let infos = decoded.balance_infos, !infos.isEmpty else {
            return failure(message: "DeepSeek 未返回余额数据", category: .malformed, credential: credential, status: response.status)
        }

        var snapshots: [BalanceSnapshot] = []
        for info in infos {
            guard let totalText = info.total_balance?.text,
                  let total = Money.parse(totalText) else {
                return failure(message: "DeepSeek 余额字段缺失或格式异常", category: .malformed, credential: credential, status: response.status)
            }
            let currency = info.currency.uppercased()
            guard !currency.isEmpty else {
                return failure(message: "DeepSeek 未返回币种", category: .malformed, credential: credential, status: response.status)
            }
            snapshots.append(BalanceSnapshot(
                accountId: account.id,
                currency: currency,
                total: total,
                granted: info.granted_balance?.text.flatMap(Money.parse),
                toppedUp: info.topped_up_balance?.text.flatMap(Money.parse),
                isAvailable: decoded.is_available,
                asOf: now,
                source: "DeepSeek 官方 API · GET /user/balance"
            ))
        }

        return SyncOutcome(
            status: .success,
            capabilities: ProviderKind.deepseek.capabilities,
            balanceSnapshots: snapshots,
            source: "DeepSeek 官方 API"
        )
    }

    private func httpFailure(_ response: HTTPResponse, credential: String) -> SyncOutcome {
        let serverMessage = Sanitizer.errorMessage(from: response.body, credential: credential)
        switch response.status {
        case 401:
            return failure(
                message: "DeepSeek API Key 无效或已过期（HTTP 401）",
                category: .invalidCredential, credential: credential,
                status: response.status
            )
        case 403:
            return failure(
                message: "该 API Key 无权访问 DeepSeek 余额接口（HTTP 403）",
                category: .permission, credential: credential,
                status: response.status
            )
        case 429:
            return failure(
                message: rateLimitMessage(retryAfter: response.retryAfter),
                category: .rateLimited, credential: credential,
                status: response.status, retryAfter: response.retryAfter
            )
        default:
            var message = "DeepSeek 请求失败（HTTP \(response.status)）"
            if let serverMessage { message += "：\(serverMessage)" }
            return failure(message: message, category: .unknown, credential: credential, status: response.status)
        }
    }
}

public final class OpenRouterConnector: ProviderConnector {
    public let provider: ProviderKind = .openrouter
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func testConnection(credential: String, now: Date = Date()) async -> ConnectionTestResult {
        let outcome = await sync(
            account: Account(provider: .openrouter, name: "连接测试"),
            credential: credential,
            now: now
        )
        switch outcome.status {
        case .success:
            return ConnectionTestResult(
                category: .success,
                message: "连接成功。OpenRouter：credits / 额度 / 用量 / 费用可用（用量为最近 30 个 UTC 日）。",
                capabilities: outcome.capabilities
            )
        case .partial:
            return ConnectionTestResult(
                category: .permission,
                message: outcome.error ?? "credits 可用，但用量接口不可用",
                capabilities: outcome.capabilities
            )
        default:
            return ConnectionTestResult(
                category: outcome.failureCategory ?? .unknown,
                message: outcome.error ?? "连接失败",
                capabilities: outcome.capabilities,
                retryAfter: outcome.retryAfter
            )
        }
    }

    public func sync(account: Account, credential: String, now: Date) async -> SyncOutcome {
        let creditsResult = await fetchCredits(credential: credential, account: account, now: now)
        switch creditsResult {
        case .failure(let outcome):
            return outcome
        case .success(let quota):
            let activity = await fetchActivity(account: account, credential: credential, now: now)
            switch activity {
            case .success(let records):
                return SyncOutcome(
                    status: .success,
                    capabilities: ProviderKind.openrouter.capabilities,
                    quotaSnapshot: quota,
                    usageRecords: records,
                    source: "OpenRouter 官方 API"
                )
            case .failure(let failure):
                return SyncOutcome(
                    status: .partial,
                    error: failure.message,
                    capabilities: ProviderKind.openrouter.capabilities,
                    quotaSnapshot: quota,
                    usageRecords: [],
                    source: "OpenRouter 官方 API",
                    httpStatus: failure.status,
                    failureCategory: failure.category
                )
            }
        }
    }

    private enum CreditsResult {
        case success(QuotaSnapshot)
        case failure(SyncOutcome)
    }

    private func fetchCredits(credential: String, account: Account, now: Date) async -> CreditsResult {
        let request = HTTPRequest(
            url: ProviderEndpoints.openRouterCredits,
            headers: [
                "Authorization": "Bearer \(credential)",
                "Accept": "application/json"
            ]
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as HTTPTransportError {
            return .failure(failure(
                message: error.description,
                category: error.isTimeout ? .timeout : .network,
                credential: credential
            ))
        } catch {
            return .failure(failure(message: "网络错误", category: .network, credential: credential))
        }

        switch response.status {
        case 200:
            break
        case 401, 403:
            let message = "需要 OpenRouter Management Key：普通 API Key 无法读取 credits / activity，或 Key 无效（HTTP \(response.status)）"
            return .failure(failure(
                message: message,
                category: response.status == 401 ? .invalidCredential : .permission,
                credential: credential,
                status: response.status
            ))
        case 429:
            return .failure(failure(
                message: rateLimitMessage(retryAfter: response.retryAfter),
                category: .rateLimited, credential: credential,
                status: response.status, retryAfter: response.retryAfter
            ))
        default:
            var message = "OpenRouter credits 请求失败（HTTP \(response.status)）"
            if let detail = Sanitizer.errorMessage(from: response.body, credential: credential) {
                message += "：\(detail)"
            }
            return .failure(failure(message: message, category: .unknown, credential: credential, status: response.status))
        }

        guard !response.body.isEmpty else {
            return .failure(failure(message: "OpenRouter credits 返回空响应", category: .malformed, credential: credential, status: response.status))
        }
        let decoded: OpenRouterCreditsResponse
        do {
            decoded = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: response.body)
        } catch {
            return .failure(failure(message: "OpenRouter credits 返回格式异常", category: .malformed, credential: credential, status: response.status))
        }
        guard let credits = decoded.data,
              let totalCredits = credits.total_credits?.value,
              let totalUsage = credits.total_usage?.value else {
            return .failure(failure(message: "OpenRouter credits 字段缺失", category: .malformed, credential: credential, status: response.status))
        }
        return .success(QuotaSnapshot(
            accountId: account.id,
            totalCredits: totalCredits,
            totalUsage: totalUsage,
            remaining: totalCredits - totalUsage,
            currency: "USD",
            asOf: now,
            source: "OpenRouter 官方 API · GET /credits"
        ))
    }

    private struct ActivityFailure: Error {
        let message: String
        let category: ConnectionTestResult.Category
        let status: Int
    }

    private func fetchActivity(
        account: Account,
        credential: String,
        now: Date
    ) async -> Result<[UsageRecord], ActivityFailure> {
        let request = HTTPRequest(
            url: ProviderEndpoints.openRouterActivity,
            headers: [
                "Authorization": "Bearer \(credential)",
                "Accept": "application/json"
            ]
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as HTTPTransportError {
            return .failure(ActivityFailure(
                message: error.description,
                category: error.isTimeout ? .timeout : .network,
                status: 0
            ))
        } catch {
            return .failure(ActivityFailure(message: "网络错误", category: .network, status: 0))
        }

        switch response.status {
        case 200:
            break
        case 401, 403:
            return .failure(ActivityFailure(
                message: "OpenRouter activity 需要 Management Key 权限（HTTP \(response.status)）",
                category: .permission, status: response.status
            ))
        case 429:
            return .failure(ActivityFailure(
                message: rateLimitMessage(retryAfter: response.retryAfter),
                category: .rateLimited, status: response.status
            ))
        default:
            var message = "OpenRouter activity 请求失败（HTTP \(response.status)）"
            if let detail = Sanitizer.errorMessage(from: response.body, credential: credential) {
                message += "：\(detail)"
            }
            return .failure(ActivityFailure(message: message, category: .unknown, status: response.status))
        }

        guard !response.body.isEmpty else {
            return .failure(ActivityFailure(message: "OpenRouter activity 返回空响应", category: .malformed, status: response.status))
        }
        let items = Self.decodeActivity(from: response.body)
        guard let items else {
            return .failure(ActivityFailure(message: "OpenRouter activity 返回格式异常", category: .malformed, status: response.status))
        }
        if items.isEmpty {
            return .success([])
        }

        struct Accumulator {
            var day: String
            var model: String
            var providerName: String
            var promptTokens: Int?
            var completionTokens: Int?
            var reasoningTokens: Int?
            var cachedTokens: Int?
            var requests: Int?
            var cost: Decimal?
            var byokCost: Decimal?
        }

        var accumulators: [String: Accumulator] = [:]
        var skipped = 0
        for item in items {
            guard let day = item.date, Self.isDayString(day) else {
                skipped += 1
                continue
            }
            let rawModel = item.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = rawModel.isEmpty ? "未知模型" : rawModel
            let providerName = item.provider_name ?? ""
            let key = "\(day)|\(model)|\(providerName)"
            var accumulator = accumulators[key] ?? Accumulator(
                day: day, model: model, providerName: providerName
            )
            Self.add(item.prompt_tokens?.value, to: &accumulator.promptTokens)
            Self.add(item.completion_tokens?.value, to: &accumulator.completionTokens)
            Self.add(item.reasoning_tokens?.value, to: &accumulator.reasoningTokens)
            Self.add(item.cached_tokens?.value, to: &accumulator.cachedTokens)
            Self.add(item.requests?.value, to: &accumulator.requests)
            Self.add(item.usage?.value, to: &accumulator.cost)
            Self.add(item.byok_usage_inference?.value, to: &accumulator.byokCost)
            accumulators[key] = accumulator
        }
        if accumulators.isEmpty && skipped > 0 {
            return .failure(ActivityFailure(message: "OpenRouter activity 数据行缺少有效日期", category: .malformed, status: response.status))
        }
        let records = accumulators.values.map { accumulator in
            UsageRecord(
                accountId: account.id,
                accountName: account.displayName,
                provider: .openrouter,
                day: accumulator.day,
                model: accumulator.model,
                providerName: accumulator.providerName,
                promptTokens: accumulator.promptTokens,
                completionTokens: accumulator.completionTokens,
                reasoningTokens: accumulator.reasoningTokens,
                cachedTokens: accumulator.cachedTokens,
                requests: accumulator.requests,
                cost: accumulator.cost,
                byokCost: accumulator.byokCost,
                currency: "USD",
                source: "OpenRouter 官方 API · GET /activity（UTC 日桶，最近约 30 天）",
                updatedAt: now
            )
        }
        return .success(records)
    }

    private static func add(_ value: Int?, to target: inout Int?) {
        guard let value else { return }
        target = (target ?? 0) + value
    }

    private static func add(_ value: Decimal?, to target: inout Decimal?) {
        guard let value else { return }
        target = (target ?? 0) + value
    }

    private static func decodeActivity(from data: Data) -> [OpenRouterActivityItem]? {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(OpenRouterActivityEnvelope.self, from: data),
           let items = envelope.data {
            return items
        }
        if let items = try? decoder.decode([OpenRouterActivityItem].self, from: data) {
            return items
        }
        return nil
    }

    private static func isDayString(_ text: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard regex?.firstMatch(in: text, range: range) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = CalendarDay.utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text) != nil
    }

    private func failure(
        message: String,
        category: ConnectionTestResult.Category,
        credential: String,
        status: Int? = nil,
        retryAfter: TimeInterval? = nil
    ) -> SyncOutcome {
        SyncOutcome(
            status: category == .invalidCredential || category == .permission ? .invalidCredential
                : category == .rateLimited ? .rateLimited : .failed,
            error: Sanitizer.sanitize(message, credential: credential),
            retryAfter: retryAfter,
            capabilities: ProviderKind.openrouter.capabilities,
            source: "OpenRouter 官方 API",
            httpStatus: status,
            failureCategory: category
        )
    }
}

private func failure(
    message: String,
    category: ConnectionTestResult.Category,
    credential: String,
    status: Int? = nil,
    retryAfter: TimeInterval? = nil
) -> SyncOutcome {
    SyncOutcome(
        status: category == .invalidCredential || category == .permission ? .invalidCredential
            : category == .rateLimited ? .rateLimited : .failed,
        error: Sanitizer.sanitize(message, credential: credential),
        retryAfter: retryAfter,
        capabilities: ProviderKind.deepseek.capabilities,
        source: "DeepSeek 官方 API",
        httpStatus: status,
        failureCategory: category
    )
}

private func rateLimitMessage(retryAfter: TimeInterval?) -> String {
    if let retryAfter {
        return "请求被厂商限流（HTTP 429），请在 \(Int(retryAfter.rounded())) 秒后重试"
    }
    return "请求被厂商限流（HTTP 429），请稍后重试"
}
