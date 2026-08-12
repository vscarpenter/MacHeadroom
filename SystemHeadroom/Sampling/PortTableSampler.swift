import Darwin
import Foundation

/// Fetches the kernel's TCP and UDP connection tables. This is the same
/// interface netstat -anv reads, and the only port→pid path the App
/// Sandbox permits: the lsof-style fd walk is EPERM for every non-self
/// process (Evidence/ports-spike/). Parsing lives in PortTableParser.
enum PortTableSampler {
  static func fetchTCPTable() -> Data? { fetch("net.inet.tcp.pcblist_n") }
  static func fetchUDPTable() -> Data? { fetch("net.inet.udp.pcblist_n") }

  private static func fetch(_ name: String) -> Data? {
    for _ in 1...3 {
      var byteCount = 0
      guard sysctlbyname(name, nil, &byteCount, nil, 0) == 0, byteCount > 0 else {
        return nil
      }
      // The table can grow between the size query and the fetch; slack
      // plus retry-on-ENOMEM is the same idiom ProcessTableSampler uses.
      var buffer = Data(count: byteCount + byteCount / 4)
      var resultBytes = buffer.count
      let status = buffer.withUnsafeMutableBytes { raw in
        sysctlbyname(name, raw.baseAddress, &resultBytes, nil, 0)
      }
      if status == 0 {
        return buffer.prefix(resultBytes)
      }
      if errno != ENOMEM { return nil }
    }
    return nil
  }
}
