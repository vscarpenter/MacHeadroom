struct ProcessMeasurement: Sendable, Equatable {
  let snapshot: ProcessSnapshot
  let cpuPercent: Double?
}

struct SystemSummary: Sendable, Equatable {
  let cpuPercent: Double?
  let memoryUsedBytes: UInt64
  let memoryTotalBytes: UInt64
}

struct MonitorTick: Sendable, Equatable {
  let processes: [ProcessMeasurement]
  let system: SystemSummary
}
