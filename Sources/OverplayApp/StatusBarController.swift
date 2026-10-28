import AppKit
import SwiftUI
import OverplayCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private let openMain: (DashboardTab) -> Void

    init(model: AppModel, openMain: @escaping (DashboardTab) -> Void) {
        self.model = model
        self.openMain = openMain
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

    func openMenuPanel() {
        guard !popover.isShown else { return }
        togglePopover()
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
                AppPanels.confirmQuit(model: self.model)
            }
        )
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 366, height: 470)
        popover.behavior = .transient
        popover.animates = true
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if model.isDemo {
            symbol = "flask.fill"
            button.contentTintColor = .systemOrange
        } else if model.hasCriticalAlert {
            symbol = "exclamationmark.triangle.fill"
            button.contentTintColor = .systemRed
        } else {
            symbol = "chart.bar.xaxis"
            button.contentTintColor = nil
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Overplay")
        image?.isTemplate = true
        button.image = image
        button.title = image == nil ? "OV" : ""
        button.toolTip = model.statusBarTooltip
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
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
        menu.addItem(withTitle: "打开主界面", action: #selector(openDashboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "打开设置", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "刷新全部", action: #selector(refreshAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Overplay", action: #selector(quitApp), keyEquivalent: "q").target = self
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func openDashboard() {
        openMain(.overview)
    }

    @objc private func openSettings() {
        openMain(.settings)
    }

    @objc private func refreshAll() {
        model.refreshAll()
    }

    @objc private func quitApp() {
        AppPanels.confirmQuit(model: model)
    }
}
