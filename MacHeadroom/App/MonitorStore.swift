import AppKit
import Foundation
import Observation
import ServiceManagement

/// Holds the latest top-10 lists and system summary for the popover.
/// SamplerService and GroupingEngine do the real work; this just orchestrates
/// the tick, pulls live app metadata from NSWorkspace, and republishes.
@MainActor
@Observable
final class MonitorStore {
  private enum DefaultsKey {
    static let samplingInterval = "samplingInterval"
    static let perCoreConvention = "perCoreConvention"
    static let showsMenuBarText = "showsMenuBarText"
  }

  private(set) var topCPUGroups: [AppGroup] = []
  private(set) var topMemoryGroups: [AppGroup] = []
  private(set) var systemSummary = SystemSummary(
    cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
  private(set) var lastUpdated: Date?

  var samplingInterval: TimeInterval {
    didSet {
      UserDefaults.standard.set(samplingInterval, forKey: DefaultsKey.samplingInterval)
      guard timerTask != nil else { return }
      stop()
      start()
    }
  }

  var cpuConvention: CPUConvention {
    didSet {
      UserDefaults.standard.set(
        cpuConvention == .perCore, forKey: DefaultsKey.perCoreConvention)
    }
  }

  /// Off by default per the brief. Turning this on keeps sampling alive even
  /// while the popover is closed, since the menu bar label needs live data.
  var showsMenuBarText: Bool {
    didSet {
      UserDefaults.standard.set(showsMenuBarText, forKey: DefaultsKey.showsMenuBarText)
      if showsMenuBarText {
        start()
      } else if !isPopoverOpen {
        stop()
      }
    }
  }

  var launchAtLogin: Bool {
    didSet {
      guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
      do {
        if launchAtLogin {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
      } catch {
        launchAtLogin = SMAppService.mainApp.status == .enabled
      }
    }
  }

  private let sampler: SamplerService
  private let topListLimit = 10
  private var timerTask: Task<Void, Never>?
  private var isPopoverOpen = false

  init(sampler: SamplerService = SamplerService()) {
    self.sampler = sampler
    let defaults = UserDefaults.standard
    let storedInterval = defaults.double(forKey: DefaultsKey.samplingInterval)
    samplingInterval = storedInterval > 0 ? storedInterval : 5
    cpuConvention = defaults.bool(forKey: DefaultsKey.perCoreConvention) ? .perCore : .machineCapacity
    showsMenuBarText = defaults.bool(forKey: DefaultsKey.showsMenuBarText)
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  /// Sample immediately on open, per the brief, regardless of whether the
  /// timer loop was already running for the menu bar text option.
  func popoverDidAppear() {
    isPopoverOpen = true
    start()
    Task { await refreshNow() }
  }

  func popoverDidDisappear() {
    isPopoverOpen = false
    if !showsMenuBarText {
      stop()
    }
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

  private func start() {
    guard timerTask == nil else { return }
    timerTask = Task { [weak self] in
      while let self, !Task.isCancelled {
        await self.refreshNow()
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .seconds(self.samplingInterval))
      }
    }
  }

  private func stop() {
    timerTask?.cancel()
    timerTask = nil
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

extension MonitorStore {
  /// Same-file access to the private(set) properties above, used only to
  /// build fixture stores for SwiftUI previews.
  static func preview(
    cpuGroups: [AppGroup],
    memoryGroups: [AppGroup],
    summary: SystemSummary
  ) -> MonitorStore {
    let store = MonitorStore()
    store.topCPUGroups = cpuGroups
    store.topMemoryGroups = memoryGroups
    store.systemSummary = summary
    store.lastUpdated = Date()
    return store
  }
}
