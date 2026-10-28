import CoreGraphics
import XCTest
@testable import OverplayCore

final class FloatingWindowStateTests: XCTestCase {
    func testInitialStateSitsInsideVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let state = FloatingWindowState.initial(visibleFrame: visible)
        XCTAssertEqual(state.width, 420)
        XCTAssertEqual(state.density, .expanded)
        XCTAssertFalse(state.collapsed)
        let frame = state.frame()
        XCTAssertEqual(frame.height, 560)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    func testClampMovesOffscreenStateIntoVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let state = FloatingWindowState(
            x: -900,
            y: 2000,
            width: 900,
            density: .compact,
            collapsed: true
        )
        let clamped = state.clamped(to: visible)
        XCTAssertEqual(clamped.width, FloatingWindowState.widthRange.upperBound)
        XCTAssertEqual(clamped.x, 0)
        XCTAssertEqual(clamped.y, visible.height - FloatingWindowState.heights.compact)
        XCTAssertTrue(clamped.collapsed)
        XCTAssertEqual(clamped.frame().height, FloatingWindowState.heights.compact)
        XCTAssertLessThanOrEqual(clamped.frame().maxX, visible.maxX)
        XCTAssertLessThanOrEqual(clamped.frame().maxY, visible.maxY)
    }

    func testClampHandlesNaNWithoutCrashing() {
        let visible = CGRect(x: 10, y: 20, width: 800, height: 600)
        let state = FloatingWindowState(
            x: .nan,
            y: .nan,
            width: .nan,
            density: .expanded,
            collapsed: false
        )
        let clamped = state.clamped(to: visible)
        XCTAssertEqual(clamped.x, 10)
        XCTAssertEqual(clamped.y, 20)
        XCTAssertEqual(clamped.width, 420)
    }

    func testEffectiveHeightNeverExceedsVisibleFrame() {
        let expanded = FloatingWindowState(x: 0, y: 0, density: .expanded)
        XCTAssertEqual(
            expanded.effectiveHeight(in: CGRect(x: 0, y: 0, width: 800, height: 400)),
            400
        )
        XCTAssertEqual(
            expanded.effectiveHeight(in: CGRect(x: 0, y: 0, width: 800, height: 700)),
            560
        )
        var compact = expanded
        compact.density = .compact
        XCTAssertEqual(
            compact.effectiveHeight(in: CGRect(x: 0, y: 0, width: 800, height: 200)),
            200
        )
    }

    func testClampKeepsStateOnSecondaryDisplay() {
        let secondary = CGRect(x: -1512, y: 458, width: 1512, height: 950)
        let state = FloatingWindowState(
            x: -1003,
            y: 843,
            width: 420,
            density: .compact,
            collapsed: false
        )
        let clamped = state.clamped(to: secondary)
        XCTAssertEqual(clamped.x, -1003)
        XCTAssertEqual(clamped.y, 843)
        XCTAssertTrue(secondary.contains(clamped.frame()))
    }

    func testStateStoreRoundTrip() {
        let suite = "overplay-floating-state-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FloatingWindowStateStore(defaults: defaults)
        XCTAssertNil(store.load())
        let state = FloatingWindowState(
            x: 111,
            y: 222,
            width: 480,
            density: .compact,
            collapsed: true
        )
        store.save(state)
        XCTAssertEqual(store.load(), state)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testDensityHeightsAndWidthRange() {
        let state = FloatingWindowState(x: 0, y: 0, width: 420, density: .expanded)
        XCTAssertEqual(state.height(), 560)
        var compact = state
        compact.density = .compact
        XCTAssertEqual(compact.height(), 320)
        XCTAssertEqual(FloatingWindowState.widthRange, 340...560)
    }
}
