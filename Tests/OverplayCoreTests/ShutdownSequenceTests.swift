import XCTest
@testable import OverplayCore

final class ShutdownSequenceTests: XCTestCase {
    func testActionsRunOnceInOrder() {
        var order: [String] = []
        var sequence = ShutdownSequence(actions: [
            ("stop", { order.append("stop") }),
            ("save", { order.append("save") }),
            ("close", { order.append("close") }),
            ("remove", { order.append("remove") })
        ])
        XCTAssertFalse(sequence.didRun)
        sequence.runIfNeeded()
        sequence.runIfNeeded()
        XCTAssertTrue(sequence.didRun)
        XCTAssertEqual(order, ["stop", "save", "close", "remove"])
        XCTAssertEqual(sequence.executedNames, ["stop", "save", "close", "remove"])
    }

    func testEmptySequenceIsSafe() {
        var sequence = ShutdownSequence(actions: [])
        sequence.runIfNeeded()
        XCTAssertTrue(sequence.didRun)
        XCTAssertTrue(sequence.executedNames.isEmpty)
    }
}
