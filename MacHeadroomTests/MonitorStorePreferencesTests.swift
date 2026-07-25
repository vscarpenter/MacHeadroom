import Foundation
import Testing

@testable import MacHeadroom

@Suite("Monitor store preferences", .serialized)
struct MonitorStorePreferencesTests {
  @Test("Max Headroom mode defaults off")
  @MainActor
  func maxHeadroomModeDefaultsOff() throws {
    let (suiteName, defaults) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = MonitorStore(defaults: defaults)

    #expect(store.maxHeadroomModeEnabled == false)
  }

  @Test("Max Headroom mode persists")
  @MainActor
  func maxHeadroomModePersists() throws {
    let (suiteName, defaults) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = MonitorStore(defaults: defaults)
    store.maxHeadroomModeEnabled = true

    let restoredStore = MonitorStore(defaults: defaults)
    #expect(restoredStore.maxHeadroomModeEnabled)
  }

  private func makeDefaults() throws -> (String, UserDefaults) {
    let suiteName = "com.vinnycarpenter.MacHeadroomTests.preferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (suiteName, defaults)
  }
}
