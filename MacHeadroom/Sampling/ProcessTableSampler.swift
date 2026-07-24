import Darwin
import Foundation

/// Reads the process table via public sysctl/libproc calls, scoped to
/// processes App Sandbox actually allows: this app plus other processes
/// owned by the same user. See SANDBOX_NOTES.md for why system, root, and
/// other-user processes never appear here.
enum ProcessTableSampler {
  static func sampleReachableProcesses() -> [ProcessSnapshot] {
    let ownUID = geteuid()
    return enumerateProcesses()
      .filter { $0.userID == ownUID }
      .compactMap { identity in
        guard let task = taskMeasurement(for: identity.pid) else { return nil }
        return ProcessSnapshot(
          pid: identity.pid,
          parentPID: identity.parentPID,
          userID: identity.userID,
          name: identity.name,
          startIdentity: identity.startIdentity,
          cpuTimeTicks: task.cpuTimeTicks,
          residentBytes: task.residentBytes
        )
      }
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
    for pid: Int32
  ) -> (cpuTimeTicks: UInt64, residentBytes: UInt64)? {
    var taskInfo = proc_taskinfo()
    let expectedBytes = Int32(MemoryLayout<proc_taskinfo>.size)
    let returnedBytes = withUnsafeMutablePointer(to: &taskInfo) { pointer in
      proc_pidinfo(pid, PROC_PIDTASKINFO, 0, UnsafeMutableRawPointer(pointer), expectedBytes)
    }
    guard returnedBytes == expectedBytes else { return nil }
    return (taskInfo.pti_total_user + taskInfo.pti_total_system, taskInfo.pti_resident_size)
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
