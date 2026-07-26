import AppKit
import SwiftUI
import Testing

@testable import MacHeadroom

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
}
