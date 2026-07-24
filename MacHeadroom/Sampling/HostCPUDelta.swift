/// Pure machine-wide CPU percent math. Host ticks are already ratios of one
/// another, so unlike per-process CPU this never needs a mach timebase
/// conversion against wall time.
enum HostCPUDelta {
  static func percent(previous: HostCPUTicks?, current: HostCPUTicks) -> Double? {
    guard let previous else { return nil }

    let deltaTotal = current.totalTicks &- previous.totalTicks
    let deltaBusy = current.busyTicks &- previous.busyTicks
    guard
      current.totalTicks >= previous.totalTicks,
      current.busyTicks >= previous.busyTicks,
      deltaTotal > 0
    else {
      return nil
    }

    return (Double(deltaBusy) / Double(deltaTotal)) * 100
  }
}
