import Foundation
import Testing

@testable import SystemHeadroom

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
    let suiteName = "com.vinnycarpenter.SystemHeadroomTests.preferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (suiteName, defaults)
  }
}

@Suite("Store sampling cadence")
struct StoreSamplingCadenceTests {
  /// The first tick after launch can only prime the CPU baseline (every
  /// delta needs two samples). The store must follow it with a quick
  /// second sample so the popover shows real CPU numbers in about a
  /// second, not a full sampling interval later.
  ///
  /// The stored interval is pushed out to 30 seconds so the two cadences
  /// sit far apart: the quick follow-up is capped at 1 second, so data
  /// landing inside the deadline can only mean the follow-up ran. An
  /// earlier version raced a 3-second deadline against the 5-second
  /// default, which left under 2 seconds for two full process-table
  /// sweeps. That cleared locally by 0.4 seconds and timed out on CI,
  /// where the same sweeps run up to 2.6x slower.
  @Test("Opening the popover publishes CPU data well before the first full interval")
  @MainActor
  func quickSecondSampleAfterPriming() async throws {
    let suiteName = "com.vinnycarpenter.SystemHeadroomTests.cadence.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(30, forKey: "samplingInterval")

    let store = MonitorStore(defaults: defaults)
    // Guards the gap this test rests on: if the defaults key ever drifts,
    // the store falls back to 5 seconds and this goes quietly flaky again.
    #expect(store.samplingInterval == 30)
    store.popoverDidAppear()
    defer { store.popoverDidDisappear() }

    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while store.systemSummary.cpuPercent == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }

    #expect(store.systemSummary.cpuPercent != nil)
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
    let suiteName = "com.vinnycarpenter.SystemHeadroomTests.termination.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return MonitorStore(
      defaults: defaults, capability: capability, terminator: terminator)
  }

  static func someGroup() -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: 77, parentPID: 1, userID: 501, name: "victim",
      startIdentity: "1:1", cpuTimeTicks: 0, memoryBytes: 1)
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
