import Testing

@testable import MacHeadroom

@Suite("Headroom presentation")
struct HeadroomPresentationTests {
  @Test("CPU headroom is the clamped remainder of capacity")
  func cpuHeadroom() {
    #expect(ValueFormatting.headroomPercent(used: 13, capacity: 100) == 87)
    #expect(ValueFormatting.headroomPercent(used: 125, capacity: 100) == 0)
    #expect(ValueFormatting.headroomPercent(used: nil, capacity: 100) == nil)
  }

  @Test("Memory headroom handles total memory boundaries")
  func memoryHeadroom() {
    #expect(ValueFormatting.headroomPercent(used: 25.94, capacity: 48) == 46)
    #expect(ValueFormatting.headroomPercent(used: 0, capacity: 0) == nil)
    #expect(ValueFormatting.headroomPercent(used: 60, capacity: 48) == 0)
  }
}
