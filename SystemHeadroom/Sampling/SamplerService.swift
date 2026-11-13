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
  private var hardwareBaseline: HardwareBaseline?
  private var lastGPUPercents: [Int32: Double]?
  private var lastDiskActivity: [String: DiskActivity] = [:]
  private var slowReadTimestamp: UInt64?
  private var purgeableBytes: UInt64?
  private var driveHealth: [DriveHealth] = []
  private let timebase: mach_timebase_info_data_t
  private let logicalCoreCount: Int
  private let processMemoryMetric: ProcessMemoryMetric
  private let driveHealthReader: (@Sendable () -> [DriveHealth])?
  private let slowReadIntervalNanoseconds: UInt64
  private let minimumHardwareWindowNanoseconds: UInt64

  /// What the GPU and disk deltas measure from. It is kept apart from
  /// the CPU baseline because its window has two limits the CPU delta
  /// does not enforce. A tick too soon after it must not shrink the
  /// window: one WindowServer frame fills 3 ms. A tick after a pause
  /// must not stretch it across the pause.
  private struct HardwareBaseline {
    let timestamp: UInt64
    let gpuTimeByPID: [Int32: UInt64]?
    /// Start identities when the baseline was taken, for the pid-reuse
    /// guard. Carrying them here means the guard never depends on when
    /// the previous process snapshots are replaced.
    let identitiesByPID: [Int32: String]
    let diskCounters: [String: DiskCounters]
  }

  private static let log = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "ports")
  private static let hardwareLog = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "hardware")

  init(
    timebase: mach_timebase_info_data_t = SamplerService.currentTimebase(),
    logicalCoreCount: Int = max(ProcessInfo.processInfo.activeProcessorCount, 1),
    processMemoryMetric: ProcessMemoryMetric = .current,
    driveHealthReader: (@Sendable () -> [DriveHealth])? = SamplerService.liveDriveHealthReader(),
    slowReadIntervalNanoseconds: UInt64 = 60 * 1_000_000_000,
    minimumHardwareWindowNanoseconds: UInt64 = 250_000_000
  ) {
    self.timebase = timebase
    self.logicalCoreCount = logicalCoreCount
    self.processMemoryMetric = processMemoryMetric
    self.driveHealthReader = driveHealthReader
    self.slowReadIntervalNanoseconds = slowReadIntervalNanoseconds
    self.minimumHardwareWindowNanoseconds = minimumHardwareWindowNanoseconds
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
  ///
  /// `resumingAfterPause` is a fact about the caller's schedule, not a
  /// time: the store sets it on the first tick after sampling restarts.
  /// The GPU and disk deltas then prime again rather than average over
  /// however long the popover was closed.
  func tick(convention: CPUConvention, resumingAfterPause: Bool = false) -> MonitorTick {
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
    if resumingAfterPause {
      hardwareBaseline = nil
      lastGPUPercents = nil
      lastDiskActivity = [:]
    }
    let hardware = sampleHardware(now: now, snapshotsByPID: snapshotsByPID)

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
      gpu: hardware.gpu,
      volumes: hardware.volumes,
      diskActivity: hardware.activity,
      driveHealth: driveHealth
    )
  }

  private func sampleHardware(
    now: UInt64, snapshotsByPID: [Int32: ProcessSnapshot]
  ) -> (gpu: GPUSample?, volumes: [VolumeSnapshot], activity: [String: DiskActivity]) {
    let reading = readGPU()
    let drives = readDrives(now: now)

    var percents: [Int32: Double]?
    var activity: [String: DiskActivity] = [:]
    let window = hardwareBaseline.map { now > $0.timestamp ? now - $0.timestamp : 0 }
    if let window, window < minimumHardwareWindowNanoseconds {
      // Too soon to measure. Repeat the last figures and leave the
      // baseline where it is, so the window keeps growing.
      percents = lastGPUPercents
      activity = lastDiskActivity
    } else {
      if let baseline = hardwareBaseline, let window {
        if let reading, reading.reportsClientUsage, let previous = baseline.gpuTimeByPID {
          percents = GPUDelta.percents(
            previous: previous,
            current: reading.gpuTimeNanosecondsByPID,
            wallTimeNanoseconds: window,
            identityChanged: { pid in
              guard let before = baseline.identitiesByPID[pid],
                let current = snapshotsByPID[pid]?.startIdentity
              else { return false }
              return before != current
            })
        }
        for (disk, current) in drives.counters {
          activity[disk] = DiskActivityDelta.activity(
            previous: baseline.diskCounters[disk], current: current,
            wallTimeNanoseconds: window)
        }
      }
      lastGPUPercents = percents
      lastDiskActivity = activity
      var identities: [Int32: String] = [:]
      for pid in (reading?.gpuTimeNanosecondsByPID ?? [:]).keys {
        identities[pid] = snapshotsByPID[pid]?.startIdentity
      }
      hardwareBaseline = HardwareBaseline(
        timestamp: now,
        gpuTimeByPID: reading?.gpuTimeNanosecondsByPID,
        identitiesByPID: identities,
        diskCounters: drives.counters)
    }

    let gpu = reading.map { reading in
      GPUSample(
        model: reading.model,
        coreCount: reading.coreCount,
        utilizationPercent: reading.deviceUtilizationPercent,
        rendererPercent: reading.rendererUtilizationPercent,
        tilerPercent: reading.tilerUtilizationPercent,
        allocatedMemoryBytes: reading.allocatedMemoryBytes,
        inUseMemoryBytes: reading.inUseMemoryBytes,
        reportsProcessUsage: reading.reportsClientUsage,
        processPercents: reading.reportsClientUsage ? percents : nil,
        processNames: reading.clientNamesByPID)
    }
    return (gpu, drives.volumes, activity)
  }

  private func readGPU() -> GPUReading? {
    let reading = GPUSampler.sample()
    // Logged on the transition only, like the ports failure: an Intel
    // Mac or a virtual machine would otherwise log every tick.
    if reading == nil, !lastGPUMissing {
      Self.hardwareLog.notice("no accelerator reports utilization; GPU tab unavailable")
    }
    lastGPUMissing = reading == nil
    return reading
  }

  private func readDrives(
    now: UInt64
  ) -> (volumes: [VolumeSnapshot], counters: [String: DiskCounters]) {
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
    return (VolumeClassifier.snapshots(from: facts), VolumeClassifier.counters(from: facts))
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
