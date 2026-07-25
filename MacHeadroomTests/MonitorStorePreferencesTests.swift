import Foundation
import Testing

@testable import MacHeadroom

@Suite("Monitor store preferences", .serialized)
struct MonitorStorePreferencesTests {
  @Test("Porcelain Native defaults on")
  @MainActor
  func porcelainNativeDefaultsOn() throws {
    let (suiteName, defaults) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = MonitorStore(defaults: defaults)

    #expect(store.usesPorcelainAppearance)
  }

  @Test("Classic appearance persists")
  @MainActor
  func classicAppearancePersists() throws {
    let (suiteName, defaults) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = MonitorStore(defaults: defaults)
    store.usesPorcelainAppearance = false

    let restoredStore = MonitorStore(defaults: defaults)
    #expect(restoredStore.usesPorcelainAppearance == false)
  }

  @Test("Legacy Max Headroom preference migrates")
  @MainActor
  func legacyMaxHeadroomPreferenceMigrates() throws {
    for legacyValue in [false, true] {
      let (suiteName, defaults) = try makeDefaults()
      defer { defaults.removePersistentDomain(forName: suiteName) }
      defaults.set(legacyValue, forKey: "maxHeadroomModeEnabled")

      let store = MonitorStore(defaults: defaults)

      #expect(store.usesPorcelainAppearance == legacyValue)
      #expect(
        defaults.object(forKey: "usesPorcelainAppearance") as? Bool == legacyValue
      )
    }
  }

  private func makeDefaults() throws -> (String, UserDefaults) {
    let suiteName = "com.vinnycarpenter.MacHeadroomTests.preferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (suiteName, defaults)
  }
}
