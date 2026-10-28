import AppKit

let application = NSApplication.shared
let appDelegate = MainActor.assumeIsolated {
    AppDelegate.launchTimestamp = Date()
    return AppDelegate()
}
application.delegate = appDelegate
application.run()
