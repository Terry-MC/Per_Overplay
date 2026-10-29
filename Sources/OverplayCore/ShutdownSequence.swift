import Foundation

/// Runs application cleanup actions once, in a deterministic order.
public struct ShutdownSequence {
    private let actions: [(name: String, run: () -> Void)]
    private var hasRun = false
    public private(set) var executedNames: [String] = []

    public init(actions: [(name: String, run: () -> Void)]) {
        self.actions = actions
    }

    public mutating func runIfNeeded() {
        guard !hasRun else { return }
        hasRun = true
        for action in actions {
            executedNames.append(action.name)
            action.run()
        }
    }

    public var didRun: Bool { hasRun }
}
