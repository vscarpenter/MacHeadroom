import AppKit
import SwiftUI
import Testing

@testable import MacHeadroom

@Suite("Popover visual rendering")
struct PopoverVisualTests {
  @Test("Max Headroom mode renders light and dark fixtures")
  @MainActor
  func maxHeadroomModeRendersFixtures() throws {
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
      let store = PreviewFixtures.makeStore(maxHeadroomModeEnabled: true)
      let hosting = NSHostingView(
        rootView: PopoverView(store: store)
          .environment(\.colorScheme, scheme)
      )

      let size = hosting.fittingSize
      #expect(size.width >= 340)
      #expect(size.height > 350)

      hosting.frame = CGRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()

      let bitmap = try #require(
        hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
      )
      hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      #expect(data.count > 10_000)

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacHeadroom-Max-\(name).png")
      try data.write(to: url)
      print("UI_RENDER \(name) \(url.path)")
    }
  }

  @Test("Settings renders the appearance preference")
  @MainActor
  func settingsRendersAppearancePreference() throws {
    let store = PreviewFixtures.makeStore()
    let hosting = NSHostingView(
      rootView: ZStack {
        Color(nsColor: .windowBackgroundColor)
        SettingsView(store: store)
      }
      .environment(\.colorScheme, .light)
    )

    let size = hosting.fittingSize
    #expect(size.width >= 440)
    #expect(size.height > 200)

    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try #require(
      hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
    )
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(data.count > 10_000)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacHeadroom-Settings.png")
    try data.write(to: url)
    print("UI_RENDER settings \(url.path)")
  }
}
