struct ProcessMeasurement: Sendable, Equatable {
  let snapshot: ProcessSnapshot
  let cpuPercent: Double?
}

struct SystemSummary: Sendable, Equatable {
  let cpuPercent: Double?
  let memoryUsedBytes: UInt64
  let memoryTotalBytes: UInt64
  /// nil when the sysctl read failed this tick; the badge shows Unknown.
  var memoryPressure: MemoryPressureLevel? = nil
  /// Bytes of swap in use right now; nil when the read failed.
  var swapUsedBytes: UInt64? = nil
}

struct MonitorTick: Sendable, Equatable {
  let processes: [ProcessMeasurement]
  let system: SystemSummary
  let processMemoryMetric: ProcessMemoryMetric
  /// The convention and core count the CPU percents were computed
  /// under, so the store converts back to percent of one core with the
  /// same pair even if the preference changed during the sweep.
  let convention: CPUConvention
  let logicalCoreCount: Int
  /// nil when the port tables could not be fetched or parsed this tick;
  /// the ports pane shows its unavailable state rather than stale rows.
  let sockets: [SocketRecord]?
  /// p_comm names for socket-owning pids outside the snapshot set (root
  /// listeners). A vanished process may be absent here.
  let socketFallbackNames: [Int32: String]
}
