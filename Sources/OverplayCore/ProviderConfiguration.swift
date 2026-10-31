import Foundation

// MARK: - Generic HTTP

public enum GenericAuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case bearer
    case header

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bearer: return "Authorization: Bearer"
        case .header: return "自定义 Header"
        }
    }
}

public struct GenericFieldMapping: Codable, Equatable, Sendable {
    public var balanceTotal: String
    public var balanceCurrency: String
    public var balanceGranted: String
    public var balanceToppedUp: String
    public var creditsTotal: String
    public var creditsUsed: String
    public var creditsCurrency: String
    public var usageDay: String
    public var promptTokens: String
    public var completionTokens: String
    public var requests: String
    public var cost: String
    public var usageCurrency: String

    public init(
        balanceTotal: String = "",
        balanceCurrency: String = "",
        balanceGranted: String = "",
        balanceToppedUp: String = "",
        creditsTotal: String = "",
        creditsUsed: String = "",
        creditsCurrency: String = "",
        usageDay: String = "",
        promptTokens: String = "",
        completionTokens: String = "",
        requests: String = "",
        cost: String = "",
        usageCurrency: String = ""
    ) {
        self.balanceTotal = balanceTotal
        self.balanceCurrency = balanceCurrency
        self.balanceGranted = balanceGranted
        self.balanceToppedUp = balanceToppedUp
        self.creditsTotal = creditsTotal
        self.creditsUsed = creditsUsed
        self.creditsCurrency = creditsCurrency
        self.usageDay = usageDay
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.requests = requests
        self.cost = cost
        self.usageCurrency = usageCurrency
    }

    public var hasBalanceMapping: Bool {
        !balanceTotal.trimmed.isEmpty && !balanceCurrency.trimmed.isEmpty
    }

    public var hasCreditsMapping: Bool {
        !creditsTotal.trimmed.isEmpty && !creditsUsed.trimmed.isEmpty && !creditsCurrency.trimmed.isEmpty
    }

    public var hasUsageMapping: Bool {
        !promptTokens.trimmed.isEmpty || !completionTokens.trimmed.isEmpty
            || !requests.trimmed.isEmpty || !cost.trimmed.isEmpty
    }

    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            balance: hasBalanceMapping,
            usage: hasUsageMapping,
            cost: !cost.trimmed.isEmpty && !usageCurrency.trimmed.isEmpty,
            credits: hasCreditsMapping,
            note: "通用 HTTP · 仅映射字段可用"
        )
    }
}

public struct GenericHTTPConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var endpointPath: String
    public var authMode: GenericAuthMode
    public var headerName: String
    public var mapping: GenericFieldMapping

    public init(
        baseURL: String,
        endpointPath: String = "/",
        authMode: GenericAuthMode = .bearer,
        headerName: String = "X-API-Key",
        mapping: GenericFieldMapping = GenericFieldMapping()
    ) {
        self.baseURL = baseURL
        self.endpointPath = endpointPath
        self.authMode = authMode
        self.headerName = headerName
        self.mapping = mapping
    }

    public var capabilities: ProviderCapabilities {
        mapping.capabilities
    }

    public func requestURL() throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmed) else {
            throw GenericHTTPConfigError.invalidURL
        }
        guard components.scheme?.lowercased() == "https" else {
            throw GenericHTTPConfigError.requiresHTTPS
        }
        guard components.host?.trimmed.isEmpty == false else {
            throw GenericHTTPConfigError.invalidURL
        }
        if components.user != nil || components.password != nil {
            throw GenericHTTPConfigError.embeddedCredentials
        }
        let path = endpointPath.trimmed
        if !path.isEmpty {
            components.path = path.hasPrefix("/") ? path : "/" + path
        }
        guard let url = components.url else {
            throw GenericHTTPConfigError.invalidURL
        }
        if let validationError = GenericHTTPURLValidator.validate(url) {
            throw validationError
        }
        return url
    }
}

public enum GenericHTTPConfigError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case requiresHTTPS
    case embeddedCredentials
    case privateAddress
    case metadataAddress
    case localhost

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return L10n.t("core.genericHTTP.59d2e3c547")
        case .requiresHTTPS: return L10n.t("core.providerConfig.778f41a924")
        case .embeddedCredentials: return L10n.t("core.providerConfig.d263318535")
        case .privateAddress: return L10n.t("core.providerConfig.f81c5b661c")
        case .metadataAddress: return L10n.t("core.providerConfig.d916dc3b2c")
        case .localhost: return L10n.t("core.providerConfig.00e7c6ca8d")
        }
    }
}

public enum GenericHTTPURLValidator {
    public static func validate(_ url: URL) -> GenericHTTPConfigError? {
        guard url.scheme?.lowercased() == "https" else { return .requiresHTTPS }
        guard let host = url.host?.trimmed.lowercased(), !host.isEmpty else { return .invalidURL }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return .localhost
        }
        if host == "metadata.google.internal" {
            return .metadataAddress
        }

        let bareHost = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host
        if isPrivateIPv4(bareHost) || isPrivateIPv6(bareHost) {
            return .privateAddress
        }
        if bareHost == "169.254.169.254" {
            return .metadataAddress
        }
        return nil
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ 0...255 ~= $0 }) else { return false }
        let first = parts[0]
        let second = parts[1]
        if first == 10 || first == 127 || first == 0 { return true }
        if first == 172, (16...31).contains(second) { return true }
        if first == 192, second == 168 { return true }
        if first == 169, second == 254 { return true }
        if first == 100, (64...127).contains(second) { return true }
        if first == 198, (18...19).contains(second) { return true }
        if first >= 224 { return true }
        return false
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "::1" || value == "::" { return true }
        if value.hasPrefix("fe80:") || value.hasPrefix("fc") || value.hasPrefix("fd") {
            return true
        }
        if value.hasPrefix("::ffff:") {
            let tail = String(value.dropFirst("::ffff:".count))
            return isPrivateIPv4(tail)
        }
        return false
    }
}

public enum JSONPathResolver {
    /// 支持点号分隔的对象路径与数字下标；不支持通配符或多结果映射。
    public static func value(at path: String, in root: Any) -> Any? {
        let pieces = path.trimmed
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return nil }
        var current: Any = root
        for piece in pieces {
            if let dictionary = current as? [String: Any] {
                guard let next = dictionary[piece] else { return nil }
                current = next
            } else if let array = current as? [Any], let index = Int(piece), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }

    public static func string(at path: String, in root: Any) -> String? {
        guard let value = value(at: path, in: root) else { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    public static func decimal(at path: String, in root: Any) -> Decimal? {
        guard let value = value(at: path, in: root) else { return nil }
        if let text = value as? String {
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let number = value as? NSNumber {
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    public static func int(at path: String, in root: Any) -> Int? {
        guard let value = value(at: path, in: root) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
