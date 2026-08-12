import Testing

@testable import SystemHeadroom

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

  @Test("CPU percents under 10 keep one decimal so light usage stays visible")
  func smallPercentsShowTenths() {
    #expect(ValueFormatting.percent(0.44) == "0.4%")
    #expect(ValueFormatting.percent(7.06) == "7.1%")
    #expect(ValueFormatting.percent(0) == "0.0%")
    // 9.96 rounds to 10.0 at one decimal, so it belongs to the integer branch.
    #expect(ValueFormatting.percent(9.96) == "10%")
  }

  @Test("CPU percents of 10 and above stay whole numbers")
  func largePercentsStayIntegers() {
    #expect(ValueFormatting.percent(12.4) == "12%")
    #expect(ValueFormatting.percent(99.5) == "100%")
    #expect(ValueFormatting.percent(nil) == "—")
  }
}
