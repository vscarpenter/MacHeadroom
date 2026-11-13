import Foundation

/// One reading of the GPU's registry counters. Every field but device
/// utilization is optional: the property names are undocumented, so a
/// missing key is an unknown, never a zero.
struct GPUReading: Sendable, Equatable {
  var model: String?
  var coreCount: Int?
  var deviceUtilizationPercent: Double
  var rendererUtilizationPercent: Double?
  var tilerUtilizationPercent: Double?
  /// Memory GPU clients hold. On Apple silicon it comes out of system
  /// memory; there is no fixed pool.
  var allocatedMemoryBytes: UInt64?
  /// Memory that in-flight GPU work references. It rises while work runs
  /// and falls back after (Evidence/gpu-drives-spike/out-gpumem.txt).
  var inUseMemoryBytes: UInt64?
  /// Accumulated GPU nanoseconds per owning pid, summed across its clients.
  var gpuTimeNanosecondsByPID: [Int32: UInt64]
  /// Names from the registry, for pids outside the same-user process table.
  var clientNamesByPID: [Int32: String]
  /// Whether any client carried a usage list at all. Apple silicon
  /// drivers publish one per client. A driver that publishes none
  /// reports utilization but no per-app time, which is different from
  /// every app being idle.
  var reportsClientUsage: Bool
}

/// Turns IORegistry property dictionaries into a GPUReading. Pure and
/// fixture-testable: GPUSampler does the registry calls.
enum GPUStatsParser {
  /// `accelerator` holds the accelerator's `PerformanceStatistics`,
  /// `model`, and `gpu-core-count`. Each client holds its
  /// `IOUserClientCreator` and `AppUsage`. Returns nil when the
  /// accelerator reports no device utilization.
  static func reading(accelerator: [String: Any], clients: [[String: Any]]) -> GPUReading? {
    reading(accelerators: [(properties: accelerator, clients: clients)])
  }

  /// A Mac can have two GPUs. The busier one supplies the headline
  /// figures, since headroom is whatever the fuller GPU has left.
  /// Client GPU time merges across all of them. Returns nil when no
  /// accelerator reports device utilization.
  static func reading(
    accelerators: [(properties: [String: Any], clients: [[String: Any]])]
  ) -> GPUReading? {
    var busiest: (statistics: [String: Any], utilization: Double, properties: [String: Any])?
    var timeByPID: [Int32: UInt64] = [:]
    var namesByPID: [Int32: String] = [:]
    var reportsClientUsage = false

    for accelerator in accelerators {
      if let statistics = accelerator.properties["PerformanceStatistics"] as? [String: Any],
        let utilization = double(statistics["Device Utilization %"]),
        utilization > busiest?.utilization ?? -.infinity
      {
        busiest = (statistics, utilization, accelerator.properties)
      }

      for client in accelerator.clients {
        guard let usage = client["AppUsage"] as? [[String: Any]] else { continue }
        reportsClientUsage = true
        guard let creator = client["IOUserClientCreator"] as? String,
          let owner = parseCreator(creator)
        else { continue }
        let clientTime = usage.reduce(UInt64(0)) { total, entry in
          saturatingSum(total, unsigned(entry["accumulatedGPUTime"]) ?? 0)
        }
        timeByPID[owner.pid] = saturatingSum(timeByPID[owner.pid] ?? 0, clientTime)
        namesByPID[owner.pid] = owner.name
      }
    }

    guard let busiest else { return nil }
    let statistics = busiest.statistics
    let accelerator = busiest.properties
    let deviceUtilization = busiest.utilization

    return GPUReading(
      model: text(accelerator["model"]),
      coreCount: (accelerator["gpu-core-count"] as? NSNumber)?.intValue,
      deviceUtilizationPercent: deviceUtilization,
      rendererUtilizationPercent: double(statistics["Renderer Utilization %"]),
      tilerUtilizationPercent: double(statistics["Tiler Utilization %"]),
      allocatedMemoryBytes: unsigned(statistics["Alloc system memory"]),
      inUseMemoryBytes: unsigned(statistics["In use system memory"]),
      gpuTimeNanosecondsByPID: timeByPID,
      clientNamesByPID: namesByPID,
      reportsClientUsage: reportsClientUsage
    )
  }

  /// The registry writes a client's owner as "pid 653, WindowServer".
  static func parseCreator(_ creator: String) -> (pid: Int32, name: String)? {
    let prefix = "pid "
    guard creator.hasPrefix(prefix), let comma = creator.firstIndex(of: ",") else {
      return nil
    }
    let pidText = creator[creator.index(creator.startIndex, offsetBy: prefix.count)..<comma]
    guard let pid = Int32(pidText), pid > 0 else { return nil }
    let name = creator[creator.index(after: comma)...].trimmingCharacters(in: .whitespaces)
    return (pid, name)
  }

  private static func double(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  private static func unsigned(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber, number.doubleValue >= 0 else { return nil }
    return number.uint64Value
  }

  /// Apple silicon stores the model as a string; Intel-era drivers
  /// stored NUL-terminated bytes.
  private static func text(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    guard let data = value as? Data else { return nil }
    let decoded = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    return decoded.isEmpty ? nil : decoded
  }

  private static func saturatingSum(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}

/// Per-process GPU percent from two readings of the accumulated-time
/// counters: the share of wall time the GPU spent on that process's work.
enum GPUDelta {
  /// A pid gets a percent only when both readings hold its counter, the
  /// counter did not move backward (a client closed), and the pid still
  /// names the same process.
  static func percents(
    previous: [Int32: UInt64],
    current: [Int32: UInt64],
    wallTimeNanoseconds: UInt64,
    identityChanged: (Int32) -> Bool
  ) -> [Int32: Double] {
    guard wallTimeNanoseconds > 0 else { return [:] }
    var percents: [Int32: Double] = [:]
    for (pid, now) in current {
      guard let before = previous[pid], now >= before, !identityChanged(pid) else { continue }
      percents[pid] = Double(now - before) / Double(wallTimeNanoseconds) * 100
    }
    return percents
  }
}
