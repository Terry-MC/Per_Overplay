import AppKit

final class AppController: NSObject, NSWindowDelegate, NSMenuDelegate {
    private let configURL: URL
    private let poller = Poller()
    private let stateStore: StateStore
    private let panel = OverlayPanel()
    private let overlayView = OverlayView()
    private let snapshotPath: String?
    private let snapshotDelay: TimeInterval

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lastConfigData: Data?
    private var configError: String?
    private var isProgrammaticFrame = false
    private var pendingStateSave: DispatchWorkItem?

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(configURL: URL, stateURL: URL, snapshotPath: String? = nil, snapshotDelay: TimeInterval = 3) {
        self.configURL = configURL
        self.snapshotPath = snapshotPath
        self.snapshotDelay = snapshotDelay
        stateStore = StateStore(url: stateURL)
        super.init()
        panel.delegate = self
        panel.contentView = overlayView
        setupStatusItem()
    }

    func start() {
        do {
            try ConfigStore.ensureConfigFile(at: configURL)
        } catch {
            configError = "无法创建配置模板：\(error.localizedDescription)"
        }
        reloadConfig(force: true)

        let saved = stateStore.load()
        let width = min(max(CGFloat(saved.width ?? 340), 240), 720)
        let opacity = min(max(CGFloat(saved.opacity ?? 0.9), 0.3), 1)
        overlayView.model = buildModel(now: Date())
        overlayView.frame = NSRect(x: 0, y: 0, width: width, height: 120)
        let height = overlayView.contentHeight(forWidth: width)
        let topLeft = initialTopLeft(state: saved, width: width, height: height)

        panel.alphaValue = opacity
        isProgrammaticFrame = true
        panel.setFrame(
            NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height),
            display: false
        )
        isProgrammaticFrame = false
        overlayView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.orderFrontRegardless()
        startTimer()
        refreshUI()
        updateStatusIcon()
        OverlayLog.info("started: \(poller.runtimes.count) vendor(s), config=\(configURL.path)")
        if panel.isVisible {
            OverlayLog.info(
                "panel frame=\(panel.frame) alpha=\(panel.alphaValue) screen=\(panel.screen?.visibleFrame ?? .zero)"
            )
        } else {
            OverlayLog.info("panel is not visible")
        }
        if snapshotPath != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
                self?.writeSnapshot()
            }
        }
    }

    private func writeSnapshot() {
        guard let snapshotPath else { return }
        refreshUI()
        guard let representation = overlayView.bitmapImageRepForCachingDisplay(in: overlayView.bounds) else {
            OverlayLog.info("snapshot failed: no bitmap")
            NSApp.terminate(nil)
            return
        }
        overlayView.cacheDisplay(in: overlayView.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            OverlayLog.info("snapshot failed: no png data")
            NSApp.terminate(nil)
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: snapshotPath))
            OverlayLog.info(
                "snapshot written: \(snapshotPath) \(Int(overlayView.bounds.width))x\(Int(overlayView.bounds.height))"
            )
        } catch {
            OverlayLog.info("snapshot write failed: \(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }

    func persistStateNow() {
        pendingStateSave?.cancel()
        pendingStateSave = nil
        saveState()
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        reloadConfig(force: false)
        let shouldPause = !panel.isVisible && poller.settings.pauseWhenHidden
        poller.setPaused(shouldPause)
        poller.tick()
        if panel.isVisible {
            refreshUI()
        }
    }

    private func reloadConfig(force: Bool) {
        let data = try? Data(contentsOf: configURL)
        if !force, let data, data == lastConfigData {
            return
        }
        lastConfigData = data
        guard let data else {
            configError = "无法读取 \(configURL.path)"
            return
        }
        do {
            let config = try JSONDecoder().decode(OverlayConfig.self, from: data)
            if let validation = ConfigValidation.validate(config) {
                configError = validation
                return
            }
            configError = nil
            poller.apply(config: config)
        } catch {
            configError = "JSON 解析失败：\(error.localizedDescription)"
        }
    }

    private func refreshUI() {
        let model = buildModel(now: Date())
        overlayView.model = model
        let width = panel.frame.width
        let height = overlayView.contentHeight(forWidth: width)
        if abs(panel.frame.height - height) > 0.5 {
            var frame = panel.frame
            let top = frame.maxY
            frame.size.height = height
            frame.origin.y = top - height
            isProgrammaticFrame = true
            panel.setFrame(frame, display: true)
            isProgrammaticFrame = false
            clampToScreen()
        }
        overlayView.frame = NSRect(x: 0, y: 0, width: width, height: panel.frame.height)
        overlayView.needsDisplay = true
    }

    private func buildModel(now: Date) -> OverlayModel {
        var notices: [String] = []
        if let configError {
            notices.append("配置：\(configError)")
        }
        if let warning = ConfigStore.permissionWarning(for: configURL) {
            notices.append(warning)
        }
        if poller.runtimes.isEmpty {
            notices.append("没有启用的厂商。编辑 \(configURL.path) 后约 1 秒自动生效。")
        }

        let cards = poller.runtimes.map { buildCard($0, now: now) }
        let subtitle: String
        if poller.isPaused {
            subtitle = "\(poller.runtimes.count) 个厂商 · 已暂停"
        } else {
            subtitle = "\(poller.runtimes.count) 个厂商 · \(timeFormatter.string(from: now))"
        }
        return OverlayModel(title: "API 额度", subtitle: subtitle, notices: notices, cards: cards)
    }

    private func buildCard(_ runtime: VendorRuntime, now: Date) -> VendorCardModel {
        var statusText = "待查询"
        var statusColor = NSColor.white.withAlphaComponent(0.5)

        if runtime.inFlight {
            statusText = "查询中…"
            statusColor = .systemYellow
        } else if runtime.error != nil {
            if runtime.failureCount > 0 {
                statusText = "重试 \(runtime.failureCount)"
                statusColor = .systemOrange
            } else {
                statusText = "待配置"
                statusColor = .systemOrange
            }
        } else if runtime.lastSuccess != nil {
            if let status = runtime.httpStatus {
                statusText = "HTTP \(status)"
            } else {
                statusText = "正常"
            }
            statusColor = .systemGreen
        }

        var health: String
        if let last = runtime.lastSuccess {
            health = "更新 " + timeFormatter.string(from: last)
        } else if let attempt = runtime.lastAttempt {
            health = "尝试 " + timeFormatter.string(from: attempt)
        } else {
            health = "尚未查询"
        }
        if poller.isPaused {
            health += " · 已暂停"
        } else if runtime.inFlight {
            health += " · 等待响应"
        } else {
            health += " · 下次 " + countdown(runtime.nextDue.timeIntervalSince(now))
        }

        let errorText: String?
        if let error = runtime.error {
            let flattened = error
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            errorText = String(flattened.prefix(160))
        } else {
            errorText = nil
        }

        return VendorCardModel(
            name: runtime.displayName,
            statusText: statusText,
            statusColor: statusColor,
            fields: runtime.fieldDisplays,
            healthText: health,
            errorText: errorText
        )
    }

    private func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3600 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func initialTopLeft(state: WindowState, width: CGFloat, height: CGFloat) -> NSPoint {
        let screens = NSScreen.screens
        let main = NSScreen.main ?? screens.first
        let mainFrame = main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = state.x.map { CGFloat($0) } ?? (mainFrame.maxX - width - 24)
        var topY = state.topY.map { CGFloat($0) } ?? (mainFrame.maxY - 24)

        let anchor = NSPoint(x: x, y: topY - 1)
        let screen = screens.first(where: { $0.visibleFrame.contains(anchor) }) ?? main
        let visible = screen?.visibleFrame ?? mainFrame
        if width <= visible.width {
            x = min(max(x, visible.minX), visible.maxX - width)
        } else {
            x = visible.minX
        }
        if height <= visible.height {
            topY = min(max(topY, visible.minY + height), visible.maxY)
        } else {
            topY = visible.maxY
        }
        return NSPoint(x: x, y: topY)
    }

    private func clampToScreen() {
        let frame = panel.frame
        let screen = NSScreen.screens.max { first, second in
            intersectionArea(first.visibleFrame, frame) < intersectionArea(second.visibleFrame, frame)
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var x = frame.minX
        var topY = frame.maxY
        if frame.width <= visible.width {
            x = min(max(x, visible.minX), visible.maxX - frame.width)
        } else {
            x = visible.minX
        }
        if frame.height <= visible.height {
            topY = min(max(topY, visible.minY + frame.height), visible.maxY)
        } else {
            topY = visible.maxY
        }
        let adjusted = NSRect(x: x, y: topY - frame.height, width: frame.width, height: frame.height)
        guard adjusted != panel.frame else { return }
        isProgrammaticFrame = true
        panel.setFrame(adjusted, display: true)
        isProgrammaticFrame = false
    }

    private func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let symbol = panel.ignoresMouseEvents ? "eye.slash" : "speedometer"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DSOverlay")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.title = image == nil ? "API" : ""
        statusItem?.button?.toolTip = panel.ignoresMouseEvents
            ? "DSOverlay（点击穿透已开启）"
            : "DSOverlay"
    }

    private func scheduleStateSave() {
        pendingStateSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveState()
        }
        pendingStateSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveState() {
        stateStore.save(WindowState(
            x: Double(panel.frame.minX),
            topY: Double(panel.frame.maxY),
            width: Double(panel.frame.width),
            opacity: Double(panel.alphaValue)
        ))
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrame else { return }
        scheduleStateSave()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(makeMenuItem(
            panel.isVisible ? "隐藏悬浮窗" : "显示悬浮窗",
            action: #selector(toggleVisibility(_:))
        ))
        menu.addItem(makeMenuItem(
            "点击穿透",
            action: #selector(toggleClickThrough(_:)),
            state: panel.ignoresMouseEvents ? .on : .off
        ))
        menu.addItem(.separator())

        let opacityParent = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for value in [50, 70, 85, 100] {
            let item = makeMenuItem("\(value)%", action: #selector(setOpacity(_:)), tag: value)
            if abs(panel.alphaValue * 100 - CGFloat(value)) < 1 {
                item.state = .on
            }
            opacityMenu.addItem(item)
        }
        opacityParent.submenu = opacityMenu
        menu.addItem(opacityParent)

        let widthParent = NSMenuItem(title: "宽度", action: nil, keyEquivalent: "")
        let widthMenu = NSMenu()
        for value in [280, 340, 420] {
            let item = makeMenuItem("\(value) px", action: #selector(setWidth(_:)), tag: value)
            if abs(panel.frame.width - CGFloat(value)) < 1 {
                item.state = .on
            }
            widthMenu.addItem(item)
        }
        widthParent.submenu = widthMenu
        menu.addItem(widthParent)
        menu.addItem(.separator())

        menu.addItem(makeMenuItem("重新加载配置", action: #selector(reloadConfigAction(_:))))
        menu.addItem(makeMenuItem("打开配置文件", action: #selector(openConfig(_:))))
        menu.addItem(makeMenuItem("打开配置目录", action: #selector(openConfigDirectory(_:))))
        menu.addItem(makeMenuItem("重置位置", action: #selector(resetPosition(_:))))
        menu.addItem(.separator())

        let status = NSMenuItem(
            title: configError == nil ? "配置加载正常" : "配置有错误",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem("退出 DSOverlay", action: #selector(quit(_:))))
    }

    private func makeMenuItem(
        _ title: String,
        action: Selector?,
        tag: Int = 0,
        state: NSControl.StateValue = .off
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = state
        return item
    }

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        if panel.isVisible {
            panel.orderOut(nil)
            poller.setPaused(poller.settings.pauseWhenHidden)
            OverlayLog.info("panel hidden")
        } else {
            refreshUI()
            panel.orderFrontRegardless()
            poller.setPaused(false)
            OverlayLog.info("panel shown")
        }
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        panel.ignoresMouseEvents.toggle()
        updateStatusIcon()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        panel.alphaValue = CGFloat(sender.tag) / 100
        scheduleStateSave()
    }

    @objc private func setWidth(_ sender: NSMenuItem) {
        let width = CGFloat(sender.tag)
        var frame = panel.frame
        let top = frame.maxY
        let height = overlayView.contentHeight(forWidth: width)
        frame.size = CGSize(width: width, height: height)
        frame.origin.y = top - height
        isProgrammaticFrame = true
        panel.setFrame(frame, display: true)
        isProgrammaticFrame = false
        overlayView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        clampToScreen()
        refreshUI()
        scheduleStateSave()
    }

    @objc private func reloadConfigAction(_ sender: NSMenuItem) {
        lastConfigData = nil
        reloadConfig(force: true)
        if panel.isVisible {
            refreshUI()
        }
    }

    @objc private func openConfig(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(configURL)
    }

    @objc private func openConfigDirectory(_ sender: NSMenuItem) {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    @objc private func resetPosition(_ sender: NSMenuItem) {
        let screens = NSScreen.screens
        let main = NSScreen.main ?? screens.first
        let visible = main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = panel.frame.width
        let height = panel.frame.height
        let x = max(visible.minX, visible.maxX - width - 24)
        let topY = max(visible.minY + height, visible.maxY - 24)
        let frame = NSRect(x: x, y: topY - height, width: width, height: height)
        isProgrammaticFrame = true
        panel.setFrame(frame, display: true)
        isProgrammaticFrame = false
        clampToScreen()
        scheduleStateSave()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        persistStateNow()
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var configURL = ConfigStore.defaultConfigURL
        var stateURL = ConfigStore.defaultStateURL
        var snapshotPath: String?
        var snapshotDelay: TimeInterval = 3

        let arguments = CommandLine.arguments
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--config" where index + 1 < arguments.count:
                configURL = URL(fileURLWithPath: arguments[index + 1])
                index += 1
            case "--state" where index + 1 < arguments.count:
                stateURL = URL(fileURLWithPath: arguments[index + 1])
                index += 1
            case "--snapshot" where index + 1 < arguments.count:
                snapshotPath = arguments[index + 1]
                index += 1
            case "--snapshot-delay" where index + 1 < arguments.count:
                snapshotDelay = TimeInterval(arguments[index + 1]) ?? 3
                index += 1
            default:
                break
            }
            index += 1
        }

        let controller = AppController(
            configURL: configURL,
            stateURL: stateURL,
            snapshotPath: snapshotPath,
            snapshotDelay: snapshotDelay
        )
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.persistStateNow()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
