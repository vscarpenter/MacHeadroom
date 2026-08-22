import AppKit
import Darwin
import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Process memory metric")
struct ProcessMemoryMetricTests {
  @Test("Sandboxed builds use RSS while Direct builds use physical footprint")
  func buildFlavorSelection() {
    #expect(ProcessMemoryMetric.forSandboxedBuild(true) == .residentSize)
    #expect(ProcessMemoryMetric.forSandboxedBuild(false) == .physicalFootprint)
    #expect(AppSandboxStatus.current == .enabled)
    #expect(ProcessMemoryMetric.current == .residentSize)
  }

  @Test("Physical-footprint mode never silently falls back to RSS")
  func metricSelection() {
    #expect(
      ProcessMemoryMetric.residentSize.value(
        residentBytes: 10, physicalFootprintBytes: 20) == 10)
    #expect(
      ProcessMemoryMetric.physicalFootprint.value(
        residentBytes: 10, physicalFootprintBytes: 20) == 20)
    #expect(
      ProcessMemoryMetric.physicalFootprint.value(
        residentBytes: 10, physicalFootprintBytes: nil) == nil)
  }

  @Test("The physical-footprint API returns a value for this process")
  func ownPhysicalFootprintIsReadable() throws {
    let footprint = try #require(
      ProcessTableSampler.physicalFootprintBytes(
        for: ProcessInfo.processInfo.processIdentifier))
    #expect(footprint > 0)
  }

  @Test("The sandbox blocks another same-user process's physical footprint")
  func otherPhysicalFootprintIsBlocked() throws {
    let finder = try #require(
      NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.finder"
      ).first)
    #expect(finder.processIdentifier != ProcessInfo.processInfo.processIdentifier)
    #expect(
      ProcessTableSampler.physicalFootprintBytes(
        for: finder.processIdentifier) == nil)
  }
}

@Suite("Sampler wall-clock integrity")
struct SamplerBurstTests {
  /// Overlapping refreshes capture their timestamps before awaiting the
  /// sampler actor, so back-to-back ticks can carry a near-zero wall time
  /// while their sweeps sit tens of milliseconds apart. Dividing real CPU
  /// accrual by that near-zero window inflated percentages a thousandfold.
  @Test("Nearly simultaneous ticks do not inflate CPU percentages")
  func burstTicksStayBounded() async throws {
    // Burn a core so this process shows real CPU accrual during the sweeps.
    let burning = Thread {
      var x = 0.5
      while !Thread.current.isCancelled { x = sqrt(x + 1) }
    }
    burning.start()
    defer { burning.cancel() }

    let service = SamplerService()
    _ = await service.tick(convention: .machineCapacity)
    try await Task.sleep(for: .milliseconds(400))

    // Back-to-back ticks, the way an overlapping timer refresh and popover
    // refresh land on the actor. The actor measures its own wall time, so
    // even a zero-delay burst divides by the real inter-sweep spacing.
    _ = await service.tick(convention: .machineCapacity)
    let burst = await service.tick(convention: .machineCapacity)

    // Machine-capacity percent is physically bounded by 100; allow slack
    // for sweep-timing jitter, nothing more.
    let worstPercent = burst.processes.compactMap(\.cpuPercent).max() ?? 0
    #expect(worstPercent < 150)
  }
}
