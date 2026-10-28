import AppKit
import SwiftUI
import OverplayCore

@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: FloatingPanel
    private var hosting: NSHostingView<FloatingPanelView>!
    private let store: FloatingWindowStateStore
    private var state: FloatingWindowState
    private var isAdjustingFrame = false
    private let onClose: () -> Void
    private let onOpenMain: () -> Void
    private let onOpenMessages: () -> Void

    init(
        model: AppModel,
        onClose: @escaping () -> Void,
        onOpenMain: @escaping () -> Void,
        onOpenMessages: @escaping () -> Void
    ) {
        self.model = model
        self.onClose = onClose
        self.onOpenMain = onOpenMain
        self.onOpenMessages = onOpenMessages
        self.store = FloatingWindowStateStore()
        let stored = store.load()
        let screen = stored.flatMap { Self.bestScreen(for: $0.frame()) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let loaded = stored ?? FloatingWindowState.initial(visibleFrame: visibleFrame)
        self.state = loaded.clamped(to: visibleFrame)
        self.panel = FloatingPanel(
            contentRect: state.frame(),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var density: FloatingDensity {
        state.density
    }

    func showIfNotCollapsed() {
        guard !state.collapsed else { return }
        show()
    }

    /// Tray click, or the explicit brief-view switch. This also clears the
    /// collapsed state so a hidden panel is restored.
    func show() {
        state.collapsed = false
        restoreToVisibleFrame()
        panel.orderFrontRegardless()
        persist()
    }

    func hideForMain() {
        panel.orderOut(nil)
    }

    func persistCurrentState() {
        persist()
    }

    func collapse() {
        state.collapsed = true
        panel.orderOut(nil)
        persist()
    }

    func toggleDensity() {
        let next: FloatingDensity = state.density == .expanded ? .compact : .expanded
        let oldFrame = panel.frame
        let visible = targetScreen.visibleFrame
        let preferredHeight = next == .expanded
            ? FloatingWindowState.heights.expanded
            : FloatingWindowState.heights.compact
        let height = min(preferredHeight, visible.height)
        var frame = CGRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - height,
            width: min(max(oldFrame.width, FloatingWindowState.widthRange.lowerBound), FloatingWindowState.widthRange.upperBound),
            height: height
        )
        state.density = next
        state.x = frame.minX
        state.y = frame.minY
        state.width = frame.width
        state = state.clamped(to: visible)
        frame = state.frame()
        frame.size.height = state.effectiveHeight(in: visible)
        isAdjustingFrame = true
        panel.setFrame(frame, display: true, animate: false)
        isAdjustingFrame = false
        hosting.rootView = makeRootView()
        persist()
        if !state.collapsed {
            panel.orderFrontRegardless()
        }
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: FloatingWindowState.widthRange.lowerBound, height: 200)
        panel.maxSize = NSSize(width: FloatingWindowState.widthRange.upperBound, height: FloatingWindowState.heights.expanded)
        panel.delegate = self
        hosting = NSHostingView(rootView: makeRootView())
        panel.contentView = hosting
        panel.setContentSize(NSSize(
            width: state.width,
            height: state.effectiveHeight(in: targetScreen.visibleFrame)
        ))
        restoreToVisibleFrame()
    }

    private func makeRootView() -> FloatingPanelView {
        FloatingPanelView(
            model: model,
            density: state.density,
            onClose: onClose,
            onToggleDensity: { [weak self] in self?.toggleDensity() },
            onCollapse: { [weak self] in self?.collapse() },
            onOpenMain: { [weak self] in
                guard let self else { return }
                self.hideForMain()
                self.onOpenMain()
            },
            onOpenMessages: { [weak self] in
                guard let self else { return }
                self.hideForMain()
                self.onOpenMessages()
            }
        )
    }

    private var targetScreen: NSScreen {
        if let screen = Self.bestScreen(for: panel.frame) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
    }

    private static func bestScreen(for frame: CGRect) -> NSScreen? {
        func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
            let intersection = lhs.intersection(rhs)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        guard let best = NSScreen.screens.max(by: {
            overlap($0.frame, frame) < overlap($1.frame, frame)
        }), overlap(best.frame, frame) > 0 else {
            return NSScreen.main
        }
        return best
    }

    private func restoreToVisibleFrame() {
        let visible = targetScreen.visibleFrame
        state = state.clamped(to: visible)
        var frame = state.frame()
        frame.size.height = state.effectiveHeight(in: visible)
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }

    private func persist() {
        store.save(state)
    }

    @objc private func screenParametersChanged() {
        let visible = targetScreen.visibleFrame
        state = state.clamped(to: visible)
        if panel.isVisible {
            restoreToVisibleFrame()
        }
        persist()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        state.x = panel.frame.minX
        state.y = panel.frame.minY
        persist()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        state.width = panel.frame.width
        state.x = panel.frame.minX
        state.y = panel.frame.minY
        persist()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let visible = targetScreen.visibleFrame
        let width = min(
            max(frameSize.width, FloatingWindowState.widthRange.lowerBound),
            min(FloatingWindowState.widthRange.upperBound, visible.width)
        )
        return NSSize(width: width, height: state.effectiveHeight(in: visible))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        collapse()
        return false
    }
}
