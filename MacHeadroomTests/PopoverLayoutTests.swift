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
}
