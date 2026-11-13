import Foundation

enum ValueFormatting {
  /// Under the machine-capacity convention one full core is only ~7% on
  /// current Apple Silicon, so whole-number rounding rendered nearly every
  /// row as "0%". Keep one decimal below 10 so light usage stays legible.
  static func percent(_ value: Double?) -> String {
    guard let value else { return "—" }
    let tenths = (value * 10).rounded() / 10
    if tenths < 10 {
      return String(format: "%.1f%%", tenths)
    }
    return "\(Int(value.rounded()))%"
  }

  static func bytes(_ value: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(clamping: value))
  }

  static func value(
    _ metric: MetricKind,
    for group: AppGroup,
    memoryMetric: ProcessMemoryMetric
  ) -> String {
    switch metric {
    case .cpu: percent(group.cpuPercent)
    case .memory: memory(group.memoryBytes, metric: memoryMetric)
    }
  }

  static func memory(_ value: UInt64, metric: ProcessMemoryMetric) -> String {
    let formatted = bytes(value)
    return metric == .residentSize ? "\(formatted) RSS" : formatted
  }

  /// Drive sizes in decimal units, the way Finder counts them. Memory
  /// uses `bytes`, which counts in binary units.
  static func diskBytes(_ value: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(clamping: value))
  }

  /// Decimal megabytes, one decimal below 10 so a quiet disk still
  /// shows movement.
  static func megabytesPerSecond(_ bytesPerSecond: Double) -> String {
    let megabytes = max(bytesPerSecond, 0) / 1_000_000
    let tenths = (megabytes * 10).rounded() / 10
    if tenths < 10 {
      return String(format: "%.1f", tenths)
    }
    return "\(Int(megabytes.rounded()))"
  }

  static func throughput(_ activity: DiskActivity?) -> String {
    guard let activity else { return "R — · W — MB/s" }
    return "R \(megabytesPerSecond(activity.readBytesPerSecond)) · "
      + "W \(megabytesPerSecond(activity.writeBytesPerSecond)) MB/s"
  }

  /// In the unit the reader's region uses for weather, so 38 C reads as
  /// 100°F in the United States.
  static func temperature(celsius: Int, locale: Locale) -> String {
    Measurement(value: Double(celsius), unit: UnitTemperature.celsius)
      .formatted(
        .measurement(
          width: .abbreviated, usage: .weather,
          numberFormatStyle: .number.precision(.fractionLength(0))
        )
        .locale(locale))
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
