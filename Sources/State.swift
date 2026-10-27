import Foundation

struct WindowState: Codable {
    var x: Double?
    var topY: Double?
    var width: Double?
    var opacity: Double?
}

final class StateStore {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() -> WindowState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else {
            return WindowState()
        }
        return state
    }

    func save(_ state: WindowState) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
