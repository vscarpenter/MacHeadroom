import Foundation
import Testing

@testable import SystemHeadroom

@Suite("CPU alert tracker")
struct CPUAlertTrackerTests {
  private let policy = CPUAlertPolicy(thresholdPercentOfCore: 90, sustainSeconds: 60)
  private let t0 = Date(timeIntervalSinceReferenceDate: 0)

  private func chrome(_ percent: Double) -> CPUAlertCandidate {
    CPUAlertCandidate(groupKey: "com.google.Chrome", name: "Google Chrome", percentOfCore: percent)
  }

  private func at(_ seconds: Double) -> Date {
    t0.addingTimeInterval(seconds)
  }

  @Test("Below threshold never alerts")
  func belowThreshold() {
    var tracker = CPUAlertTracker()
    #expect(tracker.observe([chrome(50)], at: at(0), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(70)], at: at(120), policy: policy).isEmpty)
  }

  @Test("Above threshold but shorter than sustain does not alert")
  func shorterThanSustain() {
    var tracker = CPUAlertTracker()
    #expect(tracker.observe([chrome(180)], at: at(0), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(59), policy: policy).isEmpty)
  }

  @Test("Sustained above threshold alerts exactly once with the notification copy")
  func sustainedAlertsOnce() throws {
    var tracker = CPUAlertTracker()
    _ = tracker.observe([chrome(180)], at: at(0), policy: policy)
    let alerts = tracker.observe([chrome(180)], at: at(60), policy: policy)
    let alert = try #require(alerts.first)
    #expect(alerts.count == 1)
    #expect(alert.groupKey == "com.google.Chrome")
    #expect(alert.title == "Google Chrome at 180% CPU")
    #expect(alert.body == "Above 90% of a core for 1 minute.")
  }

  @Test("Still above after alerting does not repeat")
  func noRepeatWhileStillAbove() {
    var tracker = CPUAlertTracker()
    _ = tracker.observe([chrome(180)], at: at(0), policy: policy)
    _ = tracker.observe([chrome(180)], at: at(60), policy: policy)
    #expect(tracker.observe([chrome(180)], at: at(120), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(400), policy: policy).isEmpty)
  }

  @Test("Dropping below and re-crossing inside the cooldown stays quiet")
  func cooldownSuppressesNewEpisode() {
    var tracker = CPUAlertTracker()
    _ = tracker.observe([chrome(180)], at: at(0), policy: policy)
    _ = tracker.observe([chrome(180)], at: at(60), policy: policy)
    #expect(tracker.observe([chrome(10)], at: at(70), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(80), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(140), policy: policy).isEmpty)
  }

  @Test("After the cooldown a new episode alerts again")
  func alertsAgainAfterCooldown() {
    var tracker = CPUAlertTracker()
    _ = tracker.observe([chrome(180)], at: at(0), policy: policy)
    _ = tracker.observe([chrome(180)], at: at(60), policy: policy)
    _ = tracker.observe([chrome(10)], at: at(70), policy: policy)
    #expect(tracker.observe([chrome(180)], at: at(361), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(421), policy: policy).count == 1)
  }

  @Test("A group that leaves the list resets its episode")
  func leavingTheListResets() {
    var tracker = CPUAlertTracker()
    _ = tracker.observe([chrome(180)], at: at(0), policy: policy)
    #expect(tracker.observe([], at: at(30), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(50), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(100), policy: policy).isEmpty)
    #expect(tracker.observe([chrome(180)], at: at(110), policy: policy).count == 1)
  }

  @Test("Zero sustain alerts on the first qualifying sample")
  func zeroSustain() {
    var tracker = CPUAlertTracker()
    let instant = CPUAlertPolicy(thresholdPercentOfCore: 90, sustainSeconds: 0)
    #expect(tracker.observe([chrome(180)], at: at(0), policy: instant).count == 1)
  }

  @Test(
    "Sustain descriptions",
    arguments: [(30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes")])
  func sustainDescriptions(seconds: Int, expected: String) {
    #expect(CPUAlertPolicy.describe(sustainSeconds: seconds) == expected)
  }
}
