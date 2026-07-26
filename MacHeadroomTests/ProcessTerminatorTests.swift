import Foundation
import Testing

@testable import MacHeadroom

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
    // PID_MAX on macOS is 99998; a just-above-range pid can't exist.
    #expect(ProcessTableSampler.startIdentity(of: 99_999) == nil)
  }
}
