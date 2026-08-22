import Foundation

#if DIRECT_EDITION
  import Sparkle
#endif

/// Sparkle exists only in the Direct binary. Termination could stay
/// runtime-gated because the sandbox enforces the difference; an updater
/// cannot — Sparkle symbols inside a Mac App Store submission are an App
/// Review flag — so this is the project's one deliberate compile-time fork,
/// contained to the DIRECT_EDITION condition set by Direct.xcconfig.
@MainActor
protocol UpdaterClient {
  var canCheckForUpdates: Bool { get }
  func checkForUpdates()
}

/// Mirrors DirectEditionAccessPresentation: a pure, test-pinned gate that
/// keeps update UI out of the sandboxed App Store build.
enum UpdaterPresentation {
  static func isVisible(capability: TerminationCapability, hasUpdater: Bool) -> Bool {
    capability == .available && hasUpdater
  }
}

#if DIRECT_EDITION
  @MainActor
  final class SparkleUpdaterClient: UpdaterClient {
    private let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
      controller.checkForUpdates(nil)
    }
  }

  @MainActor
  func makeUpdaterClient() -> UpdaterClient? {
    SparkleUpdaterClient()
  }
#else
  @MainActor
  func makeUpdaterClient() -> UpdaterClient? {
    nil
  }
#endif

/// One updater for the app's lifetime; Sparkle's controller schedules
/// background checks from init, so it must not be recreated per view.
@MainActor
enum UpdaterProvider {
  static let shared: UpdaterClient? = makeUpdaterClient()
}
