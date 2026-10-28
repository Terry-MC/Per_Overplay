import AppKit
import Darwin
import SwiftUI
import OverplayCore

struct LaunchOptions {
    var demo = false
    var showWindow = false
    var tab: DashboardTab = .overview
    var snapshotPath: String?
    var snapshotDirectory: String?
    var dataDirectory: URL?
    var windowHeight: CGFloat?
    var darkAppearance = false
    var uiSmoke = false
    var showMenuPanel = false
    var benchmark = false
    var scrollBottom = false
    var suppressToasts = false

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--demo":
                options.demo = true
            case "--show":
                options.showWindow = true
            case "--tab" where index + 1 < arguments.count:
                index += 1
                options.tab = DashboardTab(rawValue: arguments[index]) ?? .overview
            case "--snapshot" where index + 1 < arguments.count:
                index += 1
                options.snapshotPath = arguments[index]
            case "--snapshot-dir" where index + 1 < arguments.count:
                index += 1
                options.snapshotDirectory = arguments[index]
            case "--data-dir" where index + 1 < arguments.count:
                index += 1
                options.dataDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--window-height" where index + 1 < arguments.count:
                index += 1
                if let height = Double(arguments[index]) {
                    options.windowHeight = CGFloat(height)
                }
            case "--dark":
                options.darkAppearance = true
            case "--ui-smoke":
                options.uiSmoke = true
            case "--show-menu":
                options.showMenuPanel = true
            case "--benchmark":
                options.benchmark = true
            case "--scroll-bottom":
                options.scrollBottom = true
            case "--no-toasts":
                options.suppressToasts = true
            default:
                break
            }
            index += 1
        }
        return options
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var launchTimestamp = Date()

    private var model: AppModel!
    private var statusBarController: StatusBarController!
    private var windowController: DashboardWindowController!
    private var options = LaunchOptions()
    private var windowShownAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        options = LaunchOptions.parse(CommandLine.arguments)
        configureMainMenu()
        NSApp.setActivationPolicy(.accessory)
        if options.darkAppearance {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        model = AppModel(dataDirectory: options.dataDirectory, forceDemo: options.demo)
        if options.suppressToasts {
            model.dismissAllToasts()
        }
        model.selectedTab = options.tab
        windowController = DashboardWindowController(model: model)
        statusBarController = StatusBarController(model: model) { [weak self] tab in
            self?.showMainWindow(tab: tab)
        }
        model.start()

        let isSnapshotMode = options.snapshotPath != nil || options.snapshotDirectory != nil
        if options.showWindow || options.demo || isSnapshotMode || options.uiSmoke || options.benchmark || model.showOnboarding {
            showMainWindow(tab: options.tab)
        }
        if let height = options.windowHeight {
            windowController.setContentSize(width: 1280, height: height)
        } else if isSnapshotMode {
            windowController.setContentSize(width: 1280, height: 800)
        }

        if isSnapshotMode {
            Task { await runSnapshots() }
        }
        if options.uiSmoke {
            Task { await runUISmoke() }
        }
        if options.showMenuPanel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.statusBarController.openMenuPanel()
            }
        }
        if options.benchmark {
            Task { await runBenchmark() }
        }
    }

    private func runBenchmark() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        let readyMs = (windowShownAt ?? Date()).timeIntervalSince(Self.launchTimestamp) * 1000
        print(String(
            format: "BENCHMARK startupReadyMs=%.1f physFootprintMB=%.1f",
            readyMs,
            physicalFootprintMB()
        ))
        NSApp.terminate(nil)
    }

    private func physicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
    }

    private func showMainWindow(tab: DashboardTab) {
        model.selectedTab = tab
        windowController.show()
        if windowShownAt == nil { windowShownAt = Date() }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于 Overplay",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(
            title: "隐藏 Overplay",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 Overplay",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func quitFromMenu() {
        AppPanels.confirmQuit(model: model)
    }

    private func runUISmoke() async {
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard let window = windowController.window else {
            print("UI_SMOKE FAILED no-window")
            NSApp.terminate(nil)
            return
        }
        let initiallyVisible = window.isVisible
        window.performClose(nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let hiddenAfterClose = !window.isVisible
        showMainWindow(tab: .overview)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let reopened = window.isVisible
        let statusVisible = statusBarController.isStatusItemVisible
        print("UI_SMOKE initiallyVisible=\(initiallyVisible) hiddenAfterClose=\(hiddenAfterClose) reopened=\(reopened) statusItemVisible=\(statusVisible)")
        NSApp.terminate(nil)
    }

    private func runSnapshots() async {
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        if let directory = options.snapshotDirectory {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for tab in DashboardTab.allCases {
                model.selectedTab = tab
                try? await Task.sleep(nanoseconds: 800_000_000)
                if options.scrollBottom {
                    scrollMainScrollViewToBottom()
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                capture(to: url.appendingPathComponent("\(tab.rawValue).png"))
            }
        } else if let path = options.snapshotPath {
            if options.scrollBottom {
                scrollMainScrollViewToBottom()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            capture(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }

    private func scrollMainScrollViewToBottom() {
        guard let contentView = windowController.window?.contentView else { return }
        var candidates: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scrollView = view as? NSScrollView {
                candidates.append(scrollView)
            }
            for subview in view.subviews { walk(subview) }
        }
        walk(contentView)
        guard let scrollView = candidates.max(by: { verticalOverflow($0) < verticalOverflow($1) }),
              let documentView = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let horizontalTable = candidates
            .filter { $0 !== scrollView }
            .max { horizontalOverflow($0) < horizontalOverflow($1) }
        var targetY = max(0, documentView.bounds.height - clip.bounds.height)
        if let horizontalTable, horizontalOverflow(horizontalTable) > 0 {
            let tableRect = horizontalTable.convert(horizontalTable.bounds, to: documentView)
            targetY = max(0, tableRect.minY - 8)
        }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clip)
    }

    private func verticalOverflow(_ scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView else { return 0 }
        return max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
    }

    private func horizontalOverflow(_ scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView else { return 0 }
        return max(0, documentView.bounds.width - scrollView.contentView.bounds.width)
    }

    private func capture(to url: URL) {
        guard let window = windowController.window,
              let view = window.contentView else { return }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }
}

@MainActor
final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let hosting = NSHostingController(rootView: DashboardView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Overplay"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.minSize = NSSize(width: 1080, height: 700)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("OverplayMainWindow")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func setContentSize(width: CGFloat, height: CGFloat) {
        window?.setContentSize(NSSize(width: width, height: height))
        window?.center()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
