import Foundation

public enum L10n {
    public static func t(_ key: String) -> String {
        LocalizationStore.shared.tr(key)
    }

    public static func f(_ key: String, _ arguments: Any...) -> String {
        LocalizationStore.shared.format(key, arguments)
    }
}

public enum AlertMetricText {
    public static func localized(_ metric: String) -> String {
        let parts = metric.components(separatedBy: " · ")
        guard parts.count == 2 else { return L10n.t(metric) }
        return parts.map { L10n.t($0) }.joined(separator: " · ")
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    public var id: String { rawValue }

    public var builtinLocale: String? {
        switch self {
        case .system: return nil
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .english: return "en"
        }
    }

    public static func resolveSystem(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferred {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw")
                || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") {
                return .traditionalChinese
            }
            if normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .simplifiedChinese
    }
}

public struct LocalizedLanguage: Identifiable, Equatable, Sendable {
    public var id: String
    public var locale: String
    public var displayName: String
    public var isImported: Bool
    public var fallbackLocale: String?

    public init(
        id: String,
        locale: String,
        displayName: String,
        isImported: Bool,
        fallbackLocale: String? = nil
    ) {
        self.id = id
        self.locale = locale
        self.displayName = displayName
        self.isImported = isImported
        self.fallbackLocale = fallbackLocale
    }
}

public struct LocalizedLanguagePack: Codable, Equatable, Sendable {
    public static let supportedFormatVersion = 1
    public static let maxFileSize = 1_048_576

    public var formatVersion: Int
    public var locale: String
    public var displayName: String
    public var fallbackLocale: String
    public var appVersionRange: String
    public var strings: [String: String]
    public var importedAt: Date?
    public var sourceFileName: String?

    public init(
        formatVersion: Int,
        locale: String,
        displayName: String,
        fallbackLocale: String,
        appVersionRange: String,
        strings: [String: String],
        importedAt: Date? = nil,
        sourceFileName: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.locale = locale
        self.displayName = displayName
        self.fallbackLocale = fallbackLocale
        self.appVersionRange = appVersionRange
        self.strings = strings
        self.importedAt = importedAt
        self.sourceFileName = sourceFileName
    }
}

public enum LanguagePackError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge
    case invalidUTF8
    case malformedJSON(String)
    case duplicateKey(String)
    case missingField(String)
    case invalidField(String)
    case unsupportedFormatVersion(Int)
    case unsupportedLocale(String)
    case builtinLocale(String)
    case invalidLocale(String)
    case fallbackCycle(String)
    case versionRangeInvalid(String)
    case appVersionIncompatible(String)
    case nestedValue(String)
    case unsafeContent(String)
    case placeholderMismatch(String)
    case storageFailure(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "语言包超过 1MB 上限"
        case .invalidUTF8:
            return "语言包不是有效的 UTF-8 文本"
        case .malformedJSON(let detail):
            return "语言包 JSON 格式错误：\(detail)"
        case .duplicateKey(let key):
            return "语言包包含重复 key：\(key)"
        case .missingField(let field):
            return "语言包缺少必填字段：\(field)"
        case .invalidField(let field):
            return "语言包字段类型或内容无效：\(field)"
        case .unsupportedFormatVersion(let version):
            return "语言包 formatVersion 不受支持：\(version)"
        case .unsupportedLocale(let locale):
            return "语言包 locale 不受支持：\(locale)"
        case .builtinLocale(let locale):
            return "内置语言不可被语言包覆盖：\(locale)"
        case .invalidLocale(let locale):
            return "语言包 locale 不是有效的 BCP-47：\(locale)"
        case .fallbackCycle(let locale):
            return "语言包回退链存在循环：\(locale)"
        case .versionRangeInvalid(let range):
            return "语言包 appVersionRange 无法解析：\(range)"
        case .appVersionIncompatible(let range):
            return "语言包与当前应用版本不兼容：\(range)"
        case .nestedValue(let key):
            return "语言包 strings 只允许扁平字符串：\(key)"
        case .unsafeContent(let detail):
            return "语言包包含不安全内容：\(detail)"
        case .placeholderMismatch(let key):
            return "语言包占位符与内置文案不一致：\(key)"
        case .storageFailure(let detail):
            return "语言包保存失败：\(detail)"
        }
    }
}

public final class LocalizationStore: @unchecked Sendable {
    public static let shared = LocalizationStore()

    private let lock = NSLock()
    private let packsDirectory: URL
    private let builtinCatalogs: [String: [String: String]]
    private var sourceToKey: [String: String] = [:]
    private var dynamicKeys: [(key: String, template: String, regex: NSRegularExpression)] = []
    private var packsByLocale: [String: LocalizedLanguagePack] = [:]
    private var selectedLanguage: AppLanguage = .simplifiedChinese
    private var selectedPackLocale: String?
    private var cachedTranslations: [String: String] = [:]

    public init(
        packsDirectory: URL? = nil,
        builtinCatalogs: [String: [String: String]]? = nil
    ) {
        self.packsDirectory = packsDirectory ?? Self.defaultPacksDirectory()
        self.builtinCatalogs = builtinCatalogs ?? Self.loadBuiltinCatalogs()
        rebuildIndexes()
        loadPacks()
        resolveSelectedLocale()
    }

    public static func defaultPacksDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Overplay", isDirectory: true)
            .appendingPathComponent("LanguagePacks", isDirectory: true)
    }

    // MARK: - Selection

    public var language: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return selectedLanguage
    }

    public var effectiveLocale: String {
        lock.lock(); defer { lock.unlock() }
        return effectiveLocaleLocked()
    }

    public var currentLocale: Locale {
        Locale(identifier: effectiveLocale)
    }

    public var isUsingImportedPack: Bool {
        lock.lock(); defer { lock.unlock() }
        return selectedPackLocale != nil
    }

    public var selectedPack: LocalizedLanguagePack? {
        lock.lock(); defer { lock.unlock() }
        guard let locale = selectedPackLocale else { return nil }
        return packsByLocale[locale]
    }

    public func setLanguage(_ language: AppLanguage) {
        lock.lock()
        selectedLanguage = language
        selectedPackLocale = nil
        cachedTranslations.removeAll()
        lock.unlock()
    }

    public func setImportedLanguage(locale: String) throws {
        lock.lock()
        guard packsByLocale[locale] != nil else {
            lock.unlock()
            throw LanguagePackError.unsupportedLocale(locale)
        }
        selectedPackLocale = locale
        selectedLanguage = .system
        cachedTranslations.removeAll()
        lock.unlock()
    }

    public func select(locale: String?) {
        guard let locale, locale != AppLanguage.system.rawValue else {
            setLanguage(.system)
            return
        }
        if Self.builtinLocales.contains(locale) {
            if locale == "zh-Hans" { setLanguage(.simplifiedChinese) }
            else if locale == "zh-Hant" { setLanguage(.traditionalChinese) }
            else if locale == "en" { setLanguage(.english) }
            return
        }
        try? setImportedLanguage(locale: locale)
    }

    public var resolvedLocale: String {
        effectiveLocale
    }

    public var availableLanguages: [LocalizedLanguage] {
        lock.lock(); defer { lock.unlock() }
        let systemResolved = AppLanguage.resolveSystem()
        var result: [LocalizedLanguage] = [
            LocalizedLanguage(
                id: AppLanguage.system.rawValue,
                locale: systemResolved.builtinLocale ?? "zh-Hans",
                displayName: translateLocked("language.system") + "（" + translateLocked(Self.languageNameKey(systemResolved)) + "）",
                isImported: false
            ),
            LocalizedLanguage(
                id: AppLanguage.simplifiedChinese.rawValue,
                locale: "zh-Hans",
                displayName: translateLocked("language.zhHans"),
                isImported: false
            ),
            LocalizedLanguage(
                id: AppLanguage.traditionalChinese.rawValue,
                locale: "zh-Hant",
                displayName: translateLocked("language.zhHant"),
                isImported: false
            ),
            LocalizedLanguage(
                id: AppLanguage.english.rawValue,
                locale: "en",
                displayName: translateLocked("language.en"),
                isImported: false
            )
        ]
        for pack in packsByLocale.values.sorted(by: { $0.displayName < $1.displayName }) {
            result.append(LocalizedLanguage(
                id: pack.locale,
                locale: pack.locale,
                displayName: pack.displayName,
                isImported: true,
                fallbackLocale: pack.fallbackLocale
            ))
        }
        return result
    }

    public var selectedIdentifier: String {
        lock.lock(); defer { lock.unlock() }
        if let pack = selectedPackLocale { return pack }
        return selectedLanguage.rawValue
    }

    // MARK: - Translation

    public func tr(_ keyOrSource: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let cached = cachedTranslations[keyOrSource] { return cached }
        let result = translateLocked(keyOrSource)
        cachedTranslations[keyOrSource] = result
        return result
    }

    public func format(_ key: String, _ arguments: Any...) -> String {
        let template = tr(key)
        return substitute(template: template, arguments: arguments)
    }

    public func contains(key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return builtinCatalogs["zh-Hans"]?[key] != nil
    }

    public func sourceTemplate(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return builtinCatalogs["zh-Hans"]?[key]
    }

    public func builtinLocaleKeys() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(builtinCatalogs["zh-Hans"]?.keys ?? Dictionary<String, String>().keys)
    }

    public func builtinCatalog(for locale: String) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return builtinCatalogs[locale] ?? [:]
    }

    private func translateLocked(_ keyOrSource: String) -> String {
        let canonical = canonicalKeyLocked(keyOrSource)
        if let template = translationLocked(for: canonical) {
            return template
        }
        if let source = builtinCatalogs["zh-Hans"]?[canonical] {
            return source
        }
        // Dynamic calls pass a fully formatted source string. Match against
        // the zh-Hans templates and re-render in the selected language.
        for entry in dynamicKeys {
            let range = NSRange(keyOrSource.startIndex..., in: keyOrSource)
            guard let match = entry.regex.firstMatch(in: keyOrSource, range: range) else { continue }
            let template = translationLocked(for: entry.key)
                ?? builtinCatalogs["zh-Hans"]?[entry.key]
                ?? entry.template
            var captures: [String] = []
            for index in 1..<match.numberOfRanges {
                if let captureRange = Range(match.range(at: index), in: keyOrSource) {
                    captures.append(String(keyOrSource[captureRange]))
                } else {
                    captures.append("")
                }
            }
            return substitute(template: template, arguments: captures)
        }
        return keyOrSource
    }

    private func canonicalKeyLocked(_ keyOrSource: String) -> String {
        if builtinCatalogs["zh-Hans"]?[keyOrSource] != nil { return keyOrSource }
        if let key = sourceToKey[keyOrSource] { return key }
        return keyOrSource
    }

    private func translationLocked(for key: String) -> String? {
        if let packLocale = selectedPackLocale, let pack = packsByLocale[packLocale] {
            if let value = packValueLocked(pack, key: key) { return value }
            let builtinFallback = fallbackBuiltinLocaleLocked(for: pack) ?? "zh-Hans"
            return builtinCatalogs[builtinFallback]?[key]
                ?? builtinCatalogs["zh-Hans"]?[key]
                ?? builtinCatalogs["en"]?[key]
        }
        switch selectedLanguage {
        case .system:
            let resolved = AppLanguage.resolveSystem().builtinLocale ?? "zh-Hans"
            return builtinCatalogs[resolved]?[key]
                ?? builtinCatalogs["zh-Hans"]?[key]
                ?? builtinCatalogs["en"]?[key]
        case .simplifiedChinese:
            return builtinCatalogs["zh-Hans"]?[key]
        case .traditionalChinese:
            return builtinCatalogs["zh-Hant"]?[key]
                ?? builtinCatalogs["zh-Hans"]?[key]
                ?? builtinCatalogs["en"]?[key]
        case .english:
            return builtinCatalogs["en"]?[key]
                ?? builtinCatalogs["zh-Hans"]?[key]
        }
    }

    private func packValueLocked(_ pack: LocalizedLanguagePack, key: String) -> String? {
        if let value = pack.strings[key] { return value }
        if let source = builtinCatalogs["zh-Hans"]?[key], let value = pack.strings[source] {
            return value
        }
        if let fallbackKey = fallbackPackLocaleLocked(for: pack),
           let fallback = packsByLocale[fallbackKey] {
            return packValueLocked(fallback, key: key)
        }
        return nil
    }

    private func fallbackPackLocaleLocked(for pack: LocalizedLanguagePack) -> String? {
        var visited: Set<String> = [pack.locale]
        var current = pack.fallbackLocale
        while !current.isEmpty {
            if visited.contains(current) { return nil }
            visited.insert(current)
            if let next = packsByLocale[current] { return next.locale }
            if Self.builtinLocales.contains(current) { return nil }
            current = packsByLocale[current]?.fallbackLocale ?? ""
        }
        return nil
    }

    private func fallbackBuiltinLocaleLocked(for pack: LocalizedLanguagePack) -> String? {
        var visited: Set<String> = [pack.locale]
        var current = pack.fallbackLocale
        while !current.isEmpty {
            if visited.contains(current) { return nil }
            if Self.builtinLocales.contains(current) { return current }
            visited.insert(current)
            guard let next = packsByLocale[current] else { return nil }
            current = next.fallbackLocale
        }
        return nil
    }

    private func effectiveLocaleLocked() -> String {
        if let pack = selectedPackLocale { return pack }
        switch selectedLanguage {
        case .system: return AppLanguage.resolveSystem().builtinLocale ?? "zh-Hans"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .english: return "en"
        }
    }

    // MARK: - Packs

    public func importPack(
        data: Data,
        appVersion: String,
        sourceFileName: String? = nil
    ) throws -> LocalizedLanguagePack {
        let pack = try Self.validatePack(
            data: data,
            appVersion: appVersion,
            existingPacks: packsByLocale,
            builtinSourceTemplates: builtinCatalogs["zh-Hans"] ?? [:]
        )
        var stored = pack
        stored.importedAt = Date()
        stored.sourceFileName = sourceFileName
        try savePack(stored)
        lock.lock()
        packsByLocale[stored.locale] = stored
        cachedTranslations.removeAll()
        lock.unlock()
        return stored
    }

    public func removePack(locale: String) throws {
        guard !Self.builtinLocales.contains(locale) else {
            throw LanguagePackError.builtinLocale(locale)
        }
        lock.lock()
        let hadPack = packsByLocale.removeValue(forKey: locale) != nil
        if selectedPackLocale == locale {
            selectedPackLocale = nil
            selectedLanguage = .system
            cachedTranslations.removeAll()
        }
        lock.unlock()
        guard hadPack else { throw LanguagePackError.unsupportedLocale(locale) }
        let url = packURL(locale: locale)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw LanguagePackError.storageFailure(error.localizedDescription)
            }
        }
    }

    public func clearPacks() throws {
        lock.lock()
        let locales = Array(packsByLocale.keys)
        lock.unlock()
        for locale in locales {
            try? removePack(locale: locale)
        }
    }

    public var importedPacks: [LocalizedLanguagePack] {
        lock.lock(); defer { lock.unlock() }
        return packsByLocale.values.sorted { $0.displayName < $1.displayName }
    }

    public static func validatePack(
        data: Data,
        appVersion: String,
        existingPacks: [String: LocalizedLanguagePack] = [:],
        builtinSourceTemplates: [String: String] = [:]
    ) throws -> LocalizedLanguagePack {
        guard data.count <= LocalizedLanguagePack.maxFileSize else {
            throw LanguagePackError.fileTooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw LanguagePackError.invalidUTF8
        }
        try rejectUnsafeRawContent(text)
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw LanguagePackError.malformedJSON(error.localizedDescription)
        }
        guard let object = root as? [String: Any] else {
            throw LanguagePackError.malformedJSON("根节点必须是对象")
        }
        try Self.detectDuplicateKeys(in: text)
        guard let formatVersion = object["formatVersion"] as? Int else {
            if object["formatVersion"] == nil {
                throw LanguagePackError.missingField("formatVersion")
            }
            throw LanguagePackError.invalidField("formatVersion")
        }
        guard formatVersion == LocalizedLanguagePack.supportedFormatVersion else {
            throw LanguagePackError.unsupportedFormatVersion(formatVersion)
        }
        guard let locale = object["locale"] as? String else {
            throw object["locale"] == nil
                ? LanguagePackError.missingField("locale")
                : LanguagePackError.invalidField("locale")
        }
        try Self.validateLocale(locale)
        guard !Self.builtinLocales.contains(locale) else {
            throw LanguagePackError.builtinLocale(locale)
        }
        guard let displayName = object["displayName"] as? String else {
            throw object["displayName"] == nil
                ? LanguagePackError.missingField("displayName")
                : LanguagePackError.invalidField("displayName")
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 80 else {
            throw LanguagePackError.invalidField("displayName")
        }
        try Self.rejectUnsafeValue(trimmedName, key: "displayName")
        guard let fallbackLocale = object["fallbackLocale"] as? String else {
            throw object["fallbackLocale"] == nil
                ? LanguagePackError.missingField("fallbackLocale")
                : LanguagePackError.invalidField("fallbackLocale")
        }
        guard !fallbackLocale.isEmpty else {
            throw LanguagePackError.invalidField("fallbackLocale")
        }
        if fallbackLocale == locale {
            throw LanguagePackError.fallbackCycle(locale)
        }
        try Self.validateLocale(fallbackLocale)
        if let cycle = Self.detectFallbackCycle(
            locale: locale,
            fallback: fallbackLocale,
            existing: existingPacks
        ) {
            throw LanguagePackError.fallbackCycle(cycle)
        }
        guard let versionRange = object["appVersionRange"] as? String else {
            throw object["appVersionRange"] == nil
                ? LanguagePackError.missingField("appVersionRange")
                : LanguagePackError.invalidField("appVersionRange")
        }
        guard let range = SemanticVersionRange(versionRange) else {
            throw LanguagePackError.versionRangeInvalid(versionRange)
        }
        guard let version = SemanticVersion(appVersion) else {
            throw LanguagePackError.versionRangeInvalid(appVersion)
        }
        guard range.contains(version) else {
            throw LanguagePackError.appVersionIncompatible(versionRange)
        }
        guard let rawStrings = object["strings"] else {
            throw LanguagePackError.missingField("strings")
        }
        guard !(rawStrings is [Any]), !(rawStrings is [String]) else {
            throw LanguagePackError.invalidField("strings")
        }
        guard let strings = rawStrings as? [String: Any] else {
            throw LanguagePackError.invalidField("strings")
        }
        guard !strings.isEmpty else {
            throw LanguagePackError.invalidField("strings")
        }
        var validated: [String: String] = [:]
        for (key, value) in strings {
            guard key.count > 0, key.count <= 160 else {
                throw LanguagePackError.invalidField("strings.key")
            }
            try Self.rejectUnsafeKey(key)
            guard let string = value as? String else {
                throw LanguagePackError.nestedValue(key)
            }
            guard !string.isEmpty, string.count <= 2000 else {
                throw LanguagePackError.invalidField("strings[\(key)]")
            }
            try Self.rejectUnsafeValue(string, key: key)
            let sourceKey = builtinSourceTemplates[key] != nil
                ? key
                : builtinSourceTemplates.first(where: { $0.value == key })?.key
            if let sourceKey, let source = builtinSourceTemplates[sourceKey] {
                let sourceSlots = Self.placeholders(in: source)
                let valueSlots = Self.placeholders(in: string)
                if sourceSlots != valueSlots {
                    throw LanguagePackError.placeholderMismatch(key)
                }
                if sourceKey == "demo.disclaimer",
                   string.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                    throw LanguagePackError.invalidField("demo.disclaimer")
                }
            }
            validated[key] = string
        }
        return LocalizedLanguagePack(
            formatVersion: formatVersion,
            locale: locale,
            displayName: trimmedName,
            fallbackLocale: fallbackLocale,
            appVersionRange: versionRange,
            strings: validated
        )
    }

    private static func builtinKey(forSource source: String, in templates: [String: String]) -> String? {
        templates.first(where: { $0.value == source })?.key
    }

    // MARK: - Indexes

    private func rebuildIndexes() {
        guard let zh = builtinCatalogs["zh-Hans"] else { return }
        sourceToKey = [:]
        dynamicKeys = []
        for (key, template) in zh {
            sourceToKey[template] = key
            if template.contains("{") {
                let regex = try? NSRegularExpression(
                    pattern: regexPattern(for: template),
                    options: []
                )
                if let regex {
                    dynamicKeys.append((key, template, regex))
                }
            }
        }
        dynamicKeys.sort { $0.template.count > $1.template.count }
    }

    private func regexPattern(for template: String) -> String {
        let ns = template as NSString
        guard let placeholder = try? NSRegularExpression(pattern: "\\{[0-9]+\\}") else {
            return "^" + NSRegularExpression.escapedPattern(for: template) + "$"
        }
        let matches = placeholder.matches(
            in: template,
            range: NSRange(location: 0, length: ns.length)
        )
        var result = "^"
        var location = 0
        for match in matches {
            let prefix = ns.substring(
                with: NSRange(location: location, length: match.range.location - location)
            )
            result += NSRegularExpression.escapedPattern(for: prefix)
            result += "(?s:(.*?))"
            location = match.range.location + match.range.length
        }
        result += NSRegularExpression.escapedPattern(for: ns.substring(from: location))
        return result + "$"
    }

    private func substitute(template: String, arguments: [Any]) -> String {
        var result = template
        for (index, argument) in arguments.enumerated() {
            result = result.replacingOccurrences(
                of: "{\(index)}",
                with: String(describing: argument)
            )
        }
        return result
    }

    // MARK: - Storage

    private func loadPacks() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: packsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let pack = try? Self.decodeStoredPack(data: data) else { continue }
            packsByLocale[pack.locale] = pack
        }
    }

    private static func decodeStoredPack(data: Data) throws -> LocalizedLanguagePack {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LocalizedLanguagePack.self, from: data)
    }

    private func savePack(_ pack: LocalizedLanguagePack) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: packsDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(pack)
            let url = packURL(locale: pack.locale)
            let temp = url.appendingPathExtension("tmp")
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temp, to: url)
        } catch {
            throw LanguagePackError.storageFailure(error.localizedDescription)
        }
    }

    private func packURL(locale: String) -> URL {
        packsDirectory.appendingPathComponent("\(locale).json")
    }

    private func resolveSelectedLocale() {
        if let selectedPackLocale, packsByLocale[selectedPackLocale] == nil {
            self.selectedPackLocale = nil
        }
    }

    private static let builtinLocales: Set<String> = ["zh-Hans", "zh-Hant", "en"]

    private static func languageNameKey(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese, .system: return "language.zhHans"
        case .traditionalChinese: return "language.zhHant"
        case .english: return "language.en"
        }
    }

    private static func detectDuplicateKeys(in text: String) throws {
        // JSONSerialization keeps the last duplicate, so scan the raw text.
        var index = text.startIndex
        var containers: [Character] = []
        var keys: [Set<String>] = []
        var expectingKey = false
        var lastString: String?
        var lastStringWasKey = false

        func skipWhitespace() {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
        }

        func parseString() -> String? {
            guard index < text.endIndex, text[index] == "\"" else { return nil }
            index = text.index(after: index)
            var result = ""
            var escaped = false
            while index < text.endIndex {
                let ch = text[index]
                index = text.index(after: index)
                if escaped {
                    escaped = false
                    switch ch {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "u":
                        var code = ""
                        for _ in 0..<4 where index < text.endIndex {
                            code.append(text[index])
                            index = text.index(after: index)
                        }
                        result.append("\\u\(code)")
                    default: result.append(ch)
                    }
                    continue
                }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { return result }
                result.append(ch)
            }
            return nil
        }

        while index < text.endIndex {
            skipWhitespace()
            guard index < text.endIndex else { break }
            let ch = text[index]
            switch ch {
            case "{":
                containers.append("{")
                keys.append([])
                expectingKey = true
                lastStringWasKey = false
                index = text.index(after: index)
            case "}":
                if !containers.isEmpty { containers.removeLast() }
                if !keys.isEmpty { keys.removeLast() }
                expectingKey = false
                lastStringWasKey = false
                index = text.index(after: index)
            case "[":
                containers.append("[")
                keys.append([])
                expectingKey = false
                lastStringWasKey = false
                index = text.index(after: index)
            case "]":
                if !containers.isEmpty { containers.removeLast() }
                if !keys.isEmpty { keys.removeLast() }
                expectingKey = false
                lastStringWasKey = false
                index = text.index(after: index)
            case ":":
                if lastStringWasKey, let key = lastString, !keys.isEmpty {
                    if !keys[keys.count - 1].insert(key).inserted {
                        throw LanguagePackError.duplicateKey(key)
                    }
                }
                expectingKey = false
                lastStringWasKey = false
                index = text.index(after: index)
            case ",":
                expectingKey = containers.last == "{"
                lastStringWasKey = false
                index = text.index(after: index)
            case "\"":
                lastString = parseString()
                lastStringWasKey = expectingKey && containers.last == "{"
            default:
                expectingKey = false
                lastStringWasKey = false
                index = text.index(after: index)
            }
        }
    }

    private static func rejectUnsafeRawContent(_ text: String) throws {
        let lower = text.lowercased()
        if lower.contains("<script") || lower.contains("javascript:") || lower.contains("onerror=") {
            throw LanguagePackError.unsafeContent("脚本内容")
        }
    }

    private static func validateLocale(_ locale: String) throws {
        let pattern = "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"
        guard locale.range(of: pattern, options: .regularExpression) != nil else {
            throw LanguagePackError.invalidLocale(locale)
        }
    }

    private static func rejectUnsafeKey(_ key: String) throws {
        if key.contains("..") || key.contains("/") || key.contains("\\") {
            throw LanguagePackError.unsafeContent("key \(key)")
        }
        try rejectUnsafeValue(key, key: key)
    }

    private static func rejectUnsafeValue(_ value: String, key: String) throws {
        let lower = value.lowercased()
        if lower.contains("<script") || lower.contains("javascript:") || lower.contains("onerror=") {
            throw LanguagePackError.unsafeContent(key)
        }
        if value.unicodeScalars.contains(where: { $0.value == 0 }) {
            throw LanguagePackError.unsafeContent(key)
        }
    }

    private static func detectFallbackCycle(
        locale: String,
        fallback: String,
        existing: [String: LocalizedLanguagePack]
    ) -> String? {
        var visited: Set<String> = [locale]
        var current = fallback
        while true {
            if visited.contains(current) { return current }
            if builtinLocales.contains(current) { return nil }
            guard let pack = existing[current] else { return nil }
            visited.insert(current)
            current = pack.fallbackLocale
        }
    }

    private static func placeholders(in template: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9]+)\\}") else { return [] }
        let range = NSRange(template.startIndex..., in: template)
        var result: Set<Int> = []
        for match in regex.matches(in: template, range: range) {
            if let capture = Range(match.range(at: 1), in: template),
               let value = Int(template[capture]) {
                result.insert(value)
            }
        }
        return result
    }

    private static func loadBuiltinCatalogs() -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let url = Bundle.module.url(
                forResource: locale,
                withExtension: "json",
                subdirectory: "Localization"
            ) ?? Bundle.module.url(
                forResource: locale,
                withExtension: "json",
                subdirectory: "Resources/Localization"
            ) ?? Bundle.module.url(
                forResource: locale,
                withExtension: "json"
            )
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode([String: String].self, from: data) else {
                result[locale] = [:]
                continue
            }
            result[locale] = catalog
        }
        return result
    }
}

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public var components: [Int]

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var values: [Int] = []
        for part in parts {
            let digits = part.prefix(while: { $0.isNumber })
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            values.append(value)
        }
        components = values
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct SemanticVersionRange: Equatable, Sendable {
    private struct Constraint: Equatable, Sendable {
        enum Operator: String, Sendable { case gte = ">=", gt = ">", lte = "<=", lt = "<", eq = "=" }
        var op: Operator
        var version: SemanticVersion
    }

    private var constraints: [Constraint]

    public init?(_ text: String) {
        let tokens = text
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }
        var parsed: [Constraint] = []
        var index = 0
        let operators: [Constraint.Operator] = [.gte, .lte, .gt, .lt, .eq]
        while index < tokens.count {
            let token = tokens[index]
            if token == ">=" || token == "<=" || token == ">" || token == "<" || token == "=" {
                guard index + 1 < tokens.count,
                      let op = Constraint.Operator(rawValue: token),
                      let version = SemanticVersion(tokens[index + 1]) else { return nil }
                parsed.append(Constraint(op: op, version: version))
                index += 2
                continue
            }
            if let op = operators.first(where: { token.hasPrefix($0.rawValue) }) {
                let remainder = String(token.dropFirst(op.rawValue.count))
                guard !remainder.isEmpty, let version = SemanticVersion(remainder) else { return nil }
                parsed.append(Constraint(op: op, version: version))
                index += 1
                continue
            }
            if let version = SemanticVersion(token) {
                parsed.append(Constraint(op: .eq, version: version))
                index += 1
                continue
            }
            return nil
        }
        constraints = parsed
    }

    public func contains(_ version: SemanticVersion) -> Bool {
        constraints.allSatisfy { constraint in
            switch constraint.op {
            case .gte: return version >= constraint.version
            case .gt: return version > constraint.version
            case .lte: return version <= constraint.version
            case .lt: return version < constraint.version
            case .eq: return version == constraint.version
            }
        }
    }
}
