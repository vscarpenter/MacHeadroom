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
  let processMemoryMetric: ProcessMemoryMetric
  /// nil when the port tables could not be fetched or parsed this tick;
  /// the ports pane shows its unavailable state rather than stale rows.
  let sockets: [SocketRecord]?
  /// p_comm names for socket-owning pids outside the snapshot set (root
  /// listeners). A vanished process may be absent here.
  let socketFallbackNames: [Int32: String]
}
