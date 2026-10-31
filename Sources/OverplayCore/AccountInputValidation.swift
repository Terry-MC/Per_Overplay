import Foundation

public enum AccountValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyCredential
    case duplicateName
    case missingGenericConfig
    case missingMapping
    case invalidGenericConfig(GenericHTTPConfigError)

    public var errorDescription: String? {
        switch self {
        case .emptyCredential:
            return L10n.t("core.validation.c53fdaf1a3")
        case .duplicateName:
            return L10n.t("app.b1c29cc952")
        case .missingGenericConfig:
            return L10n.t("core.validation.5400a6a9c4")
        case .missingMapping:
            return L10n.t("core.validation.3530e92d40")
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
