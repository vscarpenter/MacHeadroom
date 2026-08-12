import AppKit
import Foundation

/// Keeps a single System Headroom instance alive: each new instance broadcasts
/// a takeover notice, and any instance hearing a notice from a different
/// sender quits, so the newest launch always wins. LaunchServices already
/// blocks double-launches from Finder and `open`; this covers what it
/// doesn't, like direct executions and Xcode debug runs. Distributed
/// notifications work inside App Sandbox, unlike terminating another app.
@MainActor
final class SingleInstanceGuard {
  static let takeoverNotification = Notification.Name(
    "com.vinnycarpenter.SystemHeadroom.instance-takeover")

  private let notificationName: Notification.Name
  private let ownIdentifier: String
  private let terminate: @MainActor () -> Void
  private var observer: NSObjectProtocol?

  /// Tests inject their own notification name so fixture notices never
  /// reach the host app's real guard, which would terminate the test host.
  init(
    notificationName: Notification.Name = SingleInstanceGuard.takeoverNotification,
    ownIdentifier: String = String(ProcessInfo.processInfo.processIdentifier),
    terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
  ) {
    self.notificationName = notificationName
    self.ownIdentifier = ownIdentifier
    self.terminate = terminate
  }

  func activate() {
    guard observer == nil else { return }
    let center = DistributedNotificationCenter.default()
    let own = ownIdentifier
    let fire = terminate
    observer = center.addObserver(
      forName: notificationName, object: nil, queue: .main
    ) { notification in
      guard let sender = notification.object as? String, sender != own else {
        return
      }
      Task { @MainActor in fire() }
    }
    // Sandboxed distributed notifications cannot carry userInfo; the sender
    // identity travels in the object string instead.
    center.postNotificationName(
      notificationName, object: ownIdentifier, userInfo: nil,
      deliverImmediately: true)
  }

  /// The app itself never deactivates; the guard lives as long as the
  /// process. Tests deactivate so short-lived guards stop observing.
  func deactivate() {
    if let observer {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
    observer = nil
  }
}
