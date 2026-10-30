import AppKit
import SwiftUI
import OverplayCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private let openFloating: () -> Void
    private let openMain: (DashboardTab) -> Void
    private let onQuit: () -> Void
    private var lastPresentation: StatusItemPresentation?
    private var lastTooltip: String?

    init(
        model: AppModel,
        openFloating: @escaping () -> Void,
        openMain: @escaping (DashboardTab) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.openFloating = openFloating
        self.openMain = openMain
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        model.onStatusChanged = { [weak self] in
            self?.updateStatusItem()
        }
        updateStatusItem()
    }

    var isStatusItemVisible: Bool {
        statusItem.isVisible
    }

    var statusItemScreenFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var isMenuPanelShown: Bool {
        popover.isShown
    }

    func openMenuPanel() {
        guard !popover.isShown else { return }
        togglePopover()
    }

    func closeMenuPanel() {
        popover.performClose(nil)
    }

    func removeStatusItem() {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(L10n.t("statusBar.44fd17022a"))
    }

    private func configurePopover() {
        let root = MenuBarPanelView(
            model: model,
            openMain: { [weak self] tab in
                self?.popover.performClose(nil)
                self?.openMain(tab)
            },
            quit: { [weak self] in
                guard let self else { return }
                self.popover.performClose(nil)
                self.onQuit()
            }
        )
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 366, height: 470)
        popover.behavior = .transient
        popover.animates = true
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let presentation = StatusItemPresentation.make(
            isDemo: model.isDemo,
            alerts: model.alerts
        )
        let tooltip = model.statusBarTooltip
        guard presentation != lastPresentation || tooltip != lastTooltip else { return }
        lastPresentation = presentation
        lastTooltip = tooltip
        switch presentation.severity {
        case .failure, .critical:
            button.contentTintColor = .systemRed
        case .warning:
            button.contentTintColor = .systemOrange
        case .normal:
            button.contentTintColor = presentation.showsDemoBadge ? .systemOrange : nil
        }
        let image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.accessibilityLabel
        )
        image?.isTemplate = true
        button.image = image
        if presentation.showsDemoBadge {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: image == nil ? L10n.t("statusBar.a2b46a35e0") : L10n.t("statusBar.b7518ad52f"),
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.menuBarFont(ofSize: 0)
                ]
            )
        } else {
            button.imagePosition = .imageOnly
            button.title = image == nil ? "OV" : ""
        }
        button.toolTip = tooltip
        button.setAccessibilityLabel(presentation.accessibilityLabel)
        button.setAccessibilityHelp(tooltip)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showContextMenu()
        } else {
            openFloating()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.reloadFromStore()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        if model.isDemo {
            let demoItem = menu.addItem(
                withTitle: L10n.t("statusBar.d0a25554b0"),
                action: nil,
                keyEquivalent: ""
            )
            demoItem.isEnabled = false
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: L10n.t("statusBar.7789c1cdfe"), action: #selector(openFloatingWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("statusBar.b833a6eabe"), action: #selector(openDashboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("statusBar.a0223d7e4f"), action: #selector(openQuickPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let refreshItem = menu.addItem(withTitle: L10n.t("common.refreshAll"), action: #selector(refreshAll), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = !model.isDemo && !model.accounts.isEmpty
        menu.addItem(withTitle: L10n.t("statusBar.ff9f5134df"), action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("statusBar.d94cefe4dc"), action: #selector(quitApp), keyEquivalent: "q").target = self
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func openFloatingWindow() {
        openFloating()
    }

    @objc private func openDashboard() {
        openMain(.overview)
    }

    @objc private func openQuickPanel() {
        togglePopover()
    }

    @objc private func openSettings() {
        openMain(.settings)
    }

    @objc private func refreshAll() {
        model.refreshAll()
    }

    @objc private func quitApp() {
        onQuit()
    }
}
