import Foundation

public final class GenericHTTPConnector: ProviderConnector {
    public let provider: ProviderKind = .genericHTTP
    private let config: GenericHTTPConfig
    private let transport: HTTPTransport

    public init(config: GenericHTTPConfig, transport: HTTPTransport) {
        self.config = config
        self.transport = transport
    }

    public func testConnection(credential: String, now: Date = Date()) async -> ConnectionTestResult {
        do {
            let payload = try await fetch(credential: credential)
            guard let object = payload as? [String: Any] else {
                return ConnectionTestResult(category: .malformed, message: "通用 HTTP 返回的不是 JSON 对象")
            }
            guard config.mapping.hasBalanceMapping
                    || config.mapping.hasCreditsMapping
                    || config.mapping.hasUsageMapping else {
                return ConnectionTestResult(
                    category: .malformed,
                    message: "至少配置一个余额 / 额度 / 用量映射字段后才能测试"
                )
            }
            guard mappingHits(object) else {
                return ConnectionTestResult(
                    category: .malformed,
                    message: "返回 JSON 未命中已配置的映射字段；请检查路径"
                )
            }
            return ConnectionTestResult(
                category: .success,
                message: "连接成功。能力：\(config.capabilities.summary)",
                capabilities: config.capabilities
            )
        } catch let failure as GenericHTTPFailure {
            return failure.result(capabilities: config.capabilities)
        } catch {
            return ConnectionTestResult(
                category: .unknown,
                message: Sanitizer.sanitize(error.localizedDescription, credential: credential),
                capabilities: config.capabilities
            )
        }
    }

    public func sync(account: Account, credential: String, now: Date = Date()) async -> SyncOutcome {
        do {
            let payload = try await fetch(credential: credential)
            guard let object = payload as? [String: Any] else {
                return failureOutcome(
                    message: "通用 HTTP 返回的不是 JSON 对象",
                    category: .malformed,
                    credential: credential
                )
            }
            return buildOutcome(account: account, object: object, now: now)
        } catch let failure as GenericHTTPFailure {
            return SyncOutcome(
                status: failure.status,
                error: Sanitizer.sanitize(failure.message, credential: credential),
                retryAfter: failure.retryAfter,
                capabilities: config.capabilities,
                source: "通用 HTTP",
                httpStatus: failure.httpStatus,
                failureCategory: failure.category
            )
        } catch {
            return failureOutcome(
                message: error.localizedDescription,
                category: .unknown,
                credential: credential
            )
        }
    }

    private func fetch(credential: String) async throws -> Any {
        let url: URL
        do {
            url = try config.requestURL()
        } catch let error as GenericHTTPConfigError {
            throw GenericHTTPFailure(
                category: .address,
                message: error.errorDescription ?? "只读端点 URL 无效",
                status: .failed
            )
        }
        let request = HTTPRequest(url: url, headers: headers(credential: credential))
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as HTTPTransportError {
            switch error {
            case .timedOut:
                throw GenericHTTPFailure(category: .timeout, message: error.description, status: .failed)
            case .redirectRejected:
                throw GenericHTTPFailure(category: .address, message: error.description, status: .failed)
            default:
                throw GenericHTTPFailure(category: .network, message: error.description, status: .failed)
            }
        } catch {
            throw GenericHTTPFailure(category: .network, message: error.localizedDescription, status: .failed)
        }

        switch response.status {
        case 200...299:
            break
        case 401:
            throw GenericHTTPFailure(
                category: .invalidCredential,
                message: "认证失败（HTTP 401），请检查 Key / Header",
                status: .invalidCredential,
                httpStatus: 401
            )
        case 403:
            throw GenericHTTPFailure(
                category: .permission,
                message: "权限或额度受限（HTTP 403）",
                status: .invalidCredential,
                httpStatus: 403
            )
        case 429:
            throw GenericHTTPFailure(
                category: .rateLimited,
                message: "请求被限流（HTTP 429），请稍后重试",
                status: .rateLimited,
                retryAfter: response.retryAfter,
                httpStatus: 429
            )
        case 400, 404, 405:
            throw GenericHTTPFailure(
                category: .address,
                message: "端点不存在或请求无效（HTTP \(response.status)）",
                status: .failed,
                httpStatus: response.status
            )
        default:
            throw GenericHTTPFailure(
                category: .unknown,
                message: "通用 HTTP 返回 HTTP \(response.status)",
                status: .failed,
                httpStatus: response.status
            )
        }

        do {
            return try JSONSerialization.jsonObject(with: response.body, options: [])
        } catch {
            throw GenericHTTPFailure(
                category: .malformed,
                message: "通用 HTTP 返回格式异常（非 JSON）",
                status: .failed,
                httpStatus: response.status
            )
        }
    }

    private func headers(credential: String) -> [String: String] {
        var headers = ["Accept": "application/json"]
        switch config.authMode {
        case .bearer:
            headers["Authorization"] = "Bearer \(credential)"
        case .header:
            let name = config.headerName.trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name.isEmpty ? "X-API-Key" : name] = credential
        }
        return headers
    }

    private func buildOutcome(account: Account, object: [String: Any], now: Date) -> SyncOutcome {
        let mapping = config.mapping
        var balances: [BalanceSnapshot] = []
        var quota: QuotaSnapshot?
        var records: [UsageRecord] = []

        if mapping.hasBalanceMapping,
           let total = JSONPathResolver.decimal(at: mapping.balanceTotal, in: object),
           let currency = JSONPathResolver.string(at: mapping.balanceCurrency, in: object) {
            let code = currency.uppercased()
            balances.append(BalanceSnapshot(
                accountId: account.id,
                currency: code,
                total: total,
                granted: JSONPathResolver.decimal(at: mapping.balanceGranted, in: object),
                toppedUp: JSONPathResolver.decimal(at: mapping.balanceToppedUp, in: object),
                isAvailable: true,
                asOf: now,
                source: "通用 HTTP · GET \(config.endpointPath)"
            ))
        }

        if mapping.hasCreditsMapping,
           let total = JSONPathResolver.decimal(at: mapping.creditsTotal, in: object),
           let used = JSONPathResolver.decimal(at: mapping.creditsUsed, in: object),
           let currency = JSONPathResolver.string(at: mapping.creditsCurrency, in: object) {
            quota = QuotaSnapshot(
                accountId: account.id,
                totalCredits: total,
                totalUsage: used,
                remaining: total - used,
                currency: currency.uppercased(),
                asOf: now,
                source: "通用 HTTP · GET \(config.endpointPath)"
            )
        }

        if mapping.hasUsageMapping {
            let day = JSONPathResolver.string(at: mapping.usageDay, in: object)
                ?? CalendarDay.string(
                    for: now,
                    timeZone: CalendarDay.utc,
                    calendar: {
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = CalendarDay.utc
                        return calendar
                    }()
                )
            let prompt = JSONPathResolver.int(at: mapping.promptTokens, in: object)
            let completion = JSONPathResolver.int(at: mapping.completionTokens, in: object)
            let requests = JSONPathResolver.int(at: mapping.requests, in: object)
            let cost = JSONPathResolver.decimal(at: mapping.cost, in: object)
            let currency = JSONPathResolver.string(at: mapping.usageCurrency, in: object)?.uppercased()
            if prompt != nil || completion != nil || requests != nil || cost != nil {
                records.append(UsageRecord(
                    accountId: account.id,
                    accountName: account.displayName,
                    provider: .genericHTTP,
                    day: day,
                    model: "generic-http",
                    providerName: "Generic HTTP",
                    promptTokens: prompt,
                    completionTokens: completion,
                    requests: requests,
                    cost: cost,
                    currency: currency,
                    source: "通用 HTTP · GET \(config.endpointPath)",
                    updatedAt: now
                ))
            }
        }

        let hasData = !balances.isEmpty || quota != nil || !records.isEmpty
        guard hasData else {
            return failureOutcome(
                message: "已配置映射未命中任何可保存数据",
                category: .malformed,
                credential: ""
            )
        }
        return SyncOutcome(
            status: .success,
            capabilities: config.capabilities,
            balanceSnapshots: balances,
            quotaSnapshot: quota,
            usageRecords: records,
            source: "通用 HTTP"
        )
    }

    private func mappingHits(_ object: [String: Any]) -> Bool {
        let paths = [
            config.mapping.balanceTotal, config.mapping.balanceCurrency,
            config.mapping.creditsTotal, config.mapping.creditsUsed,
            config.mapping.creditsCurrency, config.mapping.usageDay,
            config.mapping.promptTokens, config.mapping.completionTokens,
            config.mapping.requests, config.mapping.cost, config.mapping.usageCurrency
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return paths.contains { JSONPathResolver.value(at: $0, in: object) != nil }
    }

    private func failureOutcome(
        message: String,
        category: ConnectionTestResult.Category,
        credential: String
    ) -> SyncOutcome {
        SyncOutcome(
            status: .failed,
            error: Sanitizer.sanitize(message, credential: credential),
            capabilities: config.capabilities,
            source: "通用 HTTP",
            failureCategory: category
        )
    }
}

private struct GenericHTTPFailure: Error {
    var category: ConnectionTestResult.Category
    var message: String
    var status: SyncStatus
    var retryAfter: TimeInterval?
    var httpStatus: Int?

    init(
        category: ConnectionTestResult.Category,
        message: String,
        status: SyncStatus,
        retryAfter: TimeInterval? = nil,
        httpStatus: Int? = nil
    ) {
        self.category = category
        self.message = message
        self.status = status
        self.retryAfter = retryAfter
        self.httpStatus = httpStatus
    }

    func result(capabilities: ProviderCapabilities) -> ConnectionTestResult {
        ConnectionTestResult(
            category: category,
            message: message,
            capabilities: capabilities,
            retryAfter: retryAfter
        )
    }
}
