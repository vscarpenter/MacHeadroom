import Darwin

enum CPUConvention: Sendable {
  case machineCapacity
  case perCore
}

struct CPUDeltaInput: Sendable {
  let previousTicks: UInt64?
  let previousStartIdentity: String?
  let currentTicks: UInt64
  let currentStartIdentity: String
  let wallTimeNanoseconds: UInt64
}

/// Pure per-process CPU percent math. Isolated from the sampler actor so
/// fixture inputs can cover the first-tick and pid-reuse cases without any
/// live syscalls.
enum CPUDelta {
  static func percent(
    for input: CPUDeltaInput,
    timebase: mach_timebase_info_data_t,
    logicalCoreCount: Int,
    convention: CPUConvention
  ) -> Double? {
    guard
      let previousTicks = input.previousTicks,
      let previousStartIdentity = input.previousStartIdentity,
      previousStartIdentity == input.currentStartIdentity,
      input.currentTicks >= previousTicks,
      input.wallTimeNanoseconds > 0
    else {
      return nil
    }

    let deltaTicks = input.currentTicks - previousTicks
    let deltaNanoseconds = nanoseconds(fromMachTicks: deltaTicks, timebase: timebase)
    let perCorePercent = (Double(deltaNanoseconds) / Double(input.wallTimeNanoseconds)) * 100

    switch convention {
    case .perCore:
      return perCorePercent
    case .machineCapacity:
      return perCorePercent / Double(max(logicalCoreCount, 1))
    }
  }

  static func nanoseconds(
    fromMachTicks ticks: UInt64,
    timebase: mach_timebase_info_data_t
  ) -> UInt64 {
    let numerator = UInt64(timebase.numer)
    let denominator = UInt64(max(timebase.denom, 1))
    let quotient = ticks / denominator
    let remainder = ticks % denominator
    return quotient * numerator + (remainder * numerator) / denominator
  }
}
