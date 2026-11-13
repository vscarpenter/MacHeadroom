import Darwin
import Foundation
import Testing

@testable import SystemHeadroom

/// The hardware reads have real answers only on a physical Mac. A CI
/// runner is a virtual machine with a paravirtual GPU and disk, so the
/// assertions that need hardware are skipped there. On a physical Mac
/// they are required: a nil reading means the sandbox closed the path.
enum TestHardware {
  static var isVirtualMachine: Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value == 1
  }
}

/// Live reads inside the sandboxed TEST_HOST. These re-prove on every
/// run that the App Sandbox allows the IOAccelerator property reads the
/// GPU tab depends on (SANDBOX_NOTES.md, November 13, 2026).
@Suite("GPU sampler live")
struct GPUSamplerLiveTests {
  @Test(
    "Sandboxed registry read returns utilization, memory, and client GPU time",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical GPU"))
  func reading() throws {
    let reading = try #require(GPUSampler.sample())

    #expect((0...100).contains(reading.deviceUtilizationPercent))
    #expect(reading.allocatedMemoryBytes != nil)
    #expect(!reading.gpuTimeNanosecondsByPID.isEmpty)
    #expect(reading.reportsClientUsage)
    // Something has drawn since boot, so the counters are not all zero.
    #expect(reading.gpuTimeNanosecondsByPID.values.contains { $0 > 0 })
  }

  @Test("The registry sweep is cheap enough to ride every tick")
  func sweepCost() {
    let elapsed = ContinuousClock().measure { _ = GPUSampler.sample() }
    print("GPU_SWEEP \(elapsed)")
    // Generous: CI runs timing-sensitive work up to 2.6x slower.
    #expect(elapsed < .milliseconds(250))
  }
}
