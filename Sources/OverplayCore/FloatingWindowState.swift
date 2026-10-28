import CoreGraphics
import Foundation

public enum FloatingDensity: String, Codable, Equatable, Sendable {
    case expanded
    case compact

    public var title: String {
        switch self {
        case .expanded: return "完整"
        case .compact: return "压缩"
        }
    }
}

public struct FloatingWindowState: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var density: FloatingDensity
    public var collapsed: Bool

    public init(
        x: Double,
        y: Double,
        width: Double = 420,
        density: FloatingDensity = .expanded,
        collapsed: Bool = false
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.density = density
        self.collapsed = collapsed
    }

    public static let heights: (expanded: Double, compact: Double) = (560, 320)
    public static let widthRange: ClosedRange<Double> = 340...560

    public static func initial(visibleFrame: CGRect) -> FloatingWindowState {
        let width = min(max(420, widthRange.lowerBound), min(widthRange.upperBound, visibleFrame.width))
        let height = min(heights.expanded, visibleFrame.height)
        return FloatingWindowState(
            x: visibleFrame.maxX - width - 20,
            y: visibleFrame.maxY - height - 20,
            width: width,
            density: .expanded,
            collapsed: false
        )
    }

    public func height(expanded: Double = heights.expanded, compact: Double = heights.compact) -> Double {
        density == .expanded ? expanded : compact
    }

    public func frame(
        expanded: Double = heights.expanded,
        compact: Double = heights.compact
    ) -> CGRect {
        let resolvedHeight = height(expanded: expanded, compact: compact)
        return CGRect(x: x, y: y, width: width, height: resolvedHeight)
    }

    public func effectiveHeight(
        in visibleFrame: CGRect,
        expanded: Double = heights.expanded,
        compact: Double = heights.compact
    ) -> Double {
        min(height(expanded: expanded, compact: compact), max(visibleFrame.height, 0))
    }

    /// Keep the complete window inside the visible frame. If a persisted frame
    /// was on a disconnected display, move it to the main screen's visible area.
    public func clamped(
        to visibleFrame: CGRect,
        expanded: Double = heights.expanded,
        compact: Double = heights.compact
    ) -> FloatingWindowState {
        var copy = self
        let maxWidth = min(Self.widthRange.upperBound, max(visibleFrame.width, Self.widthRange.lowerBound))
        copy.width = min(max(width.isFinite ? width : 420, Self.widthRange.lowerBound), maxWidth)
        let targetHeight = min(height(expanded: expanded, compact: compact), visibleFrame.height)
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - copy.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - targetHeight)
        copy.x = min(max(x.isFinite ? x : visibleFrame.minX, visibleFrame.minX), maxX)
        copy.y = min(max(y.isFinite ? y : visibleFrame.minY, visibleFrame.minY), maxY)
        return copy
    }
}

public struct FloatingWindowStateStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "overplay.floatingWindow.state.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> FloatingWindowState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FloatingWindowState.self, from: data)
    }

    public func save(_ state: FloatingWindowState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
