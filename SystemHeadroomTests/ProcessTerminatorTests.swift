import AppKit
import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Termination capability")
struct TerminationCapabilityTests {
  /// The test host is the sandboxed app itself, so the capability check
  /// must report sandboxed here. The available case is exercised by the
  /// Direct build's manual checklist; keep its code path trivial.
  @Test("Test host reports sandboxed")
  func testHostIsSandboxed() {
    #expect(TerminationCapability.current == .sandboxed)
  }

  @Test("Flavor names match distribution channels")
  func flavorNames() {
    #expect(TerminationCapability.sandboxed.buildFlavorName == "App Store")
    #expect(TerminationCapability.available.buildFlavorName == "Direct")
  }
}

@Suite("Single-pid identity")
struct SinglePidIdentityTests {
  @Test("Own pid resolves and matches the full-table identity")
  func ownPidMatchesTable() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let single = ProcessTableSampler.startIdentity(of: pid)
    let table = ProcessTableSampler.sampleReachableProcesses()
      .first { $0.pid == pid }?.startIdentity
    #expect(single != nil)
    #expect(single == table)
  }

  @Test("A dead pid returns nil")
  func deadPidReturnsNil() {
    // xnu's PID_MAX is 99999, so a pid an order of magnitude above that
    // is unattainable and can't exist.
    #expect(ProcessTableSampler.startIdentity(of: 999_999) == nil)
  }
}

@Suite("ProcessTerminator")
@MainActor
struct ProcessTerminatorSuite {
  static func group(pid: Int32, identity: String) -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: pid, parentPID: 1, userID: 501, name: "victim",
      startIdentity: identity, cpuTimeTicks: 0, residentBytes: 1)
    return AppGroup(
      groupKey: "victim", name: "victim", bundleIdentifier: nil,
      representativePID: pid,
      cpuPercent: nil, memoryBytes: 1,
      children: [ProcessMeasurement(snapshot: snapshot, cpuPercent: nil)])
  }

  @Test("App groups quit via the app handle, not signals")
  func appPathUsesHandle() {
    var terminated = false
    var signals: [Int32] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        RunningAppHandle(
          terminate: { terminated = true; return true },
          forceTerminate: { false })
      },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, sig in signals.append(sig); return 0 })
    let outcome = terminator.quit(Self.group(pid: 500, identity: "1:1"))
    #expect(outcome == .requestedAppQuit)
    #expect(terminated)
    #expect(signals.isEmpty)
  }

  @Test("Force quit on an app group calls forceTerminate")
  func appForcePath() {
    var forced = false
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        RunningAppHandle(
          terminate: { false },
          forceTerminate: { forced = true; return true })
      },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, _ in 0 })
    let outcome = terminator.forceQuit(Self.group(pid: 500, identity: "1:1"))
    #expect(outcome == .requestedAppQuit)
    #expect(forced)
  }

  @Test("Standalone quit sends SIGTERM only when identity matches")
  func standaloneMatchSendsTerm() {
    var sent: [(Int32, Int32)] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "7:70" },
      sendSignal: { pid, sig in sent.append((pid, sig)); return 0 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .signaled)
    #expect(sent.count == 1)
    #expect(sent[0].0 == 42)
    #expect(sent[0].1 == SIGTERM)
  }

  @Test("Standalone force quit sends SIGKILL")
  func standaloneForceSendsKill() {
    var sent: [Int32] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "7:70" },
      sendSignal: { _, sig in sent.append(sig); return 0 })
    _ = terminator.forceQuit(Self.group(pid: 42, identity: "7:70"))
    #expect(sent == [SIGKILL])
  }

  @Test("Identity mismatch aborts without signaling")
  func staleIdentityAborts() {
    var signalCount = 0
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "9:99" },
      sendSignal: { _, _ in signalCount += 1; return 0 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .staleIdentity)
    #expect(signalCount == 0)
  }

  @Test("Vanished pid aborts without signaling")
  func vanishedPidAborts() {
    var signalCount = 0
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in nil },
      sendSignal: { _, _ in signalCount += 1; return 0 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .processGone)
    #expect(signalCount == 0)
  }

  @Test("Signal failure reports errno")
  func signalFailureReportsErrno() {
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "7:70" },
      sendSignal: { _, _ in errno = EPERM; return -1 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .signalFailed(errno: EPERM))
  }

  @Test("App refusal is reported")
  func appRefusalReported() {
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        RunningAppHandle(terminate: { false }, forceTerminate: { false })
      },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, _ in 0 })
    #expect(terminator.quit(Self.group(pid: 500, identity: "1:1")) == .appRefused)
  }

  @Test("App group with stale identity aborts before reaching the app handle")
  func appPathStaleIdentityAborts() {
    var handleVended = false
    var terminateInvoked = false
    var forceTerminateInvoked = false
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        handleVended = true
        return RunningAppHandle(
          terminate: { terminateInvoked = true; return true },
          forceTerminate: { forceTerminateInvoked = true; return true })
      },
      currentStartIdentity: { _ in "9:99" },
      sendSignal: { _, _ in 0 })
    let outcome = terminator.quit(Self.group(pid: 500, identity: "1:1"))
    #expect(outcome == .staleIdentity)
    #expect(handleVended == false)
    #expect(terminateInvoked == false)
    #expect(forceTerminateInvoked == false)
  }

  @Test("App group with vanished pid aborts before reaching the app handle")
  func appPathVanishedPidAborts() {
    var handleVended = false
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        handleVended = true
        return RunningAppHandle(terminate: { true }, forceTerminate: { true })
      },
      currentStartIdentity: { _ in nil },
      sendSignal: { _, _ in 0 })
    let outcome = terminator.quit(Self.group(pid: 500, identity: "1:1"))
    #expect(outcome == .processGone)
    #expect(handleVended == false)
  }
}
