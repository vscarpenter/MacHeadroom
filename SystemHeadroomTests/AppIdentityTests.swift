import Foundation
import Testing

@testable import SystemHeadroom

@Suite("App identity")
struct AppIdentityTests {
  @Test("Resolves the System Headroom display name from the app bundle")
  func resolvesDisplayName() {
    #expect(AppIdentity.displayName == "System Headroom")
  }

  @Test("Version description carries the bundle's marketing version and build")
  func versionDescription() throws {
    let short = try #require(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    let build = try #require(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    #expect(AppIdentity.versionDescription == "Version \(short) (\(build))")
  }

  @Test("Release identity matches the App Store submission")
  func releaseIdentity() throws {
    let short = try #require(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    let build = try #require(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    let copyright = try #require(
      Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)

    #expect(short == "1.1")
    #expect(build == "12")
    #expect(copyright == "Copyright © 2026 Vinny Carpenter")
  }

  @Test("Publishes stable website and privacy policy destinations")
  func supportDestinations() {
    #expect(AppIdentity.websiteURL.absoluteString == "https://www.macheadroom.com/")
    #expect(AppIdentity.privacyPolicyURL.absoluteString == "https://www.macheadroom.com/privacy.html")
  }

  @Test("Declares that the app uses no non-exempt encryption")
  func declaresNoNonExemptEncryption() throws {
    let usesNonExemptEncryption = try #require(
      Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool)
    #expect(usesNonExemptEncryption == false)
  }
}

@Suite("Updater gating")
struct UpdaterGatingTests {
  @Test("Update UI appears only in a Direct build that has an updater")
  func presentationGate() {
    #expect(UpdaterPresentation.isVisible(capability: .available, hasUpdater: true))
    #expect(!UpdaterPresentation.isVisible(capability: .available, hasUpdater: false))
    #expect(!UpdaterPresentation.isVisible(capability: .sandboxed, hasUpdater: true))
    #expect(!UpdaterPresentation.isVisible(capability: .sandboxed, hasUpdater: false))
  }

  @Test("The sandboxed build vends no updater")
  @MainActor
  func sandboxedBuildHasNoUpdater() {
    // The test host is the sandboxed App Store flavor, which must compile
    // the null updater path.
    #expect(UpdaterProvider.shared == nil)
  }

  @Test("App Store binary and bundle contain no Sparkle")
  func appStoreBuildHasNoSparkle() throws {
    #expect(NSClassFromString("SPUStandardUpdaterController") == nil)

    let frameworksURL = try #require(Bundle.main.privateFrameworksURL)
    let frameworkNames = ((try? FileManager.default.contentsOfDirectory(
      at: frameworksURL, includingPropertiesForKeys: nil
    )) ?? []).map(\.lastPathComponent)
    #expect(!frameworkNames.contains("Sparkle.framework"))
  }
}
