import Darwin
import Foundation

/// Minimal one-shot local HTTP server for transport integration tests.
final class LocalHTTPServer {
    let port: UInt16
    private let listenFD: Int32
    private let responseData: Data
    private let lock = NSLock()
    private var closed = false

    init(response: String) throws {
        guard let data = response.data(using: .utf8) else {
            throw NSError(domain: "LocalHTTPServer", code: 1)
        }
        responseData = data
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "LocalHTTPServer", code: 2)
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw NSError(domain: "LocalHTTPServer", code: 3)
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(fd, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            close(fd)
            throw NSError(domain: "LocalHTTPServer", code: 4)
        }
        listenFD = fd
        port = UInt16(bigEndian: bound.sin_port)
    }

    func start() {
        let fd = listenFD
        let payload = responseData
        DispatchQueue.global(qos: .userInitiated).async {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = read(client, &buffer, buffer.count)
            payload.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var written = 0
                while written < payload.count {
                    let result = write(client, base.advanced(by: written), payload.count - written)
                    if result <= 0 { break }
                    written += result
                }
            }
            close(client)
        }
    }

    deinit {
        lock.lock()
        if !closed {
            closed = true
            close(listenFD)
        }
        lock.unlock()
    }
}
