import Foundation

enum ProcessClass: String, CaseIterable, Codable, Hashable, Sendable {
  case ownApp = "own-app"
  case sameUser = "same-user"
  case systemRoot = "system-root"
  case otherUser = "other-user"
}

struct SysctlCallReport: Codable, Sendable {
  let attempt: Int
  let stage: String
  let returnValue: Int32
  let errorNumber: Int32
  let errorName: String
  let bufferBytes: Int
  let resultBytes: Int
}

struct FailureReport: Codable, Sendable {
  let processClass: ProcessClass
  let api: String
  let reason: String
  let count: Int
  let examplePID: Int32
  let exampleName: String
}

struct ClassSnapshotReport: Codable, Sendable {
  let processClass: ProcessClass
  let enumeratedPIDs: Int
  let nonemptyNames: Int
  let taskAttempts: Int
  let taskSuccesses: Int
  let taskFailures: Int
  let residentBytesNonzero: Int
  let rusageAttempts: Int
  let rusageSuccesses: Int
  let rusageFailures: Int
  let footprintBytesNonzero: Int
  let workspaceMatches: Int
}

struct WorkspaceReport: Codable, Sendable {
  let runningApplications: Int
  let matchedEnumeratedPIDs: Int
  let namesPresent: Int
  let bundleIdentifiersPresent: Int
  let iconsPresent: Int
  let executableURLsPresent: Int
}

struct SnapshotReport: Codable, Sendable {
  let label: String
  let monotonicNanoseconds: UInt64
  let measurementSequence: [String]
  let sysctlCalls: [SysctlCallReport]
  let identityRevalidationSysctlCalls: [SysctlCallReport]
  let processCount: Int
  let identityRevalidatedPIDs: Int
  let identityChangedOrExitedPIDs: Int
  let classes: [ClassSnapshotReport]
  let failures: [FailureReport]
  let workspace: WorkspaceReport
}

struct DeltaClassReport: Codable, Sendable {
  let processClass: ProcessClass
  let firstPopulation: Int
  let secondPopulation: Int
  let sharedPIDs: Int
  let enteredPIDs: Int
  let exitedPIDs: Int
  let classTransitions: Int
  let crossClassPIDReuse: Int
  let stablePairs: Int
  let positiveDeltas: Int
  let zeroDeltas: Int
  let taskUnavailablePairs: Int
  let counterRegressions: Int
  let invalidOrReusedPIDs: Int
}

struct CPUProof: Codable, Sendable {
  let processClass: ProcessClass
  let pid: Int32
  let processName: String
  let appName: String?
  let bundleIdentifier: String?
  let iconAvailable: Bool
  let stableIdentity: Bool
  let firstCPUTimeTicks: UInt64
  let secondCPUTimeTicks: UInt64
  let deltaCPUTimeTicks: UInt64
  let deltaCPUTimeNanoseconds: UInt64
  let deltaWallTimeNanoseconds: UInt64
  let perCorePercent: Double
  let machineCapacityPercent: Double
  let residentBytes: UInt64
  let physicalFootprintBytes: UInt64?
  let rusageProcessStartAbsoluteTime: UInt64?
  let rusageFailure: String?
}

struct FootprintProof: Codable, Sendable {
  let processClass: ProcessClass
  let pid: Int32
  let processName: String
  let appName: String?
  let bundleIdentifier: String?
  let iconAvailable: Bool
  let identityRevalidated: Bool
  let residentBytes: UInt64?
  let physicalFootprintBytes: UInt64
  let rusageProcessStartAbsoluteTime: UInt64
}

struct ProbeReport: Codable, Sendable {
  let reportVersion: Int
  let applicationName: String
  let processID: Int32
  let effectiveUserID: UInt32
  let operatingSystemVersion: String
  let architecture: String
  let buildConfiguration: String
  let logicalProcessorCount: Int
  let machTimebaseNumerator: UInt32
  let machTimebaseDenominator: UInt32
  let requestedIntervalNanoseconds: UInt64
  let actualIntervalNanoseconds: UInt64
  let snapshots: [SnapshotReport]
  let deltaClasses: [DeltaClassReport]
  let representativeProofs: [CPUProof]
  let representativeFootprintProofs: [FootprintProof]
  let sameUserApplicationCPUProof: CPUProof?
  let sameUserApplicationFootprintProof: FootprintProof?
  let sameUserApplicationCombinedMetricProof: CPUProof?
}
