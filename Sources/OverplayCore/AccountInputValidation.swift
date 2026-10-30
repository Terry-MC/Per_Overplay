import Foundation

public enum AccountValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyCredential
    case duplicateName
    case missingGenericConfig
    case missingMapping
    case invalidGenericConfig(GenericHTTPConfigError)

    public var errorDescription: String? {
        switch self {
        case .emptyCredential: return "API Key / Management Key 不能为空"
        case .duplicateName: return "同厂商下已存在同名账户，请使用不同显示名称"
        case .missingGenericConfig: return "通用 HTTP 缺少端点配置"
        case .missingMapping: return "通用 HTTP 至少配置一个余额 / 额度 / 用量映射字段"
        case .invalidGenericConfig(let error):
            return error.errorDescription
        }
    }
}

public enum AccountInputValidator {
    /// 返回实际使用的显示名称。
    public static func validateNewAccount(
        provider: ProviderKind,
        name: String,
        credential: String,
        genericConfig: GenericHTTPConfig?,
        existingAccounts: [Account]
    ) throws -> String {
        let key = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AccountValidationError.emptyCredential }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? provider.displayName : trimmedName
        if existingAccounts.contains(where: {
            $0.provider == provider
                && $0.displayName.caseInsensitiveCompare(resolvedName) == .orderedSame
        }) {
            throw AccountValidationError.duplicateName
        }
        if provider == .genericHTTP {
            guard let genericConfig else { throw AccountValidationError.missingGenericConfig }
            guard genericConfig.mapping.hasBalanceMapping
                    || genericConfig.mapping.hasCreditsMapping
                    || genericConfig.mapping.hasUsageMapping else {
                throw AccountValidationError.missingMapping
            }
            do {
                _ = try genericConfig.requestURL()
            } catch let error as GenericHTTPConfigError {
                throw AccountValidationError.invalidGenericConfig(error)
            }
        }
        return resolvedName
    }
}
