import Foundation

public struct HTTPRequest {
    public var url: URL
    public var headers: [String: String]
    public var timeout: TimeInterval

    public init(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
    }
}

public struct HTTPResponse {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public var finalURL: URL

    public init(status: Int, headers: [String: String], body: Data, finalURL: URL) {
        self.status = status
        self.headers = headers
        self.body = body
        self.finalURL = finalURL
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var retryAfter: TimeInterval? {
        HTTPRetryAfter.parse(header("Retry-After"))
    }
}

public enum HTTPTransportError: Error, Equatable, CustomStringConvertible {
    case timedOut
    case offline
    case cannotConnect
    case cancelled
    case redirectRejected
    case other(String)

    public var description: String {
        switch self {
        case .timedOut: return "请求超时"
        case .offline: return "无网络连接"
        case .cannotConnect: return "无法连接服务器"
        case .cancelled: return "已取消"
        case .redirectRejected: return "请求被重定向到非官方地址，已拒绝"
        case .other(let detail): return "网络错误：\(detail)"
        }
    }

    public var isTimeout: Bool {
        if case .timedOut = self { return true }
        return false
    }

    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

public protocol HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func shutdown()
}

public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let redirectGuard: RedirectGuard

    public init(configuration: URLSessionConfiguration? = nil) {
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        let guardObject = RedirectGuard()
        self.redirectGuard = guardObject
        self.session = URLSession(configuration: config, delegate: guardObject, delegateQueue: nil)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await session.data(for: urlRequest, delegate: redirectGuard)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPTransportError.other("无有效 HTTP 响应")
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            return HTTPResponse(
                status: http.statusCode,
                headers: headers,
                body: data,
                finalURL: http.url ?? request.url
            )
        } catch let error as HTTPTransportError {
            throw error
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorCancelled {
                throw HTTPTransportError.cancelled
            }
            throw HTTPTransportError.other((error as NSError).localizedDescription)
        }
    }

    public func shutdown() {
        session.invalidateAndCancel()
    }

    private static func map(_ error: URLError) -> HTTPTransportError {
        switch error.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet: return .offline
        case .networkConnectionLost: return .offline
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: return .cannotConnect
        case .cancelled: return .cancelled
        default: return .other(error.localizedDescription)
        }
    }
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum HTTPRetryAfter {
    public static func parse(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
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

public enum Sanitizer {
    public static func sanitize(_ text: String, credential: String) -> String {
        guard !credential.isEmpty else { return text }
        var result = text.replacingOccurrences(of: credential, with: "•••")
        let bearer = "Bearer \(credential)"
        result = result.replacingOccurrences(of: bearer, with: "Bearer •••")
        return result
    }

    public static func errorMessage(from data: Data, credential: String) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Detail: Decodable {
                let message: String?
                let code: String?
            }
            let error: Detail?
            let message: String?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }
        let text = envelope.error?.message ?? envelope.message
        guard let text, !text.isEmpty else { return nil }
        return String(sanitize(text, credential: credential).prefix(240))
    }
}
