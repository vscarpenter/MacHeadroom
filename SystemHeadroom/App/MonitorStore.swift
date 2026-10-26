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
    static let cpuAlertsEnabled = "cpuAlertsEnabled"
    static let cpuAlertThresholdPercent = "cpuAlertThresholdPercent"
    static let cpuAlertSustainSeconds = "cpuAlertSustainSeconds"
  }

  private(set) var topCPUGroups: [AppGroup] = []
  private(set) var topMemoryGroups: [AppGroup] = []
  /// nil = ports unavailable this tick (sysctl or parse failure);
  /// [] = genuinely nothing listening. Starts [] so launch shows the
  /// empty state, not the failure state, before the first sample.
  private(set) var portGroups: [PortGroup]? = []
  private(set) var systemSummary = SystemSummary(
    cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
  private(set) var processMemoryMetric = ProcessMemoryMetric.current
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
      } else {
        stopIfIdle()
      }
    }
  }

  /// Off by default. On, it asks macOS once for notification permission
  /// and keeps sampling alive while the popover is closed, like the menu
  /// bar percent does, so a runaway app is caught with nothing open.
  var cpuAlertsEnabled: Bool {
    didSet {
      defaults.set(cpuAlertsEnabled, forKey: DefaultsKey.cpuAlertsEnabled)
      if cpuAlertsEnabled {
        alertDelivery.requestAuthorization()
        start()
      } else {
        alertTracker = CPUAlertTracker()
        stopIfIdle()
      }
    }
  }

  /// Percent of one core, the way Activity Monitor counts, whatever
  /// convention the list displays: under machine capacity one saturated
  /// core is about 7% on a 14-core Mac, which no sensible threshold
  /// would catch.
  var cpuAlertThresholdPercent: Int {
    didSet {
      defaults.set(cpuAlertThresholdPercent, forKey: DefaultsKey.cpuAlertThresholdPercent)
    }
  }

  var cpuAlertSustainSeconds: Int {
    didSet {
      defaults.set(cpuAlertSustainSeconds, forKey: DefaultsKey.cpuAlertSustainSeconds)
    }
  }

  /// Whether the sampling timer is running; the start and stop rules
  /// above are what the tests pin.
  var isSampling: Bool { timerTask != nil }

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
  private let alertDelivery: AlertDelivery
  private let topListLimit = 10
  private var timerTask: Task<Void, Never>?
  private var isPopoverOpen = false
  private var alertTracker = CPUAlertTracker()

  private var needsBackgroundSampling: Bool {
    showsMenuBarText || cpuAlertsEnabled
  }

  init(
    sampler: SamplerService = SamplerService(),
    defaults: UserDefaults = .standard,
    capability: TerminationCapability = .current,
    terminator: ProcessTerminator = .live(),
    alertDelivery: AlertDelivery = NotificationAlertDelivery()
  ) {
    self.canTerminate = capability == .available
    self.terminator = terminator
    self.sampler = sampler
    self.defaults = defaults
    self.alertDelivery = alertDelivery
    let storedInterval = defaults.double(forKey: DefaultsKey.samplingInterval)
    samplingInterval = storedInterval > 0 ? storedInterval : 5
    cpuConvention =
      defaults.bool(forKey: DefaultsKey.perCoreConvention) ? .perCore : .machineCapacity
    showsMenuBarText = defaults.bool(forKey: DefaultsKey.showsMenuBarText)
    cpuAlertsEnabled = defaults.bool(forKey: DefaultsKey.cpuAlertsEnabled)
    let storedThreshold = defaults.integer(forKey: DefaultsKey.cpuAlertThresholdPercent)
    cpuAlertThresholdPercent = storedThreshold > 0 ? storedThreshold : 90
    let storedSustain = defaults.integer(forKey: DefaultsKey.cpuAlertSustainSeconds)
    cpuAlertSustainSeconds = storedSustain > 0 ? storedSustain : 60
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
    // Property observers don't run during init, so the menu bar text and
    // alert options have to start their live sampling here on relaunch.
    if needsBackgroundSampling {
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
    stopIfIdle()
  }

  func refreshNow() async {
    let tick = await sampler.tick(convention: cpuConvention)
    let metadata = Self.currentAppMetadata()
    let groups = GroupingEngine.group(measurements: tick.processes, metadataByPID: metadata)

    topCPUGroups = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: topListLimit)
    topMemoryGroups = GroupingEngine.topGroups(
      from: groups, by: { Double($0.memoryBytes) }, limit: topListLimit)
    portGroups = PortGroupBuilder.build(
      sockets: tick.sockets, groups: groups,
      fallbackNamesByPID: tick.socketFallbackNames)
    systemSummary = tick.system
    processMemoryMetric = tick.processMemoryMetric
    lastUpdated = Date()
    evaluateAlerts(
      groups: topCPUGroups, convention: tick.convention,
      logicalCoreCount: tick.logicalCoreCount, now: Date())
  }

  /// Internal so a test can drive it with fixture groups and a fixed
  /// clock. The convention and core count come from the tick that
  /// produced the groups, not from the preference, which can change
  /// while the sampler is mid-sweep.
  func evaluateAlerts(
    groups: [AppGroup], convention: CPUConvention, logicalCoreCount: Int, now: Date
  ) {
    guard cpuAlertsEnabled else { return }
    let policy = CPUAlertPolicy(
      thresholdPercentOfCore: cpuAlertThresholdPercent,
      sustainSeconds: cpuAlertSustainSeconds)
    let candidates = Self.candidates(
      from: groups, convention: convention, logicalCoreCount: logicalCoreCount)
    for alert in alertTracker.observe(candidates, at: now, policy: policy) {
      alertDelivery.deliver(alert)
    }
  }

  /// A group with no CPU reading yet (the priming tick) is not a
  /// candidate; treating it as zero would end a live episode early.
  static func candidates(
    from groups: [AppGroup], convention: CPUConvention, logicalCoreCount: Int
  ) -> [CPUAlertCandidate] {
    groups.compactMap { group in
      guard let percent = group.cpuPercent else { return nil }
      let percentOfCore =
        convention == .machineCapacity ? percent * Double(logicalCoreCount) : percent
      return CPUAlertCandidate(
        groupKey: group.groupKey, name: group.name, percentOfCore: percentOfCore)
    }
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
      // The first tick after launch only primes the CPU baseline (every
      // delta needs two samples), so it publishes no CPU numbers. Follow
      // it with one quick sample so real data lands in about a second
      // instead of a full interval later. Once only: if the host reading
      // ever failed outright, this must not tighten the loop to 1s forever.
      var usedQuickFollowUp = false
      while let self, !Task.isCancelled {
        await self.refreshNow()
        guard !Task.isCancelled else { return }
        let delay: TimeInterval
        if !usedQuickFollowUp, self.systemSummary.cpuPercent == nil {
          usedQuickFollowUp = true
          delay = min(1, self.samplingInterval)
        } else {
          delay = self.samplingInterval
        }
        try? await Task.sleep(for: .seconds(delay))
      }
    }
  }

  private func stop() {
    timerTask?.cancel()
    timerTask = nil
  }

  /// Sampling stays alive while anything needs it: the open popover, the
  /// menu bar percent, or alerts.
  private func stopIfIdle() {
    guard !isPopoverOpen, !needsBackgroundSampling else { return }
    stop()
  }

  private static func currentAppMetadata() -> [Int32: AppMetadata] {
    metadataTable(
      from: NSWorkspace.shared.runningApplications.map { app in
        AppMetadata(
          pid: app.processIdentifier,
          bundleIdentifier: app.bundleIdentifier,
          name: app.localizedName ?? "Unknown"
        )
      }
    )
  }

  /// NSRunningApplication reports a pid of -1 once the app has terminated, so
  /// a sweep catching two apps mid-exit yields two entries under the same key
  /// and traps `Dictionary(uniqueKeysWithValues:)`. Nothing the sampler
  /// reports has a non-positive pid, so a terminated entry could never match a
  /// row: drop it rather than keep unusable metadata.
  static func metadataTable(from entries: [AppMetadata]) -> [Int32: AppMetadata] {
    Dictionary(
      entries.lazy.filter { $0.pid > 0 }.map { ($0.pid, $0) },
      uniquingKeysWith: { first, _ in first }
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
    canTerminate: Bool = false,
    portGroups: [PortGroup]? = []
  ) -> MonitorStore {
    let suiteName = "com.vinnycarpenter.SystemHeadroom.preview"
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
        sendSignal: { _, _ in 0 }),
      alertDelivery: NoOpAlertDelivery())
    store.topCPUGroups = cpuGroups
    store.topMemoryGroups = memoryGroups
    store.portGroups = portGroups
    store.systemSummary = summary
    store.processMemoryMetric = canTerminate ? .physicalFootprint : .residentSize
    store.lastUpdated = Date()
    store.usesPorcelainAppearance = usesPorcelainAppearance
    return store
  }
}
