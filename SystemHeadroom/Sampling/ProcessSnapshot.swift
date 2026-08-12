import Foundation

struct ProcessTable: Sendable {
  let snapshots: [ProcessSnapshot]
  let commandNamesByPID: [Int32: String]
}

struct ProcessSnapshot: Sendable, Equatable {
  let pid: Int32
  let parentPID: Int32
  let userID: UInt32
  let name: String
  let startIdentity: String
  let cpuTimeTicks: UInt64
  let residentBytes: UInt64
}
