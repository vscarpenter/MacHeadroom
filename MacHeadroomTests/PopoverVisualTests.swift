import AppKit
import SwiftUI
import Testing

@testable import MacHeadroom

@Suite("Popover visual rendering")
struct PopoverVisualTests {
  @Test("Default Porcelain Native appearance renders light and dark fixtures")
  @MainActor
  func porcelainNativeRendersFixtures() throws {
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
      let store = PreviewFixtures.makeStore()
      let hosting = NSHostingView(
        rootView: PopoverView(store: store)
          .environment(\.colorScheme, scheme)
      )

      let size = hosting.intrinsicContentSize
      #expect(size.width >= 460)
      #expect(size.height > 600)

      hosting.frame = CGRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()

      let bitmap = try #require(
        hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
      )
      hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      #expect(data.count > 10_000)

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacHeadroom-Porcelain-\(name).png")
      try data.write(to: url)
      print("UI_RENDER \(name) \(url.path)")
    }
  }

  @Test("Classic compact appearance remains available")
  @MainActor
  func classicCompactAppearanceRenders() throws {
    let store = PreviewFixtures.makeStore(usesPorcelainAppearance: false)
    let hosting = NSHostingView(
      rootView: PopoverView(store: store)
        .environment(\.colorScheme, .light)
    )

    let size = hosting.intrinsicContentSize
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
