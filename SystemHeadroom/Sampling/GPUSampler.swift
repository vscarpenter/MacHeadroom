import Foundation
import IOKit

/// Reads the GPU's registry counters: the accelerator's own statistics,
/// then each child user client's owner and accumulated GPU time. This
/// is the path the App Sandbox permits; IOReport, which carries power
/// and frequency, needs a user client the sandbox denies
/// (Evidence/gpu-drives-spike/). Parsing lives in GPUStatsParser.
enum GPUSampler {
  /// The first accelerator that reports device utilization. Apple
  /// silicon has exactly one. nil when none reports it.
  static func sample() -> GPUReading? {
    var reading: GPUReading?
    IORegistry.forEachService(className: "IOAccelerator") { service in
      guard reading == nil else { return }

      var accelerator: [String: Any] = [:]
      for key in ["PerformanceStatistics", "model", "gpu-core-count"] {
        accelerator[key] = IORegistry.property(key, of: service)
      }

      var clients: [[String: Any]] = []
      IORegistry.forEachChild(of: service) { child in
        var client: [String: Any] = [:]
        for key in ["IOUserClientCreator", "AppUsage"] {
          client[key] = IORegistry.property(key, of: child)
        }
        clients.append(client)
      }

      reading = GPUStatsParser.reading(accelerator: accelerator, clients: clients)
    }
    return reading
  }
}
