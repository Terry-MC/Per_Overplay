import Foundation
import OverplayCore

final class NetworkRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class RequestCountingTransport: HTTPTransport {
    private let base: HTTPTransport
    private let counter: NetworkRequestCounter

    init(base: HTTPTransport, counter: NetworkRequestCounter) {
        self.base = base
        self.counter = counter
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        counter.increment()
        return try await base.send(request)
    }

    func shutdown() {
        base.shutdown()
    }
}
