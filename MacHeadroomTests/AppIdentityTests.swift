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
}
