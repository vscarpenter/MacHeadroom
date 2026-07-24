import Foundation

struct ProcessSnapshot: Sendable, Equatable {
  let pid: Int32
  let parentPID: Int32
  let userID: UInt32
  let name: String
  let startIdentity: String
  let cpuTimeTicks: UInt64
  let residentBytes: UInt64
}
