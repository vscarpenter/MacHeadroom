import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Memory pressure level")
struct MemoryPressureLevelTests {
  @Test(
    "Raw sysctl levels map to the three states",
    arguments: [
      (Int32(1), MemoryPressureLevel.normal),
      (Int32(2), MemoryPressureLevel.warning),
      (Int32(4), MemoryPressureLevel.critical),
    ])
  func mapping(raw: Int32, expected: MemoryPressureLevel) {
    #expect(MemoryPressureLevel(rawPressure: raw) == expected)
  }

  @Test("Unknown raw levels map to nil", arguments: [Int32(0), 3, 5, -1])
  func unknown(raw: Int32) {
    #expect(MemoryPressureLevel(rawPressure: raw) == nil)
  }

  @Test("Display names")
  func displayNames() {
    #expect(MemoryPressureLevel.normal.displayName == "Normal")
    #expect(MemoryPressureLevel.warning.displayName == "Warning")
    #expect(MemoryPressureLevel.critical.displayName == "Critical")
  }
}

@Suite("Memory pressure badge text")
struct MemoryPressureBadgeTextTests {
  @Test("Level text names the state, Unknown for nil")
  func levelText() {
    #expect(MemoryPressureBadge.levelText(nil) == "Unknown")
    #expect(MemoryPressureBadge.levelText(.warning) == "Warning")
  }

  @Test("Swap text formats bytes, dash for nil")
  func swapText() {
    #expect(MemoryPressureBadge.swapText(nil) == "Swap —")
    #expect(
      MemoryPressureBadge.swapText(1_200_000_000)
        == "Swap \(ValueFormatting.bytes(1_200_000_000))")
  }

  @Test("Accessibility label reads the state and the swap figure")
  func accessibilityLabel() {
    #expect(
      MemoryPressureBadge.accessibilityLabel(level: .normal, swapUsedBytes: 1_200_000_000)
        == "Memory pressure normal, \(ValueFormatting.bytes(1_200_000_000)) of swap in use")
    #expect(
      MemoryPressureBadge.accessibilityLabel(level: nil, swapUsedBytes: nil)
        == "Memory pressure unknown, swap unknown")
  }
}
