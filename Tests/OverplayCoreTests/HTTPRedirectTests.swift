import XCTest
@testable import OverplayCore

final class HTTPRedirectTests: XCTestCase {
    func testURLSessionTransportDoesNotFollowRedirects() async throws {
        let redirectResponse = "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/should-not-be-requested\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = try LocalHTTPServer(response: redirectResponse)
        server.start()

        let transport = URLSessionTransport()
        defer { transport.shutdown() }
        let url = URL(string: "http://127.0.0.1:\(server.port)/redirect")!
        let response = try await transport.send(HTTPRequest(url: url))

        XCTAssertEqual(response.status, 302)
        XCTAssertEqual(response.finalURL.host, "127.0.0.1")
        XCTAssertEqual(response.finalURL.port, Int(server.port))
        XCTAssertFalse(response.finalURL.path.contains("should-not-be-requested"))
    }

    func testRetryAfterParser() {
        XCTAssertEqual(HTTPRetryAfter.parse("120"), 120)
        XCTAssertNil(HTTPRetryAfter.parse("not-a-number"))
        XCTAssertNil(HTTPRetryAfter.parse(nil))
    }
}
