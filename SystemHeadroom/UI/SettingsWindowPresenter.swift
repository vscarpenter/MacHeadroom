import AppKit

/// Opening the Settings scene is not enough to show it. The app is
/// `LSUIElement`, and the MenuBarExtra panel is a non-activating window, so
/// the app is never frontmost: the panel dismisses on the tap, the app goes
/// inactive, and the Settings window is left ordered behind whichever app the
/// user was actually in. Measured on macOS 26.6.2 with an LSUIElement harness
/// reproducing the panel dismissal — rank among on-screen normal windows:
///
///     open only                  rank 1, key = false   (the reported bug)
///     open, then NSApp.activate  rank 0, key = true
///
/// Order matters: activating before the window exists has nothing to raise.
@MainActor
enum SettingsWindowPresenter {
  static func present(
    open: () -> Void,
    activate: () -> Void = { NSApp.activate() }
  ) {
    open()
    activate()
  }
}
