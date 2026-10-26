import Foundation
import Testing

@testable import SystemHeadroom

/// Records what the store asked for instead of touching
/// UNUserNotificationCenter, which would prompt inside the test host.
@MainActor
final class RecordingAlertDelivery: AlertDelivery {
  var authorizationRequests = 0
  var delivered: [CPUAlert] = []

  func requestAuthorization() {
    authorizationRequests += 1
  }

  func deliver(_ alert: CPUAlert) {
    delivered.append(alert)
  }
}

@Suite("Store alerts")
@MainActor
struct StoreAlertTests {
  static func makeStore(delivery: RecordingAlertDelivery) -> MonitorStore {
    let suiteName = "com.vinnycarpenter.SystemHeadroomTests.alerts.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return MonitorStore(
      defaults: defaults, capability: .sandboxed,
      terminator: ProcessTerminator(
        runningApplication: { _ in nil },
        currentStartIdentity: { _ in nil },
        sendSignal: { _, _ in 0 }),
      alertDelivery: delivery)
  }

  static func group(_ key: String, cpu: Double?) -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: 77, parentPID: 1, userID: 501, name: key,
      startIdentity: "1:1", cpuTimeTicks: 0, memoryBytes: 1)
    return AppGroup(
      groupKey: key, name: key, bundleIdentifier: nil,
      representativePID: 77, cpuPercent: cpu, memoryBytes: 1,
      children: [ProcessMeasurement(snapshot: snapshot, cpuPercent: cpu)])
  }

  @Test("Candidates convert machine-capacity percent to percent of one core and drop nil")
  func candidatesConvert() {
    let groups = [Self.group("a", cpu: 10), Self.group("b", cpu: nil)]
    let machine = MonitorStore.candidates(
      from: groups, convention: .machineCapacity, logicalCoreCount: 14)
    #expect(machine.map(\.groupKey) == ["name:a"])
    #expect(machine.map(\.percentOfCore) == [140])
    let perCore = MonitorStore.candidates(
      from: groups, convention: .perCore, logicalCoreCount: 14)
    #expect(perCore.map(\.percentOfCore) == [10])
  }

  @Test("A group over the threshold on a 14-core tick is delivered once")
  func deliversOverThreshold() {
    let delivery = RecordingAlertDelivery()
    let store = Self.makeStore(delivery: delivery)
    store.cpuAlertsEnabled = true
    defer { store.cpuAlertsEnabled = false }
    store.cpuAlertSustainSeconds = 0
    store.cpuAlertThresholdPercent = 90

    store.evaluateAlerts(
      groups: [Self.group("chrome", cpu: 10), Self.group("slack", cpu: 5)],
      convention: .machineCapacity, logicalCoreCount: 14, now: Date())

    #expect(delivery.delivered.map(\.groupKey) == ["name:chrome"])
    #expect(delivery.delivered.first?.percentOfCore == 140)
    #expect(delivery.delivered.first?.title == "chrome at 140% CPU")
  }

  /// The groups were computed under the tick's convention, so the
  /// conversion must use that one even if the preference changed while
  /// the sampler was running.
  @Test("Evaluation converts with the convention the tick was computed under")
  func usesTickConvention() {
    let delivery = RecordingAlertDelivery()
    let store = Self.makeStore(delivery: delivery)
    store.cpuConvention = .perCore
    store.cpuAlertsEnabled = true
    defer { store.cpuAlertsEnabled = false }
    store.cpuAlertSustainSeconds = 0

    store.evaluateAlerts(
      groups: [Self.group("chrome", cpu: 10)], convention: .machineCapacity,
      logicalCoreCount: 14, now: Date())

    #expect(delivery.delivered.first?.percentOfCore == 140)
  }

  @Test("Alerts off delivers nothing")
  func alertsOffDeliversNothing() {
    let delivery = RecordingAlertDelivery()
    let store = Self.makeStore(delivery: delivery)
    store.cpuAlertSustainSeconds = 0

    store.evaluateAlerts(
      groups: [Self.group("chrome", cpu: 10)], convention: .machineCapacity,
      logicalCoreCount: 14, now: Date())

    #expect(delivery.delivered.isEmpty)
    #expect(delivery.authorizationRequests == 0)
  }

  static func group(
    key: String, name: String, bundleIdentifier: String?, pid: Int32, cpu: Double?
  ) -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: pid, parentPID: 1, userID: 501, name: name,
      startIdentity: "\(pid):1", cpuTimeTicks: 0, memoryBytes: 1)
    return AppGroup(
      groupKey: key, name: name, bundleIdentifier: bundleIdentifier,
      representativePID: pid, cpuPercent: cpu, memoryBytes: 1,
      children: [ProcessMeasurement(snapshot: snapshot, cpuPercent: cpu)])
  }

  /// The list keys a bundle-less process by pid so two `node` servers
  /// get two rows. The cooldown is per app as the user sees it, so the
  /// alert identity is the name instead; a bundled app keeps its id.
  @Test("Bundle-less groups alert by name, bundled apps by bundle id")
  func alertKeys() {
    let groups = [
      Self.group(key: "pid:23574", name: "yes", bundleIdentifier: nil, pid: 23574, cpu: 7),
      Self.group(
        key: "com.google.Chrome", name: "Google Chrome",
        bundleIdentifier: "com.google.Chrome", pid: 900, cpu: 12),
    ]
    let candidates = MonitorStore.candidates(
      from: groups, convention: .perCore, logicalCoreCount: 14)
    #expect(candidates.map(\.groupKey) == ["name:yes", "com.google.Chrome"])
    #expect(candidates.map(\.name) == ["yes", "Google Chrome"])
  }

  @Test("Two same-name bundle-less processes merge into one candidate at the higher reading")
  func sameNameMerges() {
    let groups = [
      Self.group(key: "pid:1", name: "yes", bundleIdentifier: nil, pid: 1, cpu: 3),
      Self.group(key: "pid:2", name: "yes", bundleIdentifier: nil, pid: 2, cpu: 7),
    ]
    let candidates = MonitorStore.candidates(
      from: groups, convention: .machineCapacity, logicalCoreCount: 14)
    #expect(candidates.map(\.groupKey) == ["name:yes"])
    #expect(candidates.map(\.percentOfCore) == [98])
  }

  @Test("A restarted bundle-less process stays inside the cooldown")
  func restartedProcessKeepsCooldown() {
    let delivery = RecordingAlertDelivery()
    let store = Self.makeStore(delivery: delivery)
    store.cpuAlertsEnabled = true
    defer { store.cpuAlertsEnabled = false }
    store.cpuAlertSustainSeconds = 0
    store.cpuAlertThresholdPercent = 50
    let start = Date()

    store.evaluateAlerts(
      groups: [Self.group(key: "pid:23574", name: "yes", bundleIdentifier: nil, pid: 23574, cpu: 7)],
      convention: .machineCapacity, logicalCoreCount: 14, now: start)
    store.evaluateAlerts(
      groups: [], convention: .machineCapacity, logicalCoreCount: 14, now: start + 30)
    store.evaluateAlerts(
      groups: [Self.group(key: "pid:24983", name: "yes", bundleIdentifier: nil, pid: 24983, cpu: 7)],
      convention: .machineCapacity, logicalCoreCount: 14, now: start + 60)

    #expect(delivery.delivered.map(\.name) == ["yes"])
  }
}
