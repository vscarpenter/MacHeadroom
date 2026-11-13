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
  private var lastGPUMissing = false
  private var lastDriveHealthCount: Int?
  private var previousGPUTimeByPID: [Int32: UInt64]?
  private var previousDiskCounters: [String: DiskCounters] = [:]
  private var slowReadTimestamp: UInt64?
  private var purgeableBytes: UInt64?
  private var driveHealth: [DriveHealth] = []
  private let timebase: mach_timebase_info_data_t
  private let logicalCoreCount: Int
  private let processMemoryMetric: ProcessMemoryMetric
  private let driveHealthReader: (@Sendable () -> [DriveHealth])?
  private let slowReadIntervalNanoseconds: UInt64

  private static let log = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "ports")
  private static let hardwareLog = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "hardware")

  init(
    timebase: mach_timebase_info_data_t = SamplerService.currentTimebase(),
    logicalCoreCount: Int = max(ProcessInfo.processInfo.activeProcessorCount, 1),
    processMemoryMetric: ProcessMemoryMetric = .current,
    driveHealthReader: (@Sendable () -> [DriveHealth])? = SamplerService.liveDriveHealthReader(),
    slowReadIntervalNanoseconds: UInt64 = 60 * 1_000_000_000
  ) {
    self.timebase = timebase
    self.logicalCoreCount = logicalCoreCount
    self.processMemoryMetric = processMemoryMetric
    self.driveHealthReader = driveHealthReader
    self.slowReadIntervalNanoseconds = slowReadIntervalNanoseconds
  }

  /// nil in the sandboxed build: the SMART read opens a user client the
  /// App Sandbox denies, so that build never attempts it.
  static func liveDriveHealthReader() -> (@Sendable () -> [DriveHealth])? {
    guard DriveHealthCapability.current == .available else { return nil }
    return { DriveHealthSampler.sample() }
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

    let snapshotsByPID = Dictionary(
      uniqueKeysWithValues: snapshots.map { ($0.pid, $0) }
    )
    let gpu = sampleGPU(snapshotsByPID: snapshotsByPID, wallTime: wallTime)
    let drives = sampleDrives(now: now, wallTime: wallTime)

    let hostTicks = HostSampler.sampleCPUTicks()
    let hostMemory = HostSampler.sampleMemory()
    let memoryPressure = HostSampler.sampleMemoryPressure()
    let swap = HostSampler.sampleSwapUsage()
    let hostPercent = hostTicks.flatMap { current in
      HostCPUDelta.percent(previous: previousHostTicks, current: current)
    }

    previousSnapshotsByPID = snapshotsByPID
    previousHostTicks = hostTicks
    previousTimestamp = now

    return MonitorTick(
      processes: measurements,
      system: SystemSummary(
        cpuPercent: hostPercent,
        memoryUsedBytes: hostMemory?.usedBytes ?? 0,
        memoryTotalBytes: hostMemory?.totalBytes ?? 0,
        memoryPressure: memoryPressure,
        swapUsedBytes: swap?.usedBytes
      ),
      processMemoryMetric: processMemoryMetric,
      convention: convention,
      logicalCoreCount: logicalCoreCount,
      sockets: sockets,
      socketFallbackNames: socketFallbackNames,
      gpu: gpu,
      volumes: drives.volumes,
      diskActivity: drives.activity,
      driveHealth: driveHealth
    )
  }

  /// Must run before `previousSnapshotsByPID` is replaced: the pid-reuse
  /// guard compares each pid's start identity across the two ticks.
  private func sampleGPU(
    snapshotsByPID: [Int32: ProcessSnapshot], wallTime: UInt64
  ) -> GPUSample? {
    guard let reading = GPUSampler.sample() else {
      // Logged on the transition only, like the ports failure: an Intel
      // Mac or a virtual machine would otherwise log every tick.
      if !lastGPUMissing {
        Self.hardwareLog.notice("no accelerator reports utilization; GPU tab unavailable")
      }
      lastGPUMissing = true
      previousGPUTimeByPID = nil
      return nil
    }
    lastGPUMissing = false
    var percents: [Int32: Double]?
    if let previous = previousGPUTimeByPID, wallTime > 0 {
      percents = GPUDelta.percents(
        previous: previous,
        current: reading.gpuTimeNanosecondsByPID,
        wallTimeNanoseconds: wallTime,
        identityChanged: { pid in
          guard let before = previousSnapshotsByPID[pid], let now = snapshotsByPID[pid]
          else { return false }
          return before.startIdentity != now.startIdentity
        })
    }
    previousGPUTimeByPID = reading.gpuTimeNanosecondsByPID
    return GPUSample(
      model: reading.model,
      coreCount: reading.coreCount,
      utilizationPercent: reading.deviceUtilizationPercent,
      rendererPercent: reading.rendererUtilizationPercent,
      tilerPercent: reading.tilerUtilizationPercent,
      allocatedMemoryBytes: reading.allocatedMemoryBytes,
      inUseMemoryBytes: reading.inUseMemoryBytes,
      processPercents: percents,
      processNames: reading.clientNamesByPID)
  }

  private func sampleDrives(
    now: UInt64, wallTime: UInt64
  ) -> (volumes: [VolumeSnapshot], activity: [String: DiskActivity]) {
    var facts = VolumeSampler.sampleFacts()
    let startupIndex = facts.firstIndex(where: \.isStartup)
    refreshSlowReadsIfDue(now: now, startupMountPath: startupIndex.map { facts[$0].mountPath })

    // Finder's free space is available plus purgeable. Available is
    // read every tick; the purgeable share is the paced part.
    if let startupIndex, let purgeableBytes {
      let (sum, overflowed) = facts[startupIndex].availableBytes
        .addingReportingOverflow(purgeableBytes)
      facts[startupIndex].importantAvailableBytes = min(
        overflowed ? .max : sum, facts[startupIndex].totalBytes)
    }

    let counters = VolumeClassifier.counters(from: facts)
    var activity: [String: DiskActivity] = [:]
    for (disk, current) in counters {
      activity[disk] = DiskActivityDelta.activity(
        previous: previousDiskCounters[disk], current: current,
        wallTimeNanoseconds: wallTime)
    }
    previousDiskCounters = counters
    return (VolumeClassifier.snapshots(from: facts), activity)
  }

  /// Two reads are too slow or too invasive for every tick: purgeable
  /// space costs about 11 ms, and SMART opens a user client on the
  /// drive. Neither value moves quickly, so both refresh on the first
  /// tick and then once per slow interval.
  private func refreshSlowReadsIfDue(now: UInt64, startupMountPath: String?) {
    if let last = slowReadTimestamp, now >= last, now - last < slowReadIntervalNanoseconds {
      return
    }
    slowReadTimestamp = now
    purgeableBytes = startupMountPath.flatMap(VolumeSampler.purgeableBytes(forMountPath:))
    if let driveHealthReader {
      driveHealth = driveHealthReader()
      if driveHealth.count != lastDriveHealthCount {
        Self.hardwareLog.notice("drive health read \(self.driveHealth.count) NVMe device(s)")
        lastDriveHealthCount = driveHealth.count
      }
    }
  }
}
