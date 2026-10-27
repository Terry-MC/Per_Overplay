import Foundation

struct FieldDisplay {
    let label: String
    let value: String
}

enum OverlayLog {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func info(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

final class VendorRuntime {
    let id: String
    var config: VendorConfig
    var settings: ResolvedSettings
    var nextDue: Date
    var task: URLSessionDataTask?
    var token = 0
    var failureCount = 0
    var lastSuccess: Date?
    var lastAttempt: Date?
    var httpStatus: Int?
    var error: String?
    var inFlight = false
    var lastResponse: Any?
    var fieldDisplays: [FieldDisplay] = []

    init(config: VendorConfig, settings: ResolvedSettings, nextDue: Date) {
        id = config.id
        self.config = config
        self.settings = settings
        self.nextDue = nextDue
        refreshFields()
    }

    var displayName: String { config.displayName }
    var interval: TimeInterval { config.resolvedInterval }

    func requestSignature() -> String {
        let headers = (config.headers ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\u{1F}")
        return [
            config.resolvedMethod,
            config.url,
            config.apiKey ?? "",
            headers,
            config.body ?? ""
        ].joined(separator: "\u{1E}")
    }

    func refreshFields() {
        let fields = config.resolvedFields
        if fields.isEmpty {
            if let lastResponse {
                fieldDisplays = [
                    FieldDisplay(label: "响应", value: ValueFormatter.format(lastResponse))
                ]
            } else {
                fieldDisplays = []
            }
            return
        }
        fieldDisplays = fields.map { field in
            let value = JSONPath.value(at: field.path, in: lastResponse)
            return FieldDisplay(
                label: field.label,
                value: ValueFormatter.display(value, prefix: field.prefix, suffix: field.suffix)
            )
        }
    }

    func cancel() {
        token += 1
        task?.cancel()
        task = nil
        inFlight = false
    }
}

final class Poller {
    private(set) var runtimes: [VendorRuntime] = []
    private(set) var settings = ResolvedSettings(nil)
    private(set) var isPaused = false

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func apply(config: OverlayConfig, now: Date = Date()) {
        settings = ResolvedSettings(config.settings)
        let enabled = (config.vendors ?? []).filter { $0.isEnabled }
        var oldByID: [String: VendorRuntime] = [:]
        for runtime in runtimes {
            oldByID[runtime.id] = runtime
        }

        var next: [VendorRuntime] = []
        for (index, vendor) in enabled.enumerated() {
            if let existing = oldByID[vendor.id] {
                oldByID.removeValue(forKey: vendor.id)
                if existing.requestSignature() == signature(of: vendor) {
                    let oldInterval = existing.interval
                    existing.config = vendor
                    existing.settings = settings
                    existing.refreshFields()
                    if abs(oldInterval - existing.interval) > 0.001 {
                        existing.nextDue = now.addingTimeInterval(existing.interval)
                    }
                    next.append(existing)
                    continue
                }
                existing.cancel()
            }
            let runtime = VendorRuntime(
                config: vendor,
                settings: settings,
                nextDue: now.addingTimeInterval(Double(index) * settings.staggerSeconds)
            )
            next.append(runtime)
        }

        for runtime in oldByID.values {
            runtime.cancel()
        }
        runtimes = next
        OverlayLog.info("config loaded: \(runtimes.count) enabled vendor(s)")
    }

    func setPaused(_ paused: Bool, now: Date = Date()) {
        guard paused != isPaused else { return }
        isPaused = paused
        guard !paused else {
            OverlayLog.info("polling paused")
            return
        }
        OverlayLog.info("polling resumed")
        for (index, runtime) in runtimes.enumerated() where !runtime.inFlight {
            runtime.nextDue = now.addingTimeInterval(Double(index) * settings.staggerSeconds)
        }
    }

    func tick(now: Date = Date()) {
        guard !isPaused else { return }
        for runtime in runtimes where !runtime.inFlight && runtime.nextDue <= now {
            start(runtime, now: now)
        }
    }

    private func signature(of vendor: VendorConfig) -> String {
        let headers = (vendor.headers ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\u{1F}")
        return [
            vendor.resolvedMethod,
            vendor.url,
            vendor.apiKey ?? "",
            headers,
            vendor.body ?? ""
        ].joined(separator: "\u{1E}")
    }

    private func start(_ runtime: VendorRuntime, now: Date) {
        runtime.lastAttempt = now
        runtime.error = nil

        let config = runtime.config
        let apiKey = config.apiKey ?? ""

        guard !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            runtime.error = "未填写 URL"
            scheduleFailure(runtime, now: now, retryAfter: nil)
            return
        }
        if Placeholders.requiresAPIKey(config), apiKey.isEmpty {
            runtime.error = "未填写 API Key"
            runtime.nextDue = now.addingTimeInterval(max(runtime.interval, 30))
            return
        }

        let expandedURL = Placeholders.expand(config.url, apiKey: apiKey)
        guard let url = URL(string: expandedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            runtime.error = "URL 无效（需 http/https）"
            scheduleFailure(runtime, now: now, retryAfter: nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.resolvedMethod
        request.timeoutInterval = runtime.settings.requestTimeout

        var headers: [String: String] = [:]
        for (key, value) in config.headers ?? [:] {
            headers[key] = Placeholders.expand(value, apiKey: apiKey)
        }
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) {
            headers["Accept"] = "application/json"
        }
        if config.resolvedMethod != "GET",
           !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers["Content-Type"] = "application/json"
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if config.resolvedMethod != "GET", let body = config.body {
            request.httpBody = Placeholders.expand(body, apiKey: apiKey).data(using: .utf8)
        }

        runtime.inFlight = true
        runtime.token += 1
        let token = runtime.token

        let task = session.dataTask(with: request) { [weak self, weak runtime] data, response, error in
            DispatchQueue.main.async {
                guard let self,
                      let runtime,
                      let current = self.runtimes.first(where: { $0 === runtime }),
                      current.token == token else { return }
                current.inFlight = false
                current.task = nil
                self.handle(data: data, response: response, error: error, runtime: current, now: Date())
            }
        }
        runtime.task = task
        task.resume()
    }

    private func handle(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        runtime: VendorRuntime,
        now: Date
    ) {
        if let error {
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorCancelled {
                return
            }
            runtime.error = describe(error)
            scheduleFailure(runtime, now: now, retryAfter: nil)
            OverlayLog.info("\(runtime.id): network error, attempt \(runtime.failureCount)")
            return
        }

        guard let http = response as? HTTPURLResponse else {
            runtime.error = "无 HTTP 响应"
            scheduleFailure(runtime, now: now, retryAfter: nil)
            return
        }

        runtime.httpStatus = http.statusCode
        let retryAfter = Self.retryAfter(from: http)

        guard (200...299).contains(http.statusCode) else {
            let snippet = Self.bodySnippet(data)
            runtime.error = snippet.isEmpty
                ? "HTTP \(http.statusCode)"
                : "HTTP \(http.statusCode)：\(snippet)"
            scheduleFailure(runtime, now: now, retryAfter: retryAfter)
            OverlayLog.info("\(runtime.id): HTTP \(http.statusCode), attempt \(runtime.failureCount)")
            return
        }

        guard let data, !data.isEmpty else {
            runtime.error = "空响应"
            scheduleFailure(runtime, now: now, retryAfter: retryAfter)
            OverlayLog.info("\(runtime.id): empty response")
            return
        }

        do {
            let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            runtime.lastResponse = root
            runtime.refreshFields()
            runtime.lastSuccess = now
            runtime.error = nil
            runtime.failureCount = 0
            runtime.nextDue = now.addingTimeInterval(runtime.interval)
            OverlayLog.info("\(runtime.id): HTTP \(http.statusCode) ok")
        } catch {
            runtime.error = "响应不是合法 JSON（HTTP \(http.statusCode)）"
            scheduleFailure(runtime, now: now, retryAfter: retryAfter)
            OverlayLog.info("\(runtime.id): invalid JSON, attempt \(runtime.failureCount)")
        }
    }

    private func scheduleFailure(
        _ runtime: VendorRuntime,
        now: Date,
        retryAfter: TimeInterval?
    ) {
        runtime.failureCount += 1
        let delay: TimeInterval
        if let retryAfter {
            delay = max(retryAfter, 1)
        } else {
            let exponent = min(Double(runtime.failureCount - 1), 20)
            let capped = min(
                runtime.settings.backoffBase * pow(2, exponent),
                runtime.settings.backoffMax
            )
            delay = max(capped * Double.random(in: 1.0...1.1), 1)
        }
        runtime.nextDue = now.addingTimeInterval(delay)
    }

    private func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .cannotFindHost: return "域名解析失败"
            case .cannotConnectToHost: return "无法连接服务器"
            case .notConnectedToInternet: return "无网络连接"
            case .networkConnectionLost: return "连接中断"
            case .cancelled: return "已取消"
            default: return "网络错误（\(urlError.code.rawValue)）"
            }
        }
        return "请求失败（\((error as NSError).code)）"
    }

    private static func bodySnippet(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        let text = String(data: data.prefix(200), encoding: .utf8) ?? ""
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return seconds
        }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return max(0, date.timeIntervalSinceNow)
            }
        }
        return nil
    }
}
