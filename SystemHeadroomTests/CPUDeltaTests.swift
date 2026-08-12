import Darwin
import Testing

@testable import SystemHeadroom

@Suite("CPU delta math")
struct CPUDeltaTests {
  static let unitTimebase = mach_timebase_info_data_t(numer: 1, denom: 1)

  @Test("First tick has no prior sample, so CPU percent is unavailable")
  func firstTickReturnsNil() {
    let input = CPUDeltaInput(
      previousTicks: nil,
      previousStartIdentity: nil,
      currentTicks: 1_000,
      currentStartIdentity: "100:0",
      wallTimeNanoseconds: 1_000_000_000
    )
    let percent = CPUDelta.percent(
      for: input, timebase: Self.unitTimebase, logicalCoreCount: 4, convention: .machineCapacity
    )
    #expect(percent == nil)
  }

  @Test("A reused pid with a different start time is treated as a new process")
  func pidReuseReturnsNil() {
    let input = CPUDeltaInput(
      previousTicks: 500_000_000,
      previousStartIdentity: "100:0",
      currentTicks: 600_000_000,
      currentStartIdentity: "200:0",
      wallTimeNanoseconds: 1_000_000_000
    )
    let percent = CPUDelta.percent(
      for: input, timebase: Self.unitTimebase, logicalCoreCount: 4, convention: .machineCapacity
    )
    #expect(percent == nil)
  }

  @Test("A counter that moved backward between samples is rejected")
  func counterRegressionReturnsNil() {
    let input = CPUDeltaInput(
      previousTicks: 900_000_000,
      previousStartIdentity: "100:0",
      currentTicks: 800_000_000,
      currentStartIdentity: "100:0",
      wallTimeNanoseconds: 1_000_000_000
    )
    let percent = CPUDelta.percent(
      for: input, timebase: Self.unitTimebase, logicalCoreCount: 4, convention: .machineCapacity
    )
    #expect(percent == nil)
  }

  @Test("Machine-capacity convention divides by the logical core count")
  func machineCapacityConvention() {
    let input = CPUDeltaInput(
      previousTicks: 0,
      previousStartIdentity: "100:0",
      currentTicks: 500_000_000,
      currentStartIdentity: "100:0",
      wallTimeNanoseconds: 1_000_000_000
    )
    let percent = CPUDelta.percent(
      for: input, timebase: Self.unitTimebase, logicalCoreCount: 4, convention: .machineCapacity
    )
    #expect(percent == 12.5)
  }

  @Test("Per-core convention reports the saturated-core reading directly")
  func perCoreConvention() {
    let input = CPUDeltaInput(
      previousTicks: 0,
      previousStartIdentity: "100:0",
      currentTicks: 500_000_000,
      currentStartIdentity: "100:0",
      wallTimeNanoseconds: 1_000_000_000
    )
    let percent = CPUDelta.percent(
      for: input, timebase: Self.unitTimebase, logicalCoreCount: 4, convention: .perCore
    )
    #expect(percent == 50.0)
  }

  @Test("A non-trivial mach timebase still converts ticks to nanoseconds correctly")
  func nonTrivialTimebase() {
    let timebase = mach_timebase_info_data_t(numer: 125, denom: 3)
    let input = CPUDeltaInput(
      previousTicks: 0,
      previousStartIdentity: "100:0",
      currentTicks: 6,
      currentStartIdentity: "100:0",
      wallTimeNanoseconds: 250
    )
    let percent = CPUDelta.percent(
      for: input, timebase: timebase, logicalCoreCount: 1, convention: .perCore
    )
    #expect(percent == 100.0)
  }
}

@Suite("Host CPU delta math")
struct HostCPUDeltaTests {
  @Test("First tick has no prior host sample")
  func firstTickReturnsNil() {
    let current = HostCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
    #expect(HostCPUDelta.percent(previous: nil, current: current) == nil)
  }

  @Test("Busy ticks over total ticks yields the machine-wide percent")
  func normalCase() {
    let previous = HostCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
    let current = HostCPUTicks(user: 150, system: 70, idle: 880, nice: 0)
    #expect(HostCPUDelta.percent(previous: previous, current: current) == 70.0)
  }
}
