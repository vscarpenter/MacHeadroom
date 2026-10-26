import Foundation
import UserNotifications
import os

/// How a CPU alert reaches the user. The store talks to this, never to
/// UNUserNotificationCenter directly, so tests inject a recorder.
@MainActor
protocol AlertDelivery: AnyObject {
  func requestAuthorization()
  func deliver(_ alert: CPUAlert)
}

/// Local notifications through UNUserNotificationCenter. The center is
/// touched only inside the two methods, never in init, so constructing a
/// store in a test never prompts. The request identifier is per app
/// group, so a newer alert for the same app replaces the older one in
/// Notification Center instead of stacking. Failures go to the unified
/// log, the only field-debugging path this app has.
@MainActor
final class NotificationAlertDelivery: NSObject, AlertDelivery, UNUserNotificationCenterDelegate {
  private static let log = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "alerts")

  func requestAuthorization() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    Task {
      do {
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        Self.log.notice(
          "notification authorization \(granted ? "granted" : "denied", privacy: .public)")
      } catch {
        Self.log.error(
          "notification authorization failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  func deliver(_ alert: CPUAlert) {
    let content = UNMutableNotificationContent()
    content.title = alert.title
    content.body = alert.body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "cpu-alert-\(alert.groupKey)", content: content, trigger: nil)
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    Task {
      do {
        try await center.add(request)
      } catch {
        Self.log.error(
          "notification delivery failed for \(alert.groupKey): \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Without a delegate, macOS hides a notification while the app is
  /// frontmost, which it is whenever the Settings window is up.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}

/// For previews and fixture stores: nothing is asked and nothing is sent.
@MainActor
final class NoOpAlertDelivery: AlertDelivery {
  func requestAuthorization() {}
  func deliver(_ alert: CPUAlert) {}
}
