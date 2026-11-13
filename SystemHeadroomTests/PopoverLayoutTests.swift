import AppKit
import SwiftUI
import Testing

@testable import SystemHeadroom

@Suite("Popover layout")
struct PopoverLayoutTests {
  /// MenuBarExtra(.window) sizes its panel once, when it opens, and never
  /// grows it afterward. The popover always opens before the first sample
  /// lands, so any ideal height that depends on list content leaves the
  /// list squeezed out of the panel for the whole session.
  @Test("Default Porcelain height is the same before and after the top lists arrive")
  @MainActor
  func defaultPorcelainHeightIndependentOfListContent() {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let emptyStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary)
    let populatedStore = PreviewFixtures.makeStore()

    let emptyHeight = NSHostingView(
      rootView: PopoverView(store: emptyStore)
    ).intrinsicContentSize.height
    let populatedHeight = NSHostingView(
      rootView: PopoverView(store: populatedStore)
    ).intrinsicContentSize.height

    #expect(emptyHeight == populatedHeight)
    #expect(populatedHeight > 600)
  }

  @Test("Classic compact height is independent of list content")
  @MainActor
  func classicCompactHeightIndependentOfListContent() {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let emptyStore = MonitorStore.preview(
      cpuGroups: [],
      memoryGroups: [],
      summary: emptySummary,
      usesPorcelainAppearance: false
    )
    let populatedStore = PreviewFixtures.makeStore(usesPorcelainAppearance: false)

    let emptyHeight = NSHostingView(
      rootView: PopoverView(store: emptyStore)
    ).intrinsicContentSize.height
    let populatedHeight = NSHostingView(
      rootView: PopoverView(store: populatedStore)
    ).intrinsicContentSize.height

    #expect(emptyHeight == populatedHeight)
    #expect(populatedHeight > 250)
  }

  /// The affordance replaces the value text only under hover, so its
  /// presence in the hierarchy must never move layout: capability on and
  /// off must produce identical intrinsic sizes.
  @Test("Quit capability does not change classic popover size")
  @MainActor
  func classicCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore(usesPorcelainAppearance: false)
    let gatedOn = PreviewFixtures.makeStore(
      usesPorcelainAppearance: false, canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }

  @Test("Classic ports pane height matches the metric panes, all states")
  @MainActor
  func classicPortsPaneHeightInvariant() {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let emptyStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: false, portGroups: [])
    let unavailableStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: false, portGroups: nil)
    let populatedStore = PreviewFixtures.makeStore(usesPorcelainAppearance: false)

    let metricHeight = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .cpu)
    ).intrinsicContentSize.height
    let portsEmpty = NSHostingView(
      rootView: PopoverView(store: emptyStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsUnavailable = NSHostingView(
      rootView: PopoverView(store: unavailableStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsPopulated = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .ports)
    ).intrinsicContentSize.height

    #expect(portsEmpty == metricHeight)
    #expect(portsUnavailable == metricHeight)
    #expect(portsPopulated == metricHeight)
  }

  @Test("Porcelain ports pane height matches the metric panes, all states")
  @MainActor
  func porcelainPortsPaneHeightInvariant() {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let emptyStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary, portGroups: [])
    let unavailableStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary, portGroups: nil)
    let populatedStore = PreviewFixtures.makeStore()

    let metricHeight = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .cpu)
    ).intrinsicContentSize.height
    let portsEmpty = NSHostingView(
      rootView: PopoverView(store: emptyStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsUnavailable = NSHostingView(
      rootView: PopoverView(store: unavailableStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsPopulated = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .ports)
    ).intrinsicContentSize.height

    #expect(portsEmpty == metricHeight)
    #expect(portsUnavailable == metricHeight)
    #expect(portsPopulated == metricHeight)
  }

  @Test("Quit capability does not change Porcelain popover size")
  @MainActor
  func porcelainCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore()
    let gatedOn = PreviewFixtures.makeStore(canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }

  @Test("Quit capability does not change classic ports popover size")
  @MainActor
  func classicPortsCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore(usesPorcelainAppearance: false)
    let gatedOn = PreviewFixtures.makeStore(
      usesPorcelainAppearance: false, canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff, initialTab: .ports)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn, initialTab: .ports)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }

  @Test("Quit capability does not change Porcelain ports popover size")
  @MainActor
  func porcelainPortsCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore()
    let gatedOn = PreviewFixtures.makeStore(canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff, initialTab: .ports)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn, initialTab: .ports)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }

  /// The pressure badge renders in every state, so a nil reading and a
  /// critical reading with swap in use must produce identical sizes.
  @Test("Memory pressure state does not change classic popover size")
  @MainActor
  func classicPressureDoesNotChangeSize() {
    let plain = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [],
      summary: SystemSummary(cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0),
      usesPorcelainAppearance: false)
    let pressured = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [],
      summary: SystemSummary(
        cpuPercent: 34.2, memoryUsedBytes: 12_800_000_000, memoryTotalBytes: 36_000_000_000,
        memoryPressure: .critical, swapUsedBytes: 3_000_000_000),
      usesPorcelainAppearance: false)

    let plainSize = NSHostingView(rootView: PopoverView(store: plain)).intrinsicContentSize
    let pressuredSize = NSHostingView(rootView: PopoverView(store: pressured)).intrinsicContentSize

    #expect(plainSize == pressuredSize)
  }

  @Test("Memory pressure state does not change Porcelain popover size")
  @MainActor
  func porcelainPressureDoesNotChangeSize() {
    let plain = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [],
      summary: SystemSummary(cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0))
    let pressured = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [],
      summary: SystemSummary(
        cpuPercent: 34.2, memoryUsedBytes: 12_800_000_000, memoryTotalBytes: 36_000_000_000,
        memoryPressure: .critical, swapUsedBytes: 3_000_000_000))

    let plainSize = NSHostingView(rootView: PopoverView(store: plain)).intrinsicContentSize
    let pressuredSize = NSHostingView(rootView: PopoverView(store: pressured)).intrinsicContentSize

    #expect(plainSize == pressuredSize)
  }

  @MainActor
  private func size(_ store: MonitorStore, _ tab: PopoverTab) -> CGSize {
    NSHostingView(rootView: PopoverView(store: store, initialTab: tab)).intrinsicContentSize
  }

  @Test("Every tab opens at the same size", arguments: [true, false])
  @MainActor
  func everyTabSameSize(usesPorcelain: Bool) {
    let store = PreviewFixtures.makeStore(usesPorcelainAppearance: usesPorcelain)
    let reference = size(store, .cpu)

    for tab in PopoverTab.allCases {
      #expect(size(store, tab) == reference, "\(tab.rawValue)")
    }
    #expect(reference.width == (usesPorcelain ? 460 : 340))
  }

  /// The hardware panes have more states than a ranking: no GPU, a GPU
  /// whose app figures are still being measured, an idle GPU, drives
  /// with and without the Direct edition's health rows. None may move
  /// the popover's size.
  @Test("GPU and Drives panes keep the metric pane's size in every state", arguments: [true, false])
  @MainActor
  func hardwarePanesKeepSize(usesPorcelain: Bool) {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let unavailable = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: usesPorcelain)
    let measuring = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: usesPorcelain, gpu: PreviewFixtures.gpuSample, gpuApps: nil,
      volumes: PreviewFixtures.volumes)
    let idle = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: usesPorcelain, gpu: PreviewFixtures.gpuSample, gpuApps: [],
      volumes: PreviewFixtures.volumes)
    let populated = PreviewFixtures.makeStore(usesPorcelainAppearance: usesPorcelain)
    let withHealth = PreviewFixtures.makeStore(
      usesPorcelainAppearance: usesPorcelain, includesDriveHealth: true)

    let reference = size(populated, .cpu)
    for store in [unavailable, measuring, idle, populated, withHealth] {
      #expect(size(store, .gpu) == reference)
      #expect(size(store, .drives) == reference)
    }
  }

  @Test("A store that has not sampled yet opens the hardware panes at the same size", arguments: [true, false])
  @MainActor
  func waitingPanesKeepSize(usesPorcelain: Bool) throws {
    let suiteName = "com.vinnycarpenter.SystemHeadroom.layout-tests"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let waiting = MonitorStore(
      defaults: defaults, capability: .sandboxed,
      terminator: ProcessTerminator(
        runningApplication: { _ in nil },
        currentStartIdentity: { _ in nil },
        sendSignal: { _, _ in 0 }),
      alertDelivery: NoOpAlertDelivery())
    waiting.usesPorcelainAppearance = usesPorcelain
    #expect(waiting.lastUpdated == nil)

    let reference = size(
      PreviewFixtures.makeStore(usesPorcelainAppearance: usesPorcelain), .cpu)
    #expect(size(waiting, .gpu) == reference)
    #expect(size(waiting, .drives) == reference)
  }

  @Test("Quit capability does not change the GPU pane's size", arguments: [true, false])
  @MainActor
  func gpuCapabilityDoesNotChangeSize(usesPorcelain: Bool) {
    let gatedOff = PreviewFixtures.makeStore(usesPorcelainAppearance: usesPorcelain)
    let gatedOn = PreviewFixtures.makeStore(
      usesPorcelainAppearance: usesPorcelain, canTerminate: true)

    #expect(size(gatedOff, .gpu) == size(gatedOn, .gpu))
  }
}
