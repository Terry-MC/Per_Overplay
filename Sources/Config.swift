import Foundation

struct OverlayConfig: Codable {
    var version: Int?
    var settings: SettingsConfig?
    var vendors: [VendorConfig]?
}

struct SettingsConfig: Codable {
    var pauseWhenHidden: Bool?
    var staggerSeconds: Double?
    var requestTimeoutSeconds: Double?
    var backoff: BackoffConfig?
}

struct BackoffConfig: Codable {
    var baseSeconds: Double?
    var maxSeconds: Double?
}

struct VendorConfig: Codable {
    var id: String
    var name: String
    var enabled: Bool?
    var method: String?
    var url: String
    var apiKey: String?
    var headers: [String: String]?
    var body: String?
    var intervalSeconds: Double?
    var fields: [FieldConfig]?

    var isEnabled: Bool { enabled ?? true }
    var displayName: String { name.isEmpty ? id : name }
    var resolvedMethod: String { (method ?? "GET").uppercased() }
    var resolvedInterval: TimeInterval { max(1, intervalSeconds ?? ResolvedSettings.defaultInterval) }
    var resolvedFields: [FieldConfig] { fields ?? [] }
}

struct FieldConfig: Codable {
    var label: String
    var path: String?
    var prefix: String?
    var suffix: String?
}

struct ResolvedSettings {
    static let defaultInterval: TimeInterval = 300

    var pauseWhenHidden: Bool
    var staggerSeconds: Double
    var requestTimeout: TimeInterval
    var backoffBase: TimeInterval
    var backoffMax: TimeInterval

    init(_ settings: SettingsConfig?) {
        pauseWhenHidden = settings?.pauseWhenHidden ?? true
        staggerSeconds = min(max(settings?.staggerSeconds ?? 0.5, 0), 10)
        requestTimeout = min(max(settings?.requestTimeoutSeconds ?? 15, 1), 120)
        let base = max(settings?.backoff?.baseSeconds ?? 10, 1)
        backoffBase = base
        backoffMax = max(settings?.backoff?.maxSeconds ?? 600, base)
    }
}

enum ConfigStore {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ds-overlay", isDirectory: true)
    }

    static var defaultConfigURL: URL {
        defaultDirectory.appendingPathComponent("config.json")
    }

    static var defaultStateURL: URL {
        defaultDirectory.appendingPathComponent("state.json")
    }

    static func ensureConfigFile(at url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard !fm.fileExists(atPath: url.path) else { return }
        guard let data = templateJSON.data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(from url: URL) throws -> OverlayConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(OverlayConfig.self, from: data)
    }

    static func permissionWarning(for configURL: URL) -> String? {
        var warnings: [String] = []
        if let mode = posixMode(configURL), mode & 0o077 != 0 {
            warnings.append(String(
                format: "配置文件权限 %@，建议 chmod 600 %@",
                octal(mode), configURL.path
            ))
        }
        let dir = configURL.deletingLastPathComponent().standardizedFileURL
        if dir == defaultDirectory.standardizedFileURL,
           let mode = posixMode(dir), mode & 0o077 != 0 {
            warnings.append(String(
                format: "配置目录权限 %@，建议 chmod 700 %@",
                octal(mode), dir.path
            ))
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    private static func posixMode(_ url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attrs[.posixPermissions] as? NSNumber else { return nil }
        return number.intValue
    }

    private static func octal(_ mode: Int) -> String {
        String(mode & 0o777, radix: 8)
    }

    static let templateJSON = #"""
    {
      "_note": "DSOverlay 配置。修改后约 1 秒内自动生效。intervalSeconds 为轮询间隔（秒，默认 300）；fields 的 path 支持 a.b[0].c 和 [键.名] 形式。API Key 仅保存在本机，请保持文件权限 600。",
      "version": 1,
      "settings": {
        "pauseWhenHidden": true,
        "staggerSeconds": 0.5,
        "requestTimeoutSeconds": 15,
        "backoff": { "baseSeconds": 10, "maxSeconds": 600 }
      },
      "vendors": [
        {
          "_note": "示例端点，接入前请核对厂商官方文档。把 enabled 改为 true 并填写 apiKey 后才会查询。",
          "id": "deepseek",
          "name": "DeepSeek",
          "enabled": false,
          "method": "GET",
          "url": "https://api.deepseek.com/user/balance",
          "apiKey": "",
          "headers": { "Authorization": "Bearer ${apiKey}" },
          "intervalSeconds": 300,
          "fields": [
            { "label": "余额", "path": "balance_infos[0].total_balance", "prefix": "¥" },
            { "label": "币种", "path": "balance_infos[0].currency" },
            { "label": "可用", "path": "is_available" }
          ]
        },
        {
          "_note": "Kimi / Moonshot 余额示例，端点以官方文档为准。",
          "id": "kimi",
          "name": "Kimi",
          "enabled": false,
          "url": "https://api.moonshot.cn/v1/users/me/balance",
          "apiKey": "",
          "headers": { "Authorization": "Bearer ${apiKey}" },
          "intervalSeconds": 600,
          "fields": [
            { "label": "可用余额", "path": "data.available_balance", "prefix": "¥" },
            { "label": "代金券", "path": "data.voucher_balance", "prefix": "¥" },
            { "label": "现金", "path": "data.cash_balance", "prefix": "¥" }
          ]
        },
        {
          "_note": "OpenRouter credits 示例，端点以官方文档为准。",
          "id": "openrouter",
          "name": "OpenRouter",
          "enabled": false,
          "url": "https://openrouter.ai/api/v1/credits",
          "apiKey": "",
          "headers": { "Authorization": "Bearer ${apiKey}" },
          "intervalSeconds": 300,
          "fields": [
            { "label": "credits", "path": "data.total_credits", "prefix": "$" },
            { "label": "已用", "path": "data.total_usage", "prefix": "$" }
          ]
        }
      ]
    }
    """#
}

enum ConfigValidation {
    static func validate(_ config: OverlayConfig) -> String? {
        var seen = Set<String>()
        for vendor in config.vendors ?? [] {
            let id = vendor.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty { return "厂商 id 不能为空" }
            if !seen.insert(id).inserted { return "厂商 id 重复：\(id)" }
        }
        return nil
    }
}

enum Placeholders {
    static func expand(_ text: String, apiKey: String) -> String {
        text.replacingOccurrences(of: "${apiKey}", with: apiKey)
    }

    static func requiresAPIKey(_ config: VendorConfig) -> Bool {
        var parts = [config.url, config.body ?? ""]
        parts.append(contentsOf: (config.headers ?? [:]).values)
        return parts.contains { $0.contains("${apiKey}") }
    }
}

enum JSONPath {
    static func value(at path: String?, in root: Any?) -> Any? {
        guard let root else { return nil }
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return root }

        var current: Any = root
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == "." {
                index = trimmed.index(after: index)
                continue
            }
            if character == "[" {
                guard let close = matchingBracket(in: trimmed, from: index) else { return nil }
                let inner = String(trimmed[trimmed.index(after: index)..<close])
                    .trimmingCharacters(in: .whitespaces)
                index = trimmed.index(after: close)

                if let offset = Int(inner), !inner.hasPrefix("\""), !inner.hasPrefix("'") {
                    guard offset >= 0,
                          let array = current as? [Any],
                          offset < array.count else { return nil }
                    current = array[offset]
                } else {
                    let key = unquote(inner)
                    guard let dictionary = current as? [String: Any],
                          let next = dictionary[key] else { return nil }
                    current = next
                }
            } else {
                var cursor = index
                var key = ""
                while cursor < trimmed.endIndex,
                      trimmed[cursor] != ".", trimmed[cursor] != "[" {
                    key.append(trimmed[cursor])
                    cursor = trimmed.index(after: cursor)
                }
                guard !key.isEmpty,
                      let dictionary = current as? [String: Any],
                      let next = dictionary[key] else { return nil }
                current = next
                index = cursor
            }
        }
        return current
    }

    private static func matchingBracket(in text: String, from open: String.Index) -> String.Index? {
        var cursor = text.index(after: open)
        var quote: Character?
        while cursor < text.endIndex {
            let character = text[cursor]
            if let currentQuote = quote {
                if character == currentQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "]" {
                return cursor
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2,
              let first = text.first,
              let last = text.last,
              first == last,
              first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }
}

enum ValueFormatter {
    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func display(_ value: Any?, prefix: String?, suffix: String?) -> String {
        guard let value, !(value is NSNull) else { return "—" }
        return (prefix ?? "") + format(value) + (suffix ?? "")
    }

    static func format(_ value: Any) -> String {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "是" : "否"
            }
            return decimal.string(from: number) ?? number.stringValue
        }
        if let text = value as? String { return text }
        if let flag = value as? Bool { return flag ? "是" : "否" }
        if value is NSNull { return "—" }
        if let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys]
        ), let text = String(data: data, encoding: .utf8) {
            return text.count > 240 ? String(text.prefix(240)) + "…" : text
        }
        return String(describing: value)
    }
}
