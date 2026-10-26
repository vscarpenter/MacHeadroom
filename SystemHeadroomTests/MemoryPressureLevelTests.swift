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
