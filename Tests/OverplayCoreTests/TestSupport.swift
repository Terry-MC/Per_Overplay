import Foundation
import XCTest
@testable import OverplayCore

enum TestClock {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    static func date(
        _ year: Int = 2026,
        _ month: Int = 10,
        _ day: Int = 28,
        _ hour: Int = 12,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }
}

final class FakeHTTPTransport: HTTPTransport {
    private var queue: [Result<HTTPResponse, HTTPTransportError>]
    private(set) var requests: [HTTPRequest] = []
    private let lock = NSLock()

    init(_ queue: [Result<HTTPResponse, HTTPTransportError>]) {
        self.queue = queue
    }

    convenience init(_ responses: [HTTPResponse]) {
        self.init(responses.map { .success($0) })
    }

    convenience init() {
        self.init([Result<HTTPResponse, HTTPTransportError>]())
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        requests.append(request)
        let next = queue.isEmpty ? nil : queue.removeFirst()
        lock.unlock()
        guard let next else {
            throw HTTPTransportError.other("测试响应已耗尽")
        }
        return try next.get()
    }

    func shutdown() {}
}

func response(
    _ status: Int,
    body: String = "",
    headers: [String: String] = [:]
) -> HTTPResponse {
    HTTPResponse(
        status: status,
        headers: headers,
        body: Data(body.utf8),
        finalURL: URL(string: "https://example.com")!
    )
}

func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("overplay-tests-\(UUID().uuidString).sqlite")
        .path
}

extension OverplayStore {
    func insertTestAccount(
        provider: ProviderKind = .openrouter,
        name: String = "Test",
        budget: Budget? = nil,
        threshold: BalanceThreshold? = nil
    ) throws -> Account {
        let newAccount = Account(
            provider: provider,
            name: name,
            budget: budget,
            balanceThreshold: threshold
        )
        try insertAccount(newAccount)
        return try account(id: newAccount.id)!
    }
}
