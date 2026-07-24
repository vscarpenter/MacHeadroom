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
  @Test("Ideal height is the same before and after the top lists arrive")
  @MainActor
  func idealHeightIndependentOfListContent() {
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
  }

  @Test("The list keeps real height at the window's ideal size when groups exist")
  @MainActor
  func listKeepsIdealHeight() {
    let store = PreviewFixtures.makeStore()
    let hosting = NSHostingView(rootView: PopoverView(store: store))

    let idealHeight = hosting.intrinsicContentSize.height

    // Header, dividers, and footer alone measure about 150 points. The four
    // fixture rows need roughly 40 points each, so anything under 250 means
    // the list region collapsed instead of showing rows.
    #expect(idealHeight > 250)
  }
}
