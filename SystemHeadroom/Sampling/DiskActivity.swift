/// A physical disk's lifetime byte counters, from its
/// IOBlockStorageDriver `Statistics` property.
struct DiskCounters: Sendable, Equatable {
  let readBytes: UInt64
  let writeBytes: UInt64
}

/// Read and write throughput over one sampling interval.
struct DiskActivity: Sendable, Equatable {
  let readBytesPerSecond: Double
  let writeBytesPerSecond: Double
}

enum DiskActivityDelta {
  /// nil on the first tick, on zero wall time, and when either counter
  /// moved backward. Counters only fall when a different disk took the
  /// same BSD name, and a rate across two disks would be fiction.
  static func activity(
    previous: DiskCounters?,
    current: DiskCounters,
    wallTimeNanoseconds: UInt64
  ) -> DiskActivity? {
    guard let previous, wallTimeNanoseconds > 0,
      current.readBytes >= previous.readBytes,
      current.writeBytes >= previous.writeBytes
    else { return nil }
    let seconds = Double(wallTimeNanoseconds) / 1_000_000_000
    return DiskActivity(
      readBytesPerSecond: Double(current.readBytes - previous.readBytes) / seconds,
      writeBytesPerSecond: Double(current.writeBytes - previous.writeBytes) / seconds)
  }
}
