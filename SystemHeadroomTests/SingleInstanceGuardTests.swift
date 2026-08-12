import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Single instance guard")
struct SingleInstanceGuardTests {
  /// A newly activated guard broadcasts a takeover notice. An older guard
  /// hearing a notice from a different instance terminates; the new guard
  /// must ignore the echo of its own notice.
  @Test("A newer instance's takeover notice terminates the older instance only")
  @MainActor
  func newerInstanceWins() async throws {
    // A private channel: fixture notices on the real name would reach the
    // host app's own guard and terminate the test host.
    let channel = Notification.Name(
      "com.vinnycarpenter.SystemHeadroom.instance-takeover.test.\(UUID().uuidString)")

    await confirmation("older instance terminates") { olderTerminated in
      let older = SingleInstanceGuard(notificationName: channel, ownIdentifier: "older") {
        olderTerminated()
      }
      older.activate()

      // Let the older guard's own launch notice flush before the newer
      // guard starts observing, mirroring real launch spacing.
      try? await Task.sleep(for: .milliseconds(400))

      let newer = SingleInstanceGuard(notificationName: channel, ownIdentifier: "newer") {
        Issue.record("The newer instance must not terminate itself")
      }
      newer.activate()

      try? await Task.sleep(for: .milliseconds(600))
      older.deactivate()
      newer.deactivate()
    }
  }
}
