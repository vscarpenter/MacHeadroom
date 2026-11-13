import Testing

@testable import SystemHeadroom

@Suite("Disk activity delta")
struct DiskActivityTests {
  private static let second: UInt64 = 1_000_000_000

  @Test("No previous counters means no reading yet")
  func primingTick() {
    let activity = DiskActivityDelta.activity(
      previous: nil, current: DiskCounters(readBytes: 5, writeBytes: 5),
      wallTimeNanoseconds: Self.second)

    #expect(activity == nil)
  }

  @Test("Throughput is the byte delta over wall time")
  func measuredDelta() throws {
    // The sandboxed probe's 48 MB write, as the driver counted it.
    let activity = try #require(
      DiskActivityDelta.activity(
        previous: DiskCounters(readBytes: 1_072_556_404_736, writeBytes: 531_727_814_656),
        current: DiskCounters(readBytes: 1_072_556_625_920, writeBytes: 531_779_129_344),
        wallTimeNanoseconds: Self.second))

    #expect(activity.readBytesPerSecond == 221_184)
    #expect(activity.writeBytesPerSecond == 51_314_688)
  }

  @Test("Half the wall time doubles the rate")
  func scalesWithWallTime() throws {
    let activity = try #require(
      DiskActivityDelta.activity(
        previous: DiskCounters(readBytes: 0, writeBytes: 0),
        current: DiskCounters(readBytes: 1_000, writeBytes: 4_000),
        wallTimeNanoseconds: Self.second / 2))

    #expect(activity.readBytesPerSecond == 2_000)
    #expect(activity.writeBytesPerSecond == 8_000)
  }

  @Test("A counter that moved backward means a different disk, so no reading")
  func backwardCounter() {
    let previous = DiskCounters(readBytes: 900, writeBytes: 900)

    #expect(
      DiskActivityDelta.activity(
        previous: previous, current: DiskCounters(readBytes: 100, writeBytes: 950),
        wallTimeNanoseconds: Self.second) == nil)
    #expect(
      DiskActivityDelta.activity(
        previous: previous, current: DiskCounters(readBytes: 950, writeBytes: 100),
        wallTimeNanoseconds: Self.second) == nil)
  }

  @Test("Zero wall time yields nothing rather than a division by zero")
  func zeroWallTime() {
    let activity = DiskActivityDelta.activity(
      previous: DiskCounters(readBytes: 0, writeBytes: 0),
      current: DiskCounters(readBytes: 1, writeBytes: 1), wallTimeNanoseconds: 0)

    #expect(activity == nil)
  }
}
