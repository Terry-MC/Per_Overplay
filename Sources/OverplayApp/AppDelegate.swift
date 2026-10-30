import AppKit
import Combine
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
    var overviewPlatform: ProviderKind?
    var overviewAccount: String?
    var windowWidth: CGFloat?
    var windowHeight: CGFloat?
    var darkAppearance = false
    var uiSmoke = false
    var showMenuPanel = false
    var benchmark = false
    var scrollBottom = false
    var showMessages = false
    var printStatusFrame = false
    var suppressToasts = false
    var switchSmoke = false
    var collapseFloating = false
    var detailAccountId: String?
    var deleteSheetAccountId: String?
    var demoErrorAccountId: String?
    var alertLineAccountId: String?
    var autoQuitAfter: Double?

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
            case "--overview-platform" where index + 1 < arguments.count:
                index += 1
                options.overviewPlatform = ProviderKind(rawValue: arguments[index])
            case "--overview-account" where index + 1 < arguments.count:
                index += 1
                options.overviewAccount = arguments[index]
            case "--window-width" where index + 1 < arguments.count:
                index += 1
                if let width = Double(arguments[index]) {
                    options.windowWidth = CGFloat(width)
                }
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
            case "--show-messages":
                options.showMessages = true
            case "--print-status-frame":
                options.printStatusFrame = true
            case "--no-toasts":
                options.suppressToasts = true
            case "--switch-smoke":
                options.switchSmoke = true
            case "--collapse-floating":
                options.collapseFloating = true
            case "--detail-account" where index + 1 < arguments.count:
                index += 1
                options.detailAccountId = arguments[index]
            case "--delete-sheet" where index + 1 < arguments.count:
                index += 1
                options.deleteSheetAccountId = arguments[index]
            case "--demo-error-account" where index + 1 < arguments.count:
                index += 1
                options.demoErrorAccountId = arguments[index]
            case "--alert-line-account" where index + 1 < arguments.count:
                index += 1
                options.alertLineAccountId = arguments[index]
            case "--auto-quit-after" where index + 1 < arguments.count:
                index += 1
                options.autoQuitAfter = Double(arguments[index])
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

    private enum ViewMode {
        case floating
        case main
    }

    private var model: AppModel!
    private var cancellables = Set<AnyCancellable>()
    private var statusBarController: StatusBarController!
    private var windowController: DashboardWindowController!
    private var floatingController: FloatingWindowController!
    private var options = LaunchOptions()
    private var windowShownAt: Date?
    private var viewMode: ViewMode = .floating
    private var shutdownSequence: ShutdownSequence?

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
        if let platform = options.overviewPlatform {
            model.overviewPlatformFilter = platform
            if let account = options.overviewAccount {
                model.overviewAccountFilter = account
            }
        }
        windowController = DashboardWindowController(
            model: model,
            onSwitchToFloating: { [weak self] in
                self?.showFloatingWindow()
            },
            onHide: { [weak self] in
                self?.mainWindowDidHide()
            }
        )
        floatingController = FloatingWindowController(
            model: model,
            onClose: { [weak self] in
                self?.requestTermination()
            },
            onOpenMain: { [weak self] in
                self?.showMainWindow(tab: .overview)
            },
            onOpenMessages: { [weak self] in
                self?.showMainWindow(tab: .overview)
                self?.model.showMessageCenter = true
            }
        )
        statusBarController = StatusBarController(
            model: model,
            openFloating: { [weak self] in
                self?.showFloatingWindow()
            },
            openMain: { [weak self] tab in
                self?.showMainWindow(tab: tab)
            },
            onQuit: { [weak self] in
                self?.requestTermination()
            }
        )
        shutdownSequence = ShutdownSequence(actions: [
            ("stop-timers-and-requests", { [weak self] in self?.model.prepareForTermination() }),
            ("save-window-state", { [weak self] in self?.floatingController.persistCurrentState() }),
            ("close-windows", { [weak self] in
                self?.windowController.window?.orderOut(nil)
                self?.floatingController.hideForMain()
            }),
            ("remove-status-item", { [weak self] in self?.statusBarController.removeStatusItem() })
        ])
        model.start()
        model.$localizationRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.configureMainMenu() }
            .store(in: &cancellables)

        let isSnapshotMode = options.snapshotPath != nil || options.snapshotDirectory != nil
        let showMainAtLaunch = options.showWindow || isSnapshotMode || options.uiSmoke
            || options.switchSmoke || options.benchmark || model.showOnboarding
        if options.collapseFloating {
            viewMode = .floating
            floatingController.collapse()
        } else if showMainAtLaunch {
            showMainWindow(tab: options.tab)
        } else {
            viewMode = .floating
            floatingController.showIfNotCollapsed()
        }
        if options.windowWidth != nil || options.windowHeight != nil || isSnapshotMode {
            windowController.setContentSize(
                width: options.windowWidth ?? 1280,
                height: options.windowHeight ?? 800
            )
        }
        if let demoErrorAccountId = options.demoErrorAccountId {
            model.injectDemoRefreshFailure(accountId: demoErrorAccountId)
        }
        if let detailAccountId = options.detailAccountId {
            showMainWindow(tab: .overview)
            model.selectedProviderDetailAccountId = detailAccountId
        }
        if let deleteSheetAccountId = options.deleteSheetAccountId {
            showMainWindow(tab: .overview)
            model.debugDeleteAccountId = deleteSheetAccountId
        }
        if let alertLineAccountId = options.alertLineAccountId {
            showMainWindow(tab: .addProvider)
            model.debugAlertLineAccountId = alertLineAccountId
        }

        if options.showMessages {
            showMainWindow(tab: options.tab)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.model.showMessageCenter = true
            }
        }
        if options.printStatusFrame {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let frame = self?.statusBarController.statusItemScreenFrame else { return }
                print("STATUS_FRAME \(frame.origin.x) \(frame.origin.y) \(frame.width) \(frame.height)")
                fflush(stdout)
            }
        }
        if isSnapshotMode {
            Task { await runSnapshots() }
        }
        if options.uiSmoke {
            Task { await runUISmoke() }
        }
        if options.switchSmoke {
            Task { await runSwitchSmoke() }
        }
        if let seconds = options.autoQuitAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                NSApp.terminate(nil)
            }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !model.hasUnsavedChanges
            || AppPanels.confirmDiscardUnsaved(model: model, action: L10n.t("appDelegate.feecb1e6ad")) else {
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownSequence?.runIfNeeded()
    }

    private func showMainWindow(tab: DashboardTab) {
        floatingController?.hideForMain()
        viewMode = .main
        model.selectedTab = tab
        windowController.show()
        if windowShownAt == nil { windowShownAt = Date() }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showFloatingWindow() {
        guard !model.hasUnsavedChanges
            || AppPanels.confirmDiscardUnsaved(model: model, action: L10n.t("appDelegate.f9f838cb05")) else {
            return
        }
        windowController?.window?.orderOut(nil)
        viewMode = .floating
        floatingController.show()
    }

    private func mainWindowDidHide() {
        guard viewMode == .main else { return }
        viewMode = .floating
        floatingController.showIfNotCollapsed()
    }

    private func requestTermination() {
        AppPanels.confirmQuit(model: model)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L10n.t("appDelegate.c1e00d3105"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(
            title: L10n.t("appDelegate.36bc63fe16"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: L10n.t("statusBar.d94cefe4dc"),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L10n.t("common.edit"))
        editMenu.addItem(withTitle: L10n.t("appDelegate.9fcefd8dc8"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.t("appDelegate.1238f0d363"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("appDelegate.29b653b40e"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("appDelegate.bc6d0279b6"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("appDelegate.de7fb7d3cf"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("appDelegate.3e44b2a933"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func quitFromMenu() {
        requestTermination()
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

    /// Exercises the real window-switching entry points and fails if any of
    /// them invokes a manual refresh or opens a network request.
    private func runSwitchSmoke() async {
        try? await Task.sleep(nanoseconds: 900_000_000)
        let refreshBaseline = model.refreshInvocationCount
        let networkBaseline = model.networkRequestCount
        var checks: [(String, Bool)] = []

        showMainWindow(tab: .overview)
        checks.append(("mainVisible", windowController.window?.isVisible == true))
        checks.append(("floatingHiddenForMain", !floatingController.isVisible))

        model.showMessageCenter = true
        checks.append(("messageCenterOpen", model.showMessageCenter))
        model.showMessageCenter = false

        showFloatingWindow()
        checks.append(("floatingVisible", floatingController.isVisible))
        checks.append(("mainHidden", windowController.window?.isVisible == false))
        try? await Task.sleep(nanoseconds: 300_000_000)

        let scrollStart = floatingController.setScrollOffsetForSmoke(CGPoint(x: 0, y: 140))
        checks.append(("scrollPrepared", (scrollStart?.y ?? 0) > 0))
        let summaryBuildBaseline = floatingController.summaryBuildCountForSmoke

        showMainWindow(tab: .overview)
        try? await Task.sleep(nanoseconds: 3_200_000_000)
        let summaryBuildsWhileHidden = floatingController.summaryBuildCountForSmoke
        checks.append(("noSummaryRebuildWhileHidden", summaryBuildsWhileHidden == summaryBuildBaseline))

        showFloatingWindow()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let scrollAfterSwitch = floatingController.scrollOffsetForSmoke
        checks.append(("scrollPreservedAcrossSwitch", scrollOffsetsMatch(scrollStart, scrollAfterSwitch)))
        checks.append(("summaryRebuiltOnShow", floatingController.summaryBuildCountForSmoke > summaryBuildsWhileHidden))

        floatingController.collapse()
        checks.append(("collapsed", !floatingController.isVisible))
        try? await Task.sleep(nanoseconds: 300_000_000)
        showFloatingWindow()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let scrollAfterCollapse = floatingController.scrollOffsetForSmoke
        checks.append(("restoredFromCollapse", floatingController.isVisible))
        checks.append(("scrollPreservedAcrossCollapse", scrollOffsetsMatch(scrollStart, scrollAfterCollapse)))

        let initialDensity = floatingController.density
        floatingController.toggleDensity()
        checks.append(("densityChanged", floatingController.density != initialDensity))
        floatingController.toggleDensity()
        checks.append(("densityRestored", floatingController.density == initialDensity))

        showMainWindow(tab: .usage)
        checks.append(("tabUsageSelected", model.selectedTab == .usage))
        model.selectedTab = .quota
        checks.append(("tabQuotaSelected", model.selectedTab == .quota))
        model.selectedTab = .settings
        checks.append(("tabSettingsSelected", model.selectedTab == .settings))
        model.selectedTab = .addProvider
        checks.append(("tabAddProviderSelected", model.selectedTab == .addProvider))
        model.selectedTab = .overview
        checks.append(("tabBaseInfoSelected", model.selectedTab == .overview))
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let firstAccount = model.accounts.first {
            model.selectedProviderDetailAccountId = firstAccount.id
            for _ in 0..<20 {
                if model.providerDetailVisible { break }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            checks.append(("providerDetailOpened", model.providerDetailVisible))
            model.selectedProviderDetailAccountId = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        showFloatingWindow()

        statusBarController.openMenuPanel()
        try? await Task.sleep(nanoseconds: 400_000_000)
        checks.append(("menuPanelOpen", statusBarController.isMenuPanelShown))
        statusBarController.closeMenuPanel()

        let refreshDelta = model.refreshInvocationCount - refreshBaseline
        let networkDelta = model.networkRequestCount - networkBaseline
        checks.append(("noRefreshInvocations", refreshDelta == 0))
        checks.append(("noNetworkRequests", networkDelta == 0))

        let failed = checks.filter { !$0.1 }.map(\.0)
        let detail = checks.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        let scrollDetail = "scrollStart=\(pointDescription(scrollStart)) scrollAfterSwitch=\(pointDescription(scrollAfterSwitch)) scrollAfterCollapse=\(pointDescription(scrollAfterCollapse)) summaryBuilds=\(summaryBuildBaseline)/\(summaryBuildsWhileHidden)/\(floatingController.summaryBuildCountForSmoke)"
        print("SWITCH_SMOKE \(failed.isEmpty ? "PASS" : "FAIL") \(detail) \(scrollDetail) refreshInvocations=\(refreshDelta) networkRequests=\(networkDelta)")
        fflush(stdout)
        exit(failed.isEmpty ? 0 : 1)
    }

    private func scrollOffsetsMatch(_ lhs: CGPoint?, _ rhs: CGPoint?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.x - rhs.x) <= 1 && abs(lhs.y - rhs.y) <= 1
    }

    private func pointDescription(_ point: CGPoint?) -> String {
        guard let point else { return "nil" }
        return String(format: "%.1f,%.1f", point.x, point.y)
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
        exit(0)
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
        guard let window = windowController.window else { return }
        let targetWindow = window.attachedSheet ?? window
        guard let view = targetWindow.contentView else { return }
        targetWindow.displayIfNeeded()
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
    private let onHide: (() -> Void)?

    init(
        model: AppModel,
        onSwitchToFloating: @escaping () -> Void,
        onHide: (() -> Void)? = nil
    ) {
        self.model = model
        self.onHide = onHide
        let hosting = NSHostingController(
            rootView: DashboardView(model: model, onSwitchToFloating: onSwitchToFloating)
        )
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
        guard !model.hasUnsavedChanges
            || AppPanels.confirmDiscardUnsaved(model: model, action: L10n.t("appDelegate.c664d556f3")) else {
            return false
        }
        sender.orderOut(nil)
        onHide?()
        return false
    }
}
