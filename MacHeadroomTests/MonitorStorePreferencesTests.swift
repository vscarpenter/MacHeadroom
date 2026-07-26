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

@Suite("Store termination gating")
@MainActor
struct StoreTerminationTests {
  static func makeStore(
    capability: TerminationCapability,
    terminator: ProcessTerminator
  ) -> MonitorStore {
    // Mirrors MonitorStorePreferencesTests.makeDefaults(): a UUID-suffixed
    // scratch suite, cleared before use, so parallel tests never share state.
    let suiteName = "com.vinnycarpenter.MacHeadroomTests.termination.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return MonitorStore(
      defaults: defaults, capability: capability, terminator: terminator)
  }

  static func someGroup() -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: 77, parentPID: 1, userID: 501, name: "victim",
      startIdentity: "1:1", cpuTimeTicks: 0, residentBytes: 1)
    return AppGroup(
      groupKey: "victim", name: "victim", bundleIdentifier: nil,
      representativePID: 77, cpuPercent: nil, memoryBytes: 1,
      children: [ProcessMeasurement(snapshot: snapshot, cpuPercent: nil)])
  }

  @Test("Sandboxed store never invokes the terminator")
  func sandboxedStoreNoOps() {
    var calls = 0
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in calls += 1; return "1:1" },
      sendSignal: { _, _ in calls += 1; return 0 })
    let store = Self.makeStore(capability: .sandboxed, terminator: terminator)
    #expect(store.canTerminate == false)
    store.quit(Self.someGroup())
    store.forceQuit(Self.someGroup())
    #expect(calls == 0)
  }

  @Test("Capable store routes quit and force quit to the terminator")
  func capableStoreRoutes() {
    var signals: [Int32] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, sig in signals.append(sig); return 0 })
    let store = Self.makeStore(capability: .available, terminator: terminator)
    #expect(store.canTerminate == true)
    store.quit(Self.someGroup())
    store.forceQuit(Self.someGroup())
    #expect(signals == [SIGTERM, SIGKILL])
  }
}
