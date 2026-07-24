import AppKit
import Darwin
import Foundation

@MainActor
enum SandboxProbe {
  private static let intervalNanoseconds: UInt64 = 2_000_000_000

  static func run() async -> ProbeReport {
    let first = takeSnapshot(label: "T0")

    try? await Task.sleep(nanoseconds: intervalNanoseconds)

    let second = takeSnapshot(label: "T1")
    let deltaWallTime = second.monotonicNanoseconds - first.monotonicNanoseconds
    let timebase = machTimebase
    let deltaResult = makeDeltaReports(
      first: first,
      second: second,
      deltaWallTime: deltaWallTime,
      timebase: timebase
    )

    return ProbeReport(
      reportVersion: 2,
      applicationName: AppIdentity.displayName,
      processID: getpid(),
      effectiveUserID: geteuid(),
      operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: architecture,
      buildConfiguration: buildConfiguration,
      logicalProcessorCount: max(ProcessInfo.processInfo.activeProcessorCount, 1),
      machTimebaseNumerator: timebase.numer,
      machTimebaseDenominator: timebase.denom,
      requestedIntervalNanoseconds: intervalNanoseconds,
      actualIntervalNanoseconds: deltaWallTime,
      snapshots: [first.report, second.report],
      deltaClasses: deltaResult.classes,
      representativeProofs: deltaResult.proofs,
      representativeFootprintProofs: deltaResult.footprintProofs,
      sameUserApplicationCPUProof: deltaResult.sameUserApplicationCPUProof,
      sameUserApplicationFootprintProof:
        deltaResult.sameUserApplicationFootprintProof,
      sameUserApplicationCombinedMetricProof:
        deltaResult.sameUserApplicationCombinedMetricProof
    )
  }

  private static func takeSnapshot(label: String) -> SnapshotData {
    let monotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
    let enumeration = enumerateProcesses()

    let taskMeasurements = Dictionary(
      uniqueKeysWithValues: enumeration.processes.map { process in
        (process.pid, taskMeasurement(for: process.pid))
      }
    )
    let rusageMeasurements = Dictionary(
      uniqueKeysWithValues: enumeration.processes.map { process in
        (process.pid, rusageMeasurement(for: process.pid))
      }
    )
    let workspace = workspaceMetadata()
    let revalidation = enumerateProcesses()
    let revalidatedIdentities = Dictionary(
      uniqueKeysWithValues: revalidation.processes.map { ($0.pid, $0) }
    )

    let observations = enumeration.processes.map { process in
      let revalidatedIdentity = revalidatedIdentities[process.pid]
      return ProcessObservation(
        identity: process,
        processClass: classify(process),
        task: taskMeasurements[process.pid]!,
        rusage: rusageMeasurements[process.pid]!,
        workspace: workspace.byPID[process.pid],
        identityRevalidated:
          revalidatedIdentity?.startIdentity == process.startIdentity
          && revalidatedIdentity?.userID == process.userID
      )
    }

    let classReports = ProcessClass.allCases.map { processClass in
      makeClassReport(
        processClass: processClass,
        observations: observations
      )
    }

    return SnapshotData(
      monotonicNanoseconds: monotonicNanoseconds,
      report: SnapshotReport(
        label: label,
        monotonicNanoseconds: monotonicNanoseconds,
        measurementSequence: [
          "sysctl(KERN_PROC_ALL) enumeration",
          "proc_pidinfo(PROC_PIDTASKINFO) sweep",
          "proc_pid_rusage(RUSAGE_INFO_V4) sweep",
          "NSWorkspace.runningApplications",
          "sysctl(KERN_PROC_ALL) identity revalidation",
        ],
        sysctlCalls: enumeration.calls,
        identityRevalidationSysctlCalls: revalidation.calls,
        processCount: observations.count,
        identityRevalidatedPIDs: observations.count(where: \.identityRevalidated),
        identityChangedOrExitedPIDs: observations.count {
          !$0.identityRevalidated
        },
        classes: classReports,
        failures: makeFailureReports(observations: observations),
        workspace: makeWorkspaceReport(
          observations: observations,
          workspace: workspace
        )
      ),
      observationsByPID: Dictionary(
        uniqueKeysWithValues: observations.map { ($0.identity.pid, $0) }
      )
    )
  }

  private static func enumerateProcesses() -> EnumerationResult {
    var calls: [SysctlCallReport] = []
    let mibTemplate = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    let stride = MemoryLayout<kinfo_proc>.stride

    for attempt in 1...3 {
      var mib = mibTemplate
      var byteCount = 0
      errno = 0
      let sizeReturn = mib.withUnsafeMutableBufferPointer { pointer in
        sysctl(
          pointer.baseAddress,
          UInt32(pointer.count),
          nil,
          &byteCount,
          nil,
          0
        )
      }
      let sizeError = errno
      calls.append(
        SysctlCallReport(
          attempt: attempt,
          stage: "size-query",
          returnValue: sizeReturn,
          errorNumber: sizeError,
          errorName: errorName(sizeError),
          bufferBytes: 0,
          resultBytes: byteCount
        )
      )

      guard sizeReturn == 0, byteCount > 0 else {
        return EnumerationResult(calls: calls, processes: [])
      }

      let capacity = max((byteCount / stride) + 32, 1)
      var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
      var resultBytes = buffer.count * stride
      errno = 0
      let dataReturn = mib.withUnsafeMutableBufferPointer { mibPointer in
        buffer.withUnsafeMutableBytes { bufferPointer in
          sysctl(
            mibPointer.baseAddress,
            UInt32(mibPointer.count),
            bufferPointer.baseAddress,
            &resultBytes,
            nil,
            0
          )
        }
      }
      let dataError = errno
      calls.append(
        SysctlCallReport(
          attempt: attempt,
          stage: "data-fetch",
          returnValue: dataReturn,
          errorNumber: dataError,
          errorName: errorName(dataError),
          bufferBytes: buffer.count * stride,
          resultBytes: resultBytes
        )
      )

      if dataReturn == 0 {
        let resultCount = min(resultBytes / stride, buffer.count)
        let processes = buffer.prefix(resultCount).map(ProcessIdentity.init)
        return EnumerationResult(calls: calls, processes: processes)
      }

      if dataError != ENOMEM {
        return EnumerationResult(calls: calls, processes: [])
      }
    }

    return EnumerationResult(calls: calls, processes: [])
  }

  private static func taskMeasurement(for pid: Int32) -> CallResult<TaskMeasurement> {
    var taskInfo = proc_taskinfo()
    let expectedBytes = Int32(MemoryLayout<proc_taskinfo>.size)
    errno = 0
    let returnedBytes = withUnsafeMutablePointer(to: &taskInfo) { pointer in
      proc_pidinfo(
        pid,
        PROC_PIDTASKINFO,
        0,
        UnsafeMutableRawPointer(pointer),
        expectedBytes
      )
    }
    let capturedError = errno

    guard returnedBytes == expectedBytes else {
      let reason: String
      if returnedBytes == 0 {
        reason = "return=0 errno=\(capturedError) \(errorName(capturedError))"
      } else {
        reason = "short-read=\(returnedBytes) expected=\(expectedBytes)"
      }
      return .failure(reason)
    }

    return .success(
      TaskMeasurement(
        cpuTimeTicks: taskInfo.pti_total_user + taskInfo.pti_total_system,
        residentBytes: taskInfo.pti_resident_size
      )
    )
  }

  private static func rusageMeasurement(for pid: Int32) -> CallResult<RusageMeasurement> {
    var usage = rusage_info_v4()
    let reboundCapacity =
      MemoryLayout<rusage_info_v4>.stride
      / MemoryLayout<rusage_info_t?>.stride
    errno = 0
    let returnValue = withUnsafeMutablePointer(to: &usage) { usagePointer in
      usagePointer.withMemoryRebound(
        to: rusage_info_t?.self,
        capacity: reboundCapacity
      ) { importedBufferPointer in
        proc_pid_rusage(pid, RUSAGE_INFO_V4, importedBufferPointer)
      }
    }
    let capturedError = errno

    guard returnValue == 0 else {
      return .failure(
        "return=\(returnValue) errno=\(capturedError) \(errorName(capturedError))"
      )
    }

    return .success(
      RusageMeasurement(
        physicalFootprintBytes: usage.ri_phys_footprint,
        processStartAbsoluteTime: usage.ri_proc_start_abstime
      )
    )
  }

  private static func workspaceMetadata() -> WorkspaceSnapshot {
    let applications = NSWorkspace.shared.runningApplications
    let metadata = applications.map { application in
      WorkspaceMetadata(
        pid: application.processIdentifier,
        name: application.localizedName,
        bundleIdentifier: application.bundleIdentifier,
        iconAvailable: application.icon != nil,
        executableURLAvailable: application.executableURL != nil
      )
    }

    return WorkspaceSnapshot(
      applications: metadata,
      byPID: Dictionary(uniqueKeysWithValues: metadata.map { ($0.pid, $0) })
    )
  }

  private static func makeClassReport(
    processClass: ProcessClass,
    observations: [ProcessObservation]
  ) -> ClassSnapshotReport {
    let matching = observations.filter { $0.processClass == processClass }
    let taskSuccesses = matching.compactMap(\.task.value)
    let rusageSuccesses = matching.compactMap(\.rusage.value)

    return ClassSnapshotReport(
      processClass: processClass,
      enumeratedPIDs: matching.count,
      nonemptyNames: matching.count { !$0.identity.name.isEmpty },
      taskAttempts: matching.count,
      taskSuccesses: taskSuccesses.count,
      taskFailures: matching.count - taskSuccesses.count,
      residentBytesNonzero: taskSuccesses.count { $0.residentBytes > 0 },
      rusageAttempts: matching.count,
      rusageSuccesses: rusageSuccesses.count,
      rusageFailures: matching.count - rusageSuccesses.count,
      footprintBytesNonzero: rusageSuccesses.count {
        $0.physicalFootprintBytes > 0
      },
      workspaceMatches: matching.count { $0.workspace != nil }
    )
  }

  private static func makeFailureReports(
    observations: [ProcessObservation]
  ) -> [FailureReport] {
    var tallies: [FailureKey: FailureTally] = [:]

    for observation in observations {
      if let reason = observation.task.failure {
        let key = FailureKey(
          processClass: observation.processClass,
          api: "proc_pidinfo(PROC_PIDTASKINFO)",
          reason: reason
        )
        tallies[key, default: FailureTally(observation: observation)].count += 1
      }

      if let reason = observation.rusage.failure {
        let key = FailureKey(
          processClass: observation.processClass,
          api: "proc_pid_rusage(RUSAGE_INFO_V4)",
          reason: reason
        )
        tallies[key, default: FailureTally(observation: observation)].count += 1
      }
    }

    return tallies.map { key, tally in
      FailureReport(
        processClass: key.processClass,
        api: key.api,
        reason: key.reason,
        count: tally.count,
        examplePID: tally.examplePID,
        exampleName: tally.exampleName
      )
    }
    .sorted {
      ($0.processClass.rawValue, $0.api, $0.reason)
        < ($1.processClass.rawValue, $1.api, $1.reason)
    }
  }

  private static func makeWorkspaceReport(
    observations: [ProcessObservation],
    workspace: WorkspaceSnapshot
  ) -> WorkspaceReport {
    let matches = observations.compactMap(\.workspace)
    let applications = workspace.applications
    return WorkspaceReport(
      runningApplications: applications.count,
      matchedEnumeratedPIDs: matches.count,
      namesPresent: applications.count { $0.name != nil },
      bundleIdentifiersPresent: applications.count {
        $0.bundleIdentifier != nil
      },
      iconsPresent: applications.count(where: \.iconAvailable),
      executableURLsPresent: applications.count(
        where: \.executableURLAvailable
      )
    )
  }

  private static func makeDeltaReports(
    first: SnapshotData,
    second: SnapshotData,
    deltaWallTime: UInt64,
    timebase: mach_timebase_info_data_t
  ) -> DeltaResult {
    let logicalProcessors = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    var classes: [DeltaClassReport] = []
    var proofs: [CPUProof] = []
    var allCandidates: [CPUProof] = []
    var footprintProofs: [FootprintProof] = []
    var allFootprintCandidates: [FootprintProof] = []

    for processClass in ProcessClass.allCases {
      let firstPIDs = Set(
        first.observationsByPID.values
          .filter { $0.processClass == processClass }
          .map(\.identity.pid)
      )
      let secondPIDs = Set(
        second.observationsByPID.values
          .filter { $0.processClass == processClass }
          .map(\.identity.pid)
      )
      let sharedPIDs = firstPIDs.intersection(secondPIDs)
      let enteredPIDs = secondPIDs.subtracting(firstPIDs)
      let exitedPIDs = firstPIDs.subtracting(secondPIDs)
      let globallySharedPIDs = Set(first.observationsByPID.keys)
        .intersection(second.observationsByPID.keys)
      let classTransitions = globallySharedPIDs.count { pid in
        guard
          let firstObservation = first.observationsByPID[pid],
          let secondObservation = second.observationsByPID[pid],
          firstObservation.processClass != secondObservation.processClass,
          firstObservation.identity.startIdentity
            == secondObservation.identity.startIdentity
        else {
          return false
        }
        return firstObservation.processClass == processClass
          || secondObservation.processClass == processClass
      }
      let crossClassPIDReuse = globallySharedPIDs.count { pid in
        guard
          let firstObservation = first.observationsByPID[pid],
          let secondObservation = second.observationsByPID[pid],
          firstObservation.processClass != secondObservation.processClass,
          firstObservation.identity.startIdentity
            != secondObservation.identity.startIdentity
        else {
          return false
        }
        return firstObservation.processClass == processClass
          || secondObservation.processClass == processClass
      }

      var stablePairs = 0
      var positiveDeltas = 0
      var zeroDeltas = 0
      var taskUnavailablePairs = 0
      var counterRegressions = 0
      var invalidOrReusedPIDs = 0
      var candidates: [CPUProof] = []

      for pid in sharedPIDs {
        guard
          let firstObservation = first.observationsByPID[pid],
          let secondObservation = second.observationsByPID[pid],
          firstObservation.identityRevalidated,
          secondObservation.identityRevalidated,
          firstObservation.identity.startIdentity
            == secondObservation.identity.startIdentity,
          firstObservation.identity.userID == secondObservation.identity.userID
        else {
          invalidOrReusedPIDs += 1
          continue
        }

        guard
          let firstTask = firstObservation.task.value,
          let secondTask = secondObservation.task.value
        else {
          taskUnavailablePairs += 1
          continue
        }

        guard secondTask.cpuTimeTicks >= firstTask.cpuTimeTicks else {
          counterRegressions += 1
          continue
        }

        stablePairs += 1
        let deltaTicks = secondTask.cpuTimeTicks - firstTask.cpuTimeTicks
        let deltaNanoseconds = nanoseconds(
          fromMachTicks: deltaTicks,
          timebase: timebase
        )
        if deltaTicks > 0 {
          positiveDeltas += 1
        } else {
          zeroDeltas += 1
        }

        let perCorePercent =
          deltaWallTime == 0
          ? 0
          : (Double(deltaNanoseconds) / Double(deltaWallTime)) * 100
        let workspace = secondObservation.workspace ?? firstObservation.workspace
        let proof = CPUProof(
          processClass: processClass,
          pid: pid,
          processName: secondObservation.identity.name,
          appName: workspace?.name,
          bundleIdentifier: workspace?.bundleIdentifier,
          iconAvailable: workspace?.iconAvailable ?? false,
          stableIdentity: true,
          firstCPUTimeTicks: firstTask.cpuTimeTicks,
          secondCPUTimeTicks: secondTask.cpuTimeTicks,
          deltaCPUTimeTicks: deltaTicks,
          deltaCPUTimeNanoseconds: deltaNanoseconds,
          deltaWallTimeNanoseconds: deltaWallTime,
          perCorePercent: perCorePercent,
          machineCapacityPercent: perCorePercent / logicalProcessors,
          residentBytes: secondTask.residentBytes,
          physicalFootprintBytes:
            secondObservation.rusage.value?.physicalFootprintBytes,
          rusageProcessStartAbsoluteTime:
            secondObservation.rusage.value?.processStartAbsoluteTime,
          rusageFailure: secondObservation.rusage.failure
        )
        candidates.append(proof)
        allCandidates.append(proof)
      }

      classes.append(
        DeltaClassReport(
          processClass: processClass,
          firstPopulation: firstPIDs.count,
          secondPopulation: secondPIDs.count,
          sharedPIDs: sharedPIDs.count,
          enteredPIDs: enteredPIDs.count,
          exitedPIDs: exitedPIDs.count,
          classTransitions: classTransitions,
          crossClassPIDReuse: crossClassPIDReuse,
          stablePairs: stablePairs,
          positiveDeltas: positiveDeltas,
          zeroDeltas: zeroDeltas,
          taskUnavailablePairs: taskUnavailablePairs,
          counterRegressions: counterRegressions,
          invalidOrReusedPIDs: invalidOrReusedPIDs
        )
      )

      if let representative = candidates.max(by: proofIsLessUseful) {
        proofs.append(representative)
      }

      let classFootprints = second.observationsByPID.values.compactMap {
        observation -> FootprintProof? in
        guard
          observation.processClass == processClass,
          observation.identityRevalidated,
          let rusage = observation.rusage.value,
          rusage.physicalFootprintBytes > 0
        else {
          return nil
        }
        let workspace = observation.workspace
        return FootprintProof(
          processClass: processClass,
          pid: observation.identity.pid,
          processName: observation.identity.name,
          appName: workspace?.name,
          bundleIdentifier: workspace?.bundleIdentifier,
          iconAvailable: workspace?.iconAvailable ?? false,
          identityRevalidated: true,
          residentBytes: observation.task.value?.residentBytes,
          physicalFootprintBytes: rusage.physicalFootprintBytes,
          rusageProcessStartAbsoluteTime: rusage.processStartAbsoluteTime
        )
      }
      allFootprintCandidates.append(contentsOf: classFootprints)
      if let representative = classFootprints.max(by: footprintProofIsLessUseful) {
        footprintProofs.append(representative)
      }
    }

    let sameUserApplicationCPUProof =
      allCandidates
      .filter {
        $0.processClass == .sameUser
          && $0.bundleIdentifier != nil
          && $0.deltaCPUTimeNanoseconds > 0
      }
      .max(by: proofIsLessUseful)
    let sameUserApplicationFootprintProof =
      allFootprintCandidates
      .filter {
        $0.processClass == .sameUser
          && $0.bundleIdentifier != nil
      }
      .max(by: footprintProofIsLessUseful)
    let sameUserApplicationCombinedMetricProof =
      allCandidates
      .filter {
        $0.processClass == .sameUser
          && $0.bundleIdentifier != nil
          && $0.deltaCPUTimeNanoseconds > 0
          && ($0.physicalFootprintBytes ?? 0) > 0
      }
      .max(by: proofIsLessUseful)

    return DeltaResult(
      classes: classes,
      proofs: proofs,
      footprintProofs: footprintProofs,
      sameUserApplicationCPUProof: sameUserApplicationCPUProof,
      sameUserApplicationFootprintProof: sameUserApplicationFootprintProof,
      sameUserApplicationCombinedMetricProof:
        sameUserApplicationCombinedMetricProof
    )
  }

  private static func proofIsLessUseful(_ lhs: CPUProof, _ rhs: CPUProof) -> Bool {
    let lhsUseful =
      lhs.deltaCPUTimeNanoseconds > 0 && (lhs.physicalFootprintBytes ?? 0) > 0
    let rhsUseful =
      rhs.deltaCPUTimeNanoseconds > 0 && (rhs.physicalFootprintBytes ?? 0) > 0
    if lhsUseful != rhsUseful {
      return !lhsUseful
    }
    return lhs.deltaCPUTimeNanoseconds < rhs.deltaCPUTimeNanoseconds
  }

  private static func footprintProofIsLessUseful(
    _ lhs: FootprintProof,
    _ rhs: FootprintProof
  ) -> Bool {
    lhs.physicalFootprintBytes < rhs.physicalFootprintBytes
  }

  private static func nanoseconds(
    fromMachTicks ticks: UInt64,
    timebase: mach_timebase_info_data_t
  ) -> UInt64 {
    let numerator = UInt64(timebase.numer)
    let denominator = UInt64(max(timebase.denom, 1))
    let quotient = ticks / denominator
    let remainder = ticks % denominator
    return quotient * numerator + (remainder * numerator) / denominator
  }

  private static func classify(_ process: ProcessIdentity) -> ProcessClass {
    if process.pid == getpid() {
      return .ownApp
    }
    if process.userID == 0 {
      return .systemRoot
    }
    if process.userID == geteuid() {
      return .sameUser
    }
    return .otherUser
  }

  private static func errorName(_ errorNumber: Int32) -> String {
    guard errorNumber != 0, let message = strerror(errorNumber) else {
      return "none"
    }
    return String(cString: message)
  }

  private static var architecture: String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #else
      "unknown"
    #endif
  }

  private static var buildConfiguration: String {
    #if DEBUG
      "Debug"
    #else
      "Release"
    #endif
  }

  private static var machTimebase: mach_timebase_info_data_t {
    var timebase = mach_timebase_info_data_t()
    _ = mach_timebase_info(&timebase)
    return timebase
  }
}

private struct ProcessIdentity: Sendable {
  let pid: Int32
  let userID: UInt32
  let name: String
  let startIdentity: String

  init(_ process: kinfo_proc) {
    pid = process.kp_proc.p_pid
    userID = process.kp_eproc.e_ucred.cr_uid
    name = Self.commandName(process.kp_proc.p_comm)
    startIdentity =
      "\(process.kp_proc.p_starttime.tv_sec):\(process.kp_proc.p_starttime.tv_usec)"
  }

  private static func commandName<T>(_ command: T) -> String {
    withUnsafeBytes(of: command) { bytes in
      let content = bytes.prefix { $0 != 0 }
      return String(decoding: content, as: UTF8.self)
    }
  }
}

private struct TaskMeasurement: Sendable {
  let cpuTimeTicks: UInt64
  let residentBytes: UInt64
}

private struct RusageMeasurement: Sendable {
  let physicalFootprintBytes: UInt64
  let processStartAbsoluteTime: UInt64
}

private enum CallResult<Value: Sendable>: Sendable {
  case success(Value)
  case failure(String)

  var value: Value? {
    guard case .success(let value) = self else {
      return nil
    }
    return value
  }

  var failure: String? {
    guard case .failure(let reason) = self else {
      return nil
    }
    return reason
  }
}

private struct WorkspaceMetadata: Sendable {
  let pid: Int32
  let name: String?
  let bundleIdentifier: String?
  let iconAvailable: Bool
  let executableURLAvailable: Bool
}

private struct WorkspaceSnapshot: Sendable {
  let applications: [WorkspaceMetadata]
  let byPID: [Int32: WorkspaceMetadata]
}

private struct ProcessObservation: Sendable {
  let identity: ProcessIdentity
  let processClass: ProcessClass
  let task: CallResult<TaskMeasurement>
  let rusage: CallResult<RusageMeasurement>
  let workspace: WorkspaceMetadata?
  let identityRevalidated: Bool
}

private struct EnumerationResult {
  let calls: [SysctlCallReport]
  let processes: [ProcessIdentity]
}

private struct SnapshotData {
  let monotonicNanoseconds: UInt64
  let report: SnapshotReport
  let observationsByPID: [Int32: ProcessObservation]
}

private struct FailureKey: Hashable {
  let processClass: ProcessClass
  let api: String
  let reason: String
}

private struct FailureTally {
  var count = 0
  let examplePID: Int32
  let exampleName: String

  init(observation: ProcessObservation) {
    examplePID = observation.identity.pid
    exampleName = observation.identity.name
  }
}

private struct DeltaResult {
  let classes: [DeltaClassReport]
  let proofs: [CPUProof]
  let footprintProofs: [FootprintProof]
  let sameUserApplicationCPUProof: CPUProof?
  let sameUserApplicationFootprintProof: FootprintProof?
  let sameUserApplicationCombinedMetricProof: CPUProof?
}
