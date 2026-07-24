import AppKit
import Foundation
import Observation

/// Holds the latest top-10 lists and system summary for the popover.
/// SamplerService and GroupingEngine do the real work; this just orchestrates
/// the tick, pulls live app metadata from NSWorkspace, and republishes.
@MainActor
@Observable
final class MonitorStore {
  private(set) var topCPUGroups: [AppGroup] = []
  private(set) var topMemoryGroups: [AppGroup] = []
  private(set) var systemSummary = SystemSummary(
    cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
  private(set) var lastUpdated: Date?

  var samplingInterval: TimeInterval = 5
  var cpuConvention: CPUConvention = .machineCapacity

  private let sampler: SamplerService
  private let topListLimit = 10
  private var timerTask: Task<Void, Never>?

  init(sampler: SamplerService = SamplerService()) {
    self.sampler = sampler
  }

  func start() {
    guard timerTask == nil else { return }
    timerTask = Task { [weak self] in
      while let self, !Task.isCancelled {
        await self.refreshNow()
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .seconds(self.samplingInterval))
      }
    }
  }

  func stop() {
    timerTask?.cancel()
    timerTask = nil
  }

  func refreshNow() async {
    let tick = await sampler.tick(
      now: DispatchTime.now().uptimeNanoseconds, convention: cpuConvention)
    let metadata = Self.currentAppMetadata()
    let groups = GroupingEngine.group(measurements: tick.processes, metadataByPID: metadata)

    topCPUGroups = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: topListLimit)
    topMemoryGroups = GroupingEngine.topGroups(
      from: groups, by: { Double($0.memoryBytes) }, limit: topListLimit)
    systemSummary = tick.system
    lastUpdated = Date()
  }

  private static func currentAppMetadata() -> [Int32: AppMetadata] {
    Dictionary(
      uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { app in
        (
          app.processIdentifier,
          AppMetadata(
            pid: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            name: app.localizedName ?? "Unknown"
          )
        )
      }
    )
  }
}
