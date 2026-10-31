import AppKit
import Foundation
import UserNotifications
import OverplayCore

@MainActor
final class NotificationManager: ObservableObject {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let current = await authorizationStatus()
        guard current == .notDetermined else { return current }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return await authorizationStatus()
        }
        return await authorizationStatus()
    }

    func post(title: String, body: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func post(events: [AlertEvent]) async {
        for event in events.prefix(5) {
            _ = await post(
                title: "\(event.renderedTitle) · \(event.accountName)",
                body: L10n.f(
                    "notification.1afa529f8c",
                    event.renderedValue,
                    event.renderedThreshold,
                    AlertMetricText.localized(event.metric)
                )
            )
        }
    }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
