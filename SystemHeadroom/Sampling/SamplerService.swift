import Darwin
import Foundation
import os

/// Owns the sampling loop's mutable state: the previous tick's process and
/// host readings, used to compute this tick's deltas. One tick, one
/// enumeration pass, per the brief's performance budget.
actor SamplerService {
  private var previousSnapshotsByPID: [Int32: ProcessSnapshot] = [:]
  private var previousHostTicks: HostCPUTicks?
  private var previousTimestamp: UInt64?
  private var lastSocketsFailed = false
  private let timebase: mach_timebase_info_data_t
  private let logicalCoreCount: Int
  private let processMemoryMetric: ProcessMemoryMetric

  private static let log = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "ports")

  init(
    timebase: mach_timebase_info_data_t = SamplerService.currentTimebase(),
    logicalCoreCount: Int = max(ProcessInfo.processInfo.activeProcessorCount, 1),
    processMemoryMetric: ProcessMemoryMetric = .current
  ) {
    self.timebase = timebase
    self.logicalCoreCount = logicalCoreCount
    self.processMemoryMetric = processMemoryMetric
  }

  static func currentTimebase() -> mach_timebase_info_data_t {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }

  /// The actor owns the clock: the timestamp is taken here, next to the
  /// sweep, never passed in. A caller-captured timestamp goes stale while
  /// the call waits its turn on the actor, and dividing a full sweep's CPU
  /// accrual by that near-zero wall time inflated percentages a
  /// thousandfold when two refreshes overlapped.
  func tick(convention: CPUConvention) -> MonitorTick {
    let now = DispatchTime.now().uptimeNanoseconds
    let table = ProcessTableSampler.sampleTable(memoryMetric: processMemoryMetric)
    let snapshots = table.snapshots
    let wallTime = previousTimestamp.flatMap { now > $0 ? now - $0 : nil } ?? 0

    let sockets = PortTableParser.listeningSockets(
      tcpTable: PortTableSampler.fetchTCPTable(),
      udpTable: PortTableSampler.fetchUDPTable())
    // Log the failure transition once, not every tick: a persistent
    // seatbelt or layout change would otherwise spam a fault per tick.
    if sockets == nil, !lastSocketsFailed {
      Self.log.fault("port table fetch or parse failed; ports pane unavailable")
    }
    lastSocketsFailed = sockets == nil

    let snapshotPIDs = Set(snapshots.map(\.pid))
    var socketFallbackNames: [Int32: String] = [:]
    for record in sockets ?? [] where !snapshotPIDs.contains(record.pid) {
      socketFallbackNames[record.pid] = table.commandNamesByPID[record.pid]
    }

    let measurements = snapshots.map { snapshot -> ProcessMeasurement in
      let previous = previousSnapshotsByPID[snapshot.pid]
      let input = CPUDeltaInput(
        previousTicks: previous?.cpuTimeTicks,
        previousStartIdentity: previous?.startIdentity,
        currentTicks: snapshot.cpuTimeTicks,
        currentStartIdentity: snapshot.startIdentity,
        wallTimeNanoseconds: wallTime
      )
      let percent = CPUDelta.percent(
        for: input,
        timebase: timebase,
        logicalCoreCount: logicalCoreCount,
        convention: convention
      )
      return ProcessMeasurement(snapshot: snapshot, cpuPercent: percent)
    }

    let hostTicks = HostSampler.sampleCPUTicks()
    let hostMemory = HostSampler.sampleMemory()
    let hostPercent = hostTicks.flatMap { current in
      HostCPUDelta.percent(previous: previousHostTicks, current: current)
    }

    previousSnapshotsByPID = Dictionary(
      uniqueKeysWithValues: snapshots.map { ($0.pid, $0) }
    )
    previousHostTicks = hostTicks
    previousTimestamp = now

    return MonitorTick(
      processes: measurements,
      system: SystemSummary(
        cpuPercent: hostPercent,
        memoryUsedBytes: hostMemory?.usedBytes ?? 0,
        memoryTotalBytes: hostMemory?.totalBytes ?? 0
      ),
      processMemoryMetric: processMemoryMetric,
      sockets: sockets,
      socketFallbackNames: socketFallbackNames
    )
  }
}
