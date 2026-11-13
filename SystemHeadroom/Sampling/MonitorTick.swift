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

/// The GPU's state for one tick. The registry reading plus the
/// per-process percents the sampler service computed from it.
struct GPUSample: Sendable, Equatable {
  let model: String?
  let coreCount: Int?
  let utilizationPercent: Double
  let rendererPercent: Double?
  let tilerPercent: Double?
  let allocatedMemoryBytes: UInt64?
  let inUseMemoryBytes: UInt64?
  /// Share of wall time per pid. nil until a second tick gives the
  /// counters a delta; a pid is absent when its own delta is unknown.
  let processPercents: [Int32: Double]?
  /// Registry names for pids outside the same-user process table.
  let processNames: [Int32: String]
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
  /// nil when no accelerator reported utilization this tick; the GPU
  /// tab shows its unavailable state.
  let gpu: GPUSample?
  /// Drives only, startup volume first. Empty when none could be read.
  let volumes: [VolumeSnapshot]
  /// Keyed by physical disk. A disk is absent until its second tick.
  let diskActivity: [String: DiskActivity]
  /// Always empty in the sandboxed build, which may not read SMART.
  let driveHealth: [DriveHealth]
}
