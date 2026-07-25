import Foundation

enum ValueFormatting {
  static func percent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int(value.rounded()))%"
  }

  static func bytes(_ value: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(clamping: value))
  }

  static func value(_ metric: MetricKind, for group: AppGroup) -> String {
    switch metric {
    case .cpu: percent(group.cpuPercent)
    case .memory: bytes(group.memoryBytes)
    }
  }

  static func headroomPercent(used: Double?, capacity: Double) -> Int? {
    guard let used, used.isFinite, capacity.isFinite, capacity > 0 else { return nil }
    let remaining = min(max(1 - (used / capacity), 0), 1)
    return Int((remaining * 100).rounded())
  }

  static func updatedAgo(since date: Date?, now: Date) -> String {
    guard let date else { return "Updating…" }
    let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
    return seconds < 1 ? "Updated just now" : "Updated \(seconds)s ago"
  }
}
