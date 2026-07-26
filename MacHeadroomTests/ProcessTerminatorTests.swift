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
