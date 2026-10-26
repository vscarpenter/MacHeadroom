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
    #expect(machine.map(\.groupKey) == ["a"])
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
      logicalCoreCount: 14, now: Date())

    #expect(delivery.delivered.map(\.groupKey) == ["chrome"])
    #expect(delivery.delivered.first?.percentOfCore == 140)
    #expect(delivery.delivered.first?.title == "chrome at 140% CPU")
  }

  @Test("Alerts off delivers nothing")
  func alertsOffDeliversNothing() {
    let delivery = RecordingAlertDelivery()
    let store = Self.makeStore(delivery: delivery)
    store.cpuAlertSustainSeconds = 0

    store.evaluateAlerts(
      groups: [Self.group("chrome", cpu: 10)], logicalCoreCount: 14, now: Date())

    #expect(delivery.delivered.isEmpty)
    #expect(delivery.authorizationRequests == 0)
  }
}
