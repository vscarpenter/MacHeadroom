import Foundation
import IOKit

/// Reads the GPU's registry counters: each accelerator's own statistics,
/// then each child user client's owner and accumulated GPU time. This
/// is the path the App Sandbox permits; IOReport, which carries power
/// and frequency, needs a user client the sandbox denies
/// (Evidence/gpu-drives-spike/). Parsing lives in GPUStatsParser.
enum GPUSampler {
  /// nil when no accelerator reports device utilization. Apple silicon
  /// has exactly one accelerator; the parser picks the busier of two.
  static func sample() -> GPUReading? {
    var accelerators: [(properties: [String: Any], clients: [[String: Any]])] = []
    IORegistry.forEachService(className: "IOAccelerator") { service in
      var properties: [String: Any] = [:]
      for key in ["PerformanceStatistics", "model", "gpu-core-count"] {
        properties[key] = IORegistry.property(key, of: service)
      }

      var clients: [[String: Any]] = []
      IORegistry.forEachChild(of: service) { child in
        var client: [String: Any] = [:]
        for key in ["IOUserClientCreator", "AppUsage"] {
          client[key] = IORegistry.property(key, of: child)
        }
        clients.append(client)
      }

      accelerators.append((properties: properties, clients: clients))
    }
    return GPUStatsParser.reading(accelerators: accelerators)
  }
}
