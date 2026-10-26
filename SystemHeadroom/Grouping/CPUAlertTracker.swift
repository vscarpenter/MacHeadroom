import Foundation

/// What counts as a sustained CPU episode. The percent is always of one
/// core, the way Activity Monitor counts; the store converts a displayed
/// machine-capacity percent before the tracker sees a candidate.
struct CPUAlertPolicy: Sendable, Equatable {
  let thresholdPercentOfCore: Int
  let sustainSeconds: Int
  var cooldownSeconds: Int = 300

  /// The picker label and the notification body share this wording.
  static func describe(sustainSeconds: Int) -> String {
    if sustainSeconds < 60 { return "\(sustainSeconds) seconds" }
    let minutes = sustainSeconds / 60
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}

struct CPUAlertCandidate: Sendable, Equatable {
  let groupKey: String
  let name: String
  let percentOfCore: Double
}

struct CPUAlert: Sendable, Equatable {
  let groupKey: String
  let name: String
  let percentOfCore: Double
  let policy: CPUAlertPolicy

  var title: String {
    "\(name) at \(Int(percentOfCore.rounded()))% CPU"
  }

  var body: String {
    "Above \(policy.thresholdPercentOfCore)% of a core for "
      + "\(CPUAlertPolicy.describe(sustainSeconds: policy.sustainSeconds))."
  }
}

/// Pure decision behind the notification: one alert per episode, and a
/// cooldown per app after each alert. An episode starts when an app's
/// per-core percent reaches the threshold and ends when it drops below
/// or leaves the list. No clock of its own: `now` comes in, so tests
/// drive time.
struct CPUAlertTracker: Sendable {
  private var episodeStarts: [String: Date] = [:]
  private var notifiedEpisodes: Set<String> = []
  private var lastNotified: [String: Date] = [:]

  init() {}

  mutating func observe(
    _ candidates: [CPUAlertCandidate], at now: Date, policy: CPUAlertPolicy
  ) -> [CPUAlert] {
    let present = Set(candidates.map(\.groupKey))
    for key in episodeStarts.keys.filter({ !present.contains($0) }) {
      endEpisode(key)
    }

    var alerts: [CPUAlert] = []
    for candidate in candidates {
      let key = candidate.groupKey
      guard candidate.percentOfCore >= Double(policy.thresholdPercentOfCore) else {
        endEpisode(key)
        continue
      }
      let start = episodeStarts[key] ?? now
      episodeStarts[key] = start
      guard now.timeIntervalSince(start) >= Double(policy.sustainSeconds) else { continue }
      guard !notifiedEpisodes.contains(key) else { continue }
      if let last = lastNotified[key],
        now.timeIntervalSince(last) < Double(policy.cooldownSeconds)
      {
        continue
      }
      alerts.append(
        CPUAlert(
          groupKey: key, name: candidate.name,
          percentOfCore: candidate.percentOfCore, policy: policy))
      notifiedEpisodes.insert(key)
      lastNotified[key] = now
    }
    return alerts
  }

  private mutating func endEpisode(_ key: String) {
    episodeStarts[key] = nil
    notifiedEpisodes.remove(key)
  }
}
