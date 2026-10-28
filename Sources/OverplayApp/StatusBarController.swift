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

    func openMenuPanel() {
        guard !popover.isShown else { return }
        togglePopover()
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
        button.setAccessibilityLabel("Overplay 菜单栏图标")
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
        let unacknowledged = model.unacknowledgedAlerts
        let failure = unacknowledged.contains {
            $0.kind == .credentialInvalid || $0.kind == .syncFailed
        }
        let critical = unacknowledged.contains {
            $0.kind == .budgetExceeded || $0.kind == .balanceLow
        }
        let warning = unacknowledged.contains {
            $0.kind == .budgetWarning || $0.kind == .dataStale
        }

        let symbol: String
        if failure {
            symbol = "xmark.octagon.fill"
            button.contentTintColor = .systemRed
        } else if critical {
            symbol = "exclamationmark.triangle.fill"
            button.contentTintColor = .systemRed
        } else if warning {
            symbol = "exclamationmark.circle.fill"
            button.contentTintColor = .systemOrange
        } else if model.isDemo {
            symbol = "flask.fill"
            button.contentTintColor = .systemOrange
        } else {
            symbol = "chart.bar.xaxis"
            button.contentTintColor = nil
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Overplay")
        image?.isTemplate = true
        button.image = image
        button.title = image == nil ? "OV" : ""
        button.toolTip = model.statusBarTooltip
        button.setAccessibilityLabel("Overplay 菜单栏图标")
        button.setAccessibilityHelp(model.statusBarTooltip)
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
        menu.addItem(withTitle: "打开悬浮窗", action: #selector(openFloatingWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "打开主窗口", action: #selector(openDashboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "打开快捷面板", action: #selector(openQuickPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let refreshItem = menu.addItem(withTitle: "刷新全部", action: #selector(refreshAll), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = !model.isDemo && !model.accounts.isEmpty
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Overplay", action: #selector(quitApp), keyEquivalent: "q").target = self
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
