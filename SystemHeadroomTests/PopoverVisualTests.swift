import AppKit
import SwiftUI
import Testing

@testable import SystemHeadroom

@Suite("Popover visual rendering")
struct PopoverVisualTests {
  @Test("Default Porcelain Native appearance renders CPU and memory fixtures")
  @MainActor
  func porcelainNativeRendersFixtures() throws {
    let fixtures: [(name: String, tab: PopoverTab, scheme: ColorScheme)] = [
      ("cpu-light", .cpu, .light),
      ("memory-light", .memory, .light),
      ("cpu-dark", .cpu, .dark),
      ("memory-dark", .memory, .dark),
      ("ports-light", .ports, .light),
      ("ports-dark", .ports, .dark),
    ]

    for fixture in fixtures {
      let store = PreviewFixtures.makeStore()
      let hosting = NSHostingView(
        rootView: PopoverView(store: store, initialTab: fixture.tab)
          .environment(\.colorScheme, fixture.scheme)
      )

      let size = hosting.intrinsicContentSize
      #expect(size.width >= 460)
      #expect(size.height > 600)

      hosting.frame = CGRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()

      let scale: CGFloat = 2
      let bitmap = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: Int(size.width * scale),
          pixelsHigh: Int(size.height * scale),
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        )
      )
      bitmap.size = size
      hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
      let data = try #require(
        bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
      )
      #expect(data.count > 40_000)

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SystemHeadroom-Porcelain-\(fixture.name)@2x.png")
      try data.write(to: url)
      print("UI_RENDER \(fixture.name) \(url.path)")
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
      .appendingPathComponent("SystemHeadroom-Settings.png")
    try data.write(to: url)
    print("UI_RENDER settings \(url.path)")
  }

  @Test("Configured App Store settings render the Direct edition entry point")
  @MainActor
  func settingsRendersDirectEditionEntryPoint() throws {
    let endpoint = try #require(URL(string: "https://claim.example.com/v1/claims"))
    let store = PreviewFixtures.makeStore()
    let hosting = NSHostingView(
      rootView: ZStack {
        Color(nsColor: .windowBackgroundColor)
        SettingsView(store: store, directEditionClaimURL: endpoint)
      }
      .environment(\.colorScheme, .light)
    )

    let size = hosting.fittingSize
    #expect(size.width >= 440)
    #expect(size.height > 260)

    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try #require(
      hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
    )
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(data.count > 10_000)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SystemHeadroom-Settings-Direct.png")
    try data.write(to: url)
    print("UI_RENDER settings-direct \(url.path)")
  }

  @Test("About renders release identity and support links")
  @MainActor
  func aboutRendersReleaseIdentity() throws {
    let hosting = NSHostingView(
      rootView: ZStack {
        Color(nsColor: .windowBackgroundColor)
        AboutView()
      }
      .environment(\.colorScheme, .light)
    )

    let size = hosting.fittingSize
    #expect(size.width >= 440)
    #expect(size.height > 160)

    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try #require(
      hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
    )
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(data.count > 10_000)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SystemHeadroom-About.png")
    try data.write(to: url)
    print("UI_RENDER about \(url.path)")
  }

  @Test("Help renders the menu-bar workflow and sandbox guidance")
  @MainActor
  func helpRendersWorkflowAndSandboxGuidance() throws {
    let store = PreviewFixtures.makeStore()
    let hosting = NSHostingView(
      rootView: ZStack {
        Color(nsColor: .windowBackgroundColor)
        HelpView(store: store)
      }
      .environment(\.colorScheme, .light)
    )

    let size = hosting.fittingSize
    #expect(size.width >= 440)
    #expect(size.height >= 500)

    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try #require(
      hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
    )
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(data.count > 10_000)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SystemHeadroom-Help.png")
    try data.write(to: url)
    print("UI_RENDER help \(url.path)")
  }

  @Test("Configured App Store Help renders the Direct edition explanation")
  @MainActor
  func helpRendersDirectEditionExplanation() throws {
    let endpoint = try #require(URL(string: "https://claim.example.com/v1/claims"))
    let store = PreviewFixtures.makeStore()
    let hosting = NSHostingView(
      rootView: ZStack {
        Color(nsColor: .windowBackgroundColor)
        HelpView(
          store: store,
          directEditionClaimURL: endpoint,
          requestedSection: .directEdition
        )
      }
      .environment(\.colorScheme, .light)
    )

    let size = hosting.fittingSize
    #expect(size.width >= 440)
    #expect(size.height >= 500)

    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try #require(
      hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
    )
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(data.count > 10_000)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("SystemHeadroom-Help-Direct.png")
    try data.write(to: url)
    print("UI_RENDER help-direct \(url.path)")
  }

  @Test("About hides Check for Updates outside a Direct build with an updater")
  @MainActor
  func aboutHidesUpdateButtonWhenGated() throws {
    struct FakeUpdater: UpdaterClient {
      var canCheckForUpdates: Bool { true }
      func checkForUpdates() {}
    }

    // The gate needs both conditions; each alone must render identically to
    // the plain App Store About tab.
    let baseline = NSHostingView(rootView: AboutView()).fittingSize
    let updaterOnly = NSHostingView(
      rootView: AboutView(updater: FakeUpdater(), capability: .sandboxed)
    ).fittingSize
    let capabilityOnly = NSHostingView(
      rootView: AboutView(updater: nil, capability: .available)
    ).fittingSize
    #expect(updaterOnly == baseline)
    #expect(capabilityOnly == baseline)

    let direct = NSHostingView(
      rootView: AboutView(updater: FakeUpdater(), capability: .available)
    ).fittingSize
    #expect(direct.height > baseline.height)
  }
}
