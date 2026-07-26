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
    static let usesPorcelainAppearance = "usesPorcelainAppearance"
    static let legacyMaxHeadroomModeEnabled = "maxHeadroomModeEnabled"
  }

  private(set) var topCPUGroups: [AppGroup] = []
  private(set) var topMemoryGroups: [AppGroup] = []
  private(set) var systemSummary = SystemSummary(
    cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
  private(set) var lastUpdated: Date?

  var samplingInterval: TimeInterval {
    didSet {
      defaults.set(samplingInterval, forKey: DefaultsKey.samplingInterval)
      guard timerTask != nil else { return }
      stop()
      start()
    }
  }

  var cpuConvention: CPUConvention {
    didSet {
      defaults.set(
        cpuConvention == .perCore, forKey: DefaultsKey.perCoreConvention)
    }
  }

  /// Off by default per the brief. Turning this on keeps sampling alive even
  /// while the popover is closed, since the menu bar label needs live data.
  var showsMenuBarText: Bool {
    didSet {
      defaults.set(showsMenuBarText, forKey: DefaultsKey.showsMenuBarText)
      if showsMenuBarText {
        start()
      } else if !isPopoverOpen {
        stop()
      }
    }
  }

  /// Porcelain Native is the default presentation. Users can still select
  /// the classic compact view without changing sampling or measurements.
  var usesPorcelainAppearance: Bool {
    didSet {
      defaults.set(usesPorcelainAppearance, forKey: DefaultsKey.usesPorcelainAppearance)
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

  let canTerminate: Bool
  private let terminator: ProcessTerminator
  private let sampler: SamplerService
  private let defaults: UserDefaults
  private let topListLimit = 10
  private var timerTask: Task<Void, Never>?
  private var isPopoverOpen = false

  init(
    sampler: SamplerService = SamplerService(),
    defaults: UserDefaults = .standard,
    capability: TerminationCapability = .current,
    terminator: ProcessTerminator = .live()
  ) {
    self.canTerminate = capability == .available
    self.terminator = terminator
    self.sampler = sampler
    self.defaults = defaults
    let storedInterval = defaults.double(forKey: DefaultsKey.samplingInterval)
    samplingInterval = storedInterval > 0 ? storedInterval : 5
    cpuConvention =
      defaults.bool(forKey: DefaultsKey.perCoreConvention) ? .perCore : .machineCapacity
    showsMenuBarText = defaults.bool(forKey: DefaultsKey.showsMenuBarText)
    if let storedAppearance = defaults.object(
      forKey: DefaultsKey.usesPorcelainAppearance
    ) as? Bool {
      usesPorcelainAppearance = storedAppearance
    } else if let legacyAppearance = defaults.object(
      forKey: DefaultsKey.legacyMaxHeadroomModeEnabled
    ) as? Bool {
      usesPorcelainAppearance = legacyAppearance
      defaults.set(legacyAppearance, forKey: DefaultsKey.usesPorcelainAppearance)
    } else {
      usesPorcelainAppearance = true
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
    // Property observers don't run during init, so the menu bar text option
    // has to start its live sampling here on relaunch.
    if showsMenuBarText {
      start()
    }
  }

  /// Sample immediately on open, per the brief. Starting the timer already
  /// refreshes at once, so the explicit refresh is only for the case where
  /// the loop was running for the menu bar text option; issuing both would
  /// stack two ticks back to back.
  func popoverDidAppear() {
    isPopoverOpen = true
    if timerTask == nil {
      start()
    } else {
      Task { await refreshNow() }
    }
  }

  func popoverDidDisappear() {
    isPopoverOpen = false
    if !showsMenuBarText {
      stop()
    }
  }

  func refreshNow() async {
    let tick = await sampler.tick(convention: cpuConvention)
    let metadata = Self.currentAppMetadata()
    let groups = GroupingEngine.group(measurements: tick.processes, metadataByPID: metadata)

    topCPUGroups = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: topListLimit)
    topMemoryGroups = GroupingEngine.topGroups(
      from: groups, by: { Double($0.memoryBytes) }, limit: topListLimit)
    systemSummary = tick.system
    lastUpdated = Date()
  }

  /// Termination feedback is the next sample: the row disappearing (or
  /// not) tells the truth better than a result state machine would.
  func quit(_ group: AppGroup) {
    performTermination { terminator.quit(group) }
  }

  func forceQuit(_ group: AppGroup) {
    performTermination { terminator.forceQuit(group) }
  }

  private func performTermination(_ action: () -> TerminationOutcome) {
    guard canTerminate else { return }
    _ = action()
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      await self?.refreshNow()
    }
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
    summary: SystemSummary,
    usesPorcelainAppearance: Bool = true,
    canTerminate: Bool = false
  ) -> MonitorStore {
    let suiteName = "com.vinnycarpenter.MacHeadroom.preview"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Could not create preview defaults")
    }
    defaults.removePersistentDomain(forName: suiteName)
    let store = MonitorStore(
      defaults: defaults,
      capability: canTerminate ? .available : .sandboxed,
      terminator: ProcessTerminator(
        runningApplication: { _ in nil },
        currentStartIdentity: { _ in nil },
        sendSignal: { _, _ in 0 }))
    store.topCPUGroups = cpuGroups
    store.topMemoryGroups = memoryGroups
    store.systemSummary = summary
    store.lastUpdated = Date()
    store.usesPorcelainAppearance = usesPorcelainAppearance
    return store
  }
}
