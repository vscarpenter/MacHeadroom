import Darwin
import Foundation

/// Reads the process table via public sysctl/libproc calls, scoped to
/// processes App Sandbox actually allows: this app plus other processes
/// owned by the same user. See SANDBOX_NOTES.md for why system, root, and
/// other-user processes never appear here.
enum ProcessTableSampler {
  static func sampleReachableProcesses(
    memoryMetric: ProcessMemoryMetric = .current
  ) -> [ProcessSnapshot] {
    sampleTable(memoryMetric: memoryMetric).snapshots
  }

  /// One enumeration pass serving both consumers: metric snapshots for
  /// same-user processes, and p_comm names for every pid — root and
  /// other-user rows expose their name in kinfo_proc even though their
  /// task info is EPERM, and the ports view needs names for the root
  /// listeners the pcblist sysctl reveals.
  static func sampleTable(
    memoryMetric: ProcessMemoryMetric = .current
  ) -> ProcessTable {
    let ownUID = geteuid()
    let identities = enumerateProcesses()
    let names = Dictionary(
      identities.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
    let snapshots = identities
      .filter { $0.userID == ownUID }
      .compactMap { identity -> ProcessSnapshot? in
        guard
          let task = taskMeasurement(
            for: identity.pid,
            memoryMetric: memoryMetric)
        else { return nil }
        return ProcessSnapshot(
          pid: identity.pid,
          parentPID: identity.parentPID,
          userID: identity.userID,
          name: identity.name,
          startIdentity: identity.startIdentity,
          cpuTimeTicks: task.cpuTimeTicks,
          memoryBytes: task.memoryBytes
        )
      }
    return ProcessTable(snapshots: snapshots, commandNamesByPID: names)
  }

  /// Re-reads one pid's start-time identity immediately before a signal
  /// is sent. Rows can be a full sampling interval stale; a reused pid
  /// must never be signaled. Nil means the pid is gone or unreadable.
  static func startIdentity(of pid: Int32) -> String? {
    var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    let result = mib.withUnsafeMutableBufferPointer { pointer in
      sysctl(pointer.baseAddress, UInt32(pointer.count), &info, &size, nil, 0)
    }
    guard result == 0, size == MemoryLayout<kinfo_proc>.size,
      info.kp_proc.p_pid == pid
    else { return nil }
    return ProcessIdentity(info).startIdentity
  }

  private static func enumerateProcesses() -> [ProcessIdentity] {
    let mibTemplate = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    let stride = MemoryLayout<kinfo_proc>.stride

    for _ in 1...3 {
      var mib = mibTemplate
      var byteCount = 0
      errno = 0
      let sizeReturn = mib.withUnsafeMutableBufferPointer { pointer in
        sysctl(pointer.baseAddress, UInt32(pointer.count), nil, &byteCount, nil, 0)
      }
      guard sizeReturn == 0, byteCount > 0 else { return [] }

      let capacity = max((byteCount / stride) + 32, 1)
      var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
      var resultBytes = buffer.count * stride
      errno = 0
      let dataReturn = mib.withUnsafeMutableBufferPointer { mibPointer in
        buffer.withUnsafeMutableBytes { bufferPointer in
          sysctl(mibPointer.baseAddress, UInt32(mibPointer.count), bufferPointer.baseAddress, &resultBytes, nil, 0)
        }
      }

      if dataReturn == 0 {
        let resultCount = min(resultBytes / stride, buffer.count)
        return buffer.prefix(resultCount).map(ProcessIdentity.init)
      }
      if errno != ENOMEM { return [] }
    }
    return []
  }

  private static func taskMeasurement(
    for pid: Int32,
    memoryMetric: ProcessMemoryMetric
  ) -> (cpuTimeTicks: UInt64, memoryBytes: UInt64)? {
    var taskInfo = proc_taskinfo()
    let expectedBytes = Int32(MemoryLayout<proc_taskinfo>.size)
    let returnedBytes = withUnsafeMutablePointer(to: &taskInfo) { pointer in
      proc_pidinfo(pid, PROC_PIDTASKINFO, 0, UnsafeMutableRawPointer(pointer), expectedBytes)
    }
    guard returnedBytes == expectedBytes else { return nil }
    let footprint =
      memoryMetric == .physicalFootprint
      ? physicalFootprintBytes(for: pid)
      : nil
    guard
      let memoryBytes = memoryMetric.value(
        residentBytes: taskInfo.pti_resident_size,
        physicalFootprintBytes: footprint)
    else { return nil }
    return (taskInfo.pti_total_user + taskInfo.pti_total_system, memoryBytes)
  }

  /// `proc_pid_rusage` is available on every supported macOS version. It is
  /// permitted for same-user processes only outside App Sandbox; callers gate
  /// the sweep by ProcessMemoryMetric so the App Store build never makes a
  /// guaranteed-to-fail call per process.
  static func physicalFootprintBytes(for pid: Int32) -> UInt64? {
    var usage = rusage_info_v2()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
      }
    }
    guard result == 0, usage.ri_phys_footprint > 0 else { return nil }
    return usage.ri_phys_footprint
  }
}

private struct ProcessIdentity: Sendable {
  let pid: Int32
  let parentPID: Int32
  let userID: UInt32
  let name: String
  let startIdentity: String

  init(_ process: kinfo_proc) {
    pid = process.kp_proc.p_pid
    parentPID = process.kp_eproc.e_ppid
    userID = process.kp_eproc.e_ucred.cr_uid
    name = Self.commandName(process.kp_proc.p_comm)
    startIdentity =
      "\(process.kp_proc.p_starttime.tv_sec):\(process.kp_proc.p_starttime.tv_usec)"
  }

  private static func commandName<T>(_ command: T) -> String {
    withUnsafeBytes(of: command) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}
