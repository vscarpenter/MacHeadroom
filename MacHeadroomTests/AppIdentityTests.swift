import Testing

@testable import MacHeadroom

@Suite("App identity")
struct AppIdentityTests {
  @Test("Resolves the Mac Headroom display name from the app bundle")
  func resolvesDisplayName() {
    #expect(AppIdentity.displayName == "Mac Headroom")
  }
}
