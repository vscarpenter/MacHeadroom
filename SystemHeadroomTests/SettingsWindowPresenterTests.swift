import Testing

@testable import SystemHeadroom

@Suite("Settings window presentation")
struct SettingsWindowPresenterTests {
  /// The app is LSUIElement and the menu bar panel never makes it frontmost,
  /// so opening the Settings scene without activating leaves the window
  /// buried behind the app the user was in. Activating is the fix; doing it
  /// before the window exists raises nothing, so the order is part of the
  /// contract.
  @Test("Presenting opens the settings scene, then activates the app")
  @MainActor
  func opensThenActivates() {
    var calls: [String] = []

    SettingsWindowPresenter.present(
      open: { calls.append("open") },
      activate: { calls.append("activate") }
    )

    #expect(calls == ["open", "activate"])
  }
}
