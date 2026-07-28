import Foundation
import Testing

@testable import MacHeadroom

@Suite("App identity")
struct AppIdentityTests {
  @Test("Resolves the Mac Headroom display name from the app bundle")
  func resolvesDisplayName() {
    #expect(AppIdentity.displayName == "Mac Headroom")
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

    #expect(short == "1.0")
    #expect(build == "8")
    #expect(copyright == "Copyright © 2026 Vinny Carpenter")
  }

  @Test("Publishes stable website and privacy policy destinations")
  func supportDestinations() {
    #expect(AppIdentity.websiteURL.absoluteString == "https://www.macheadroom.com/")
    #expect(AppIdentity.privacyPolicyURL.absoluteString == "https://www.macheadroom.com/#privacy")
  }

  @Test("Declares that the app uses no non-exempt encryption")
  func declaresNoNonExemptEncryption() throws {
    let usesNonExemptEncryption = try #require(
      Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool)
    #expect(usesNonExemptEncryption == false)
  }
}
