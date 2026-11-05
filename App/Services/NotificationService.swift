import Foundation
import UserNotifications

/// Notifications locales "Time-Sensitive" de fin de repos (iPhone verrouillé).
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    static let restEndID = "rest.end"

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleRestEnd(at date: Date, nextSet: String) {
        cancelRestEnd()
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Repos terminé 💪"
        content.body = nextSet.isEmpty ? "C'est reparti !" : "À toi : \(nextSet)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.threadIdentifier = "rest"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.restEndID, content: content, trigger: trigger))
    }

    func cancelRestEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restEndID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.restEndID])
    }

    // App au premier plan : on affiche quand même la bannière (en plus de l'alerte in-app).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
