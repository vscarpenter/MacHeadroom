import Foundation

/// Per-process memory has two deliberately distinct meanings. Activity
/// Monitor uses physical footprint. The App Sandbox denies that value for
/// other processes, so the App Store build must use resident size (RSS) and
/// label it. The unsandboxed Direct build can use physical footprint.
enum ProcessMemoryMetric: Sendable, Equatable {
  case physicalFootprint
  case residentSize

  static var current: ProcessMemoryMetric {
    forSandboxedBuild(AppSandboxStatus.current == .enabled)
  }

  static func forSandboxedBuild(_ isSandboxed: Bool) -> ProcessMemoryMetric {
    isSandboxed ? .residentSize : .physicalFootprint
  }

  func value(
    residentBytes: UInt64,
    physicalFootprintBytes: UInt64?
  ) -> UInt64? {
    switch self {
    case .physicalFootprint:
      physicalFootprintBytes
    case .residentSize:
      residentBytes
    }
  }

  var accessibilityName: String {
    switch self {
    case .physicalFootprint: "physical footprint memory"
    case .residentSize: "resident memory"
    }
  }

  var helpText: String {
    switch self {
    case .physicalFootprint:
      "App values use physical footprint, the same memory accounting shown by Activity Monitor."
    case .residentSize:
      "App values use resident size (RSS) because the App Store sandbox blocks physical-footprint access. RSS can differ substantially from Activity Monitor, especially for GPU-backed apps."
    }
  }
}

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
  /// Bytes in the ProcessMemoryMetric selected for this build.
  let memoryBytes: UInt64
}
