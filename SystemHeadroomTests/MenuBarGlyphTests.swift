import AppKit
import Testing

@testable import SystemHeadroom

@Suite("Menu bar glyph")
struct MenuBarGlyphTests {
  /// The brand glyph must exist in the asset catalog and carry the template
  /// rendering intent, or the menu bar shows a blank or untinted image.
  @Test("The MenuBarGlyph asset loads as a template image")
  @MainActor
  func glyphLoadsAsTemplate() throws {
    let image = try #require(NSImage(named: "MenuBarGlyph"))
    #expect(image.isTemplate)
    #expect(image.size.width > 0)
  }
}
