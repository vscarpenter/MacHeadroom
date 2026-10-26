import Foundation
import Testing

@testable import SystemHeadroom

/// Live reads inside the sandboxed TEST_HOST. These re-prove on every
/// run that the App Sandbox allows the two sysctls the header badge
/// depends on (kern.memorystatus_vm_pressure_level and vm.swapusage).
@Suite("Host pressure live")
struct HostPressureLiveTests {
  @Test("Sandboxed pressure read returns a level")
  func pressure() throws {
    _ = try #require(HostSampler.sampleMemoryPressure())
  }

  @Test("Sandboxed swap read returns a snapshot within bounds")
  func swap() throws {
    let swap = try #require(HostSampler.sampleSwapUsage())
    #expect(swap.usedBytes <= swap.totalBytes)
  }

  @Test("Tick carries pressure and swap")
  func tickCarriesPressure() async throws {
    let tick = await SamplerService().tick(convention: .machineCapacity)
    #expect(tick.system.memoryPressure != nil)
    #expect(tick.system.swapUsedBytes != nil)
  }
}
