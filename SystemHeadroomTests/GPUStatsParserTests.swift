import Foundation
import Testing

@testable import SystemHeadroom

/// Fixtures mirror the registry shapes measured on an M4 Pro
/// (Evidence/gpu-drives-spike/): the accelerator's own properties, and
/// one dictionary per child user client.
@Suite("GPU stats parser")
struct GPUStatsParserTests {
  private static func accelerator(
    statistics: [String: Any] = [
      "Device Utilization %": 27,
      "Renderer Utilization %": 27,
      "Tiler Utilization %": 12,
      "Alloc system memory": 5_182_881_792,
      "In use system memory": 1_850_884_096,
    ],
    model: Any = "Apple M4 Pro"
  ) -> [String: Any] {
    ["PerformanceStatistics": statistics, "model": model, "gpu-core-count": 20]
  }

  private static func client(_ creator: String, times: [UInt64]) -> [String: Any] {
    let usage: [[String: Any]] = times.map {
      ["API": "Metal", "accumulatedGPUTime": $0, "lastSubmittedTime": 1]
    }
    return ["IOUserClientCreator": creator, "AppUsage": usage]
  }

  @Test("A full reading carries utilization, memory, model, and core count")
  func fullReading() throws {
    let reading = try #require(
      GPUStatsParser.reading(accelerator: Self.accelerator(), clients: []))

    #expect(reading.deviceUtilizationPercent == 27)
    #expect(reading.rendererUtilizationPercent == 27)
    #expect(reading.tilerUtilizationPercent == 12)
    #expect(reading.allocatedMemoryBytes == 5_182_881_792)
    #expect(reading.inUseMemoryBytes == 1_850_884_096)
    #expect(reading.model == "Apple M4 Pro")
    #expect(reading.coreCount == 20)
    #expect(reading.gpuTimeNanosecondsByPID.isEmpty)
  }

  @Test("No device utilization means no reading")
  func missingUtilization() {
    let noKey = Self.accelerator(statistics: ["Tiler Utilization %": 12])
    #expect(GPUStatsParser.reading(accelerator: noKey, clients: []) == nil)
    #expect(GPUStatsParser.reading(accelerator: [:], clients: []) == nil)

    let wrongType = Self.accelerator(statistics: ["Device Utilization %": "busy"])
    #expect(GPUStatsParser.reading(accelerator: wrongType, clients: []) == nil)
  }

  @Test("Optional counters that are missing stay nil")
  func missingOptionalCounters() throws {
    let sparse = Self.accelerator(statistics: ["Device Utilization %": 3])
    let reading = try #require(GPUStatsParser.reading(accelerator: sparse, clients: []))

    #expect(reading.deviceUtilizationPercent == 3)
    #expect(reading.rendererUtilizationPercent == nil)
    #expect(reading.allocatedMemoryBytes == nil)
    #expect(reading.inUseMemoryBytes == nil)
  }

  @Test("A model stored as NUL-terminated data decodes to text")
  func modelAsData() throws {
    let data = Data("AMD Radeon Pro 5500M".utf8) + Data([0])
    let reading = try #require(
      GPUStatsParser.reading(accelerator: Self.accelerator(model: data), clients: []))

    #expect(reading.model == "AMD Radeon Pro 5500M")
  }

  @Test("GPU time sums across usage entries and across one pid's clients")
  func sumsPerPID() throws {
    let clients = [
      Self.client("pid 653, WindowServer", times: [6_879_279_887_083, 122_007_416, 0]),
      Self.client("pid 653, WindowServer", times: [142_360_541]),
      Self.client("pid 9001, Final Cut Pro", times: [5_000]),
    ]
    let reading = try #require(
      GPUStatsParser.reading(accelerator: Self.accelerator(), clients: clients))

    #expect(
      reading.gpuTimeNanosecondsByPID[653] == 6_879_279_887_083 + 122_007_416 + 142_360_541)
    #expect(reading.gpuTimeNanosecondsByPID[9001] == 5_000)
    #expect(reading.clientNamesByPID[653] == "WindowServer")
    #expect(reading.clientNamesByPID[9001] == "Final Cut Pro")
  }

  @Test("A client with an empty usage list counts as zero; one with none is skipped")
  func emptyAndMissingUsage() throws {
    let clients: [[String: Any]] = [
      Self.client("pid 783, storagekitd", times: []),
      ["IOUserClientCreator": "pid 800, legacy"],
      ["AppUsage": [["accumulatedGPUTime": 9]]],
      Self.client("no pid here", times: [9]),
    ]
    let reading = try #require(
      GPUStatsParser.reading(accelerator: Self.accelerator(), clients: clients))

    #expect(reading.gpuTimeNanosecondsByPID == [783: 0])
    #expect(reading.clientNamesByPID == [783: "storagekitd"])
  }

  @Test("Creator strings parse to a pid and a name")
  func parseCreator() throws {
    let windowServer = try #require(GPUStatsParser.parseCreator("pid 653, WindowServer"))
    #expect(windowServer.pid == 653)
    #expect(windowServer.name == "WindowServer")

    let comma = try #require(GPUStatsParser.parseCreator("pid 5, Render, Inc"))
    #expect(comma.name == "Render, Inc")
  }

  @Test(
    "Malformed creator strings are rejected, not trapped",
    arguments: ["pid x, y", "653", "pid 99999999999, z", "pid 0, kernel", "pid -4, odd", ""])
  func rejectsMalformedCreator(creator: String) {
    #expect(GPUStatsParser.parseCreator(creator) == nil)
  }
}

@Suite("GPU delta")
struct GPUDeltaTests {
  @Test("Percent is the counter delta over wall time")
  func measuredDelta() throws {
    // WindowServer between the two probe runs: 187,564,500 ns of GPU
    // time across 13,649,697,292 ns of wall time.
    let percents = GPUDelta.percents(
      previous: [653: 6_879_279_887_083],
      current: [653: 6_879_467_451_583],
      wallTimeNanoseconds: 13_649_697_292,
      identityChanged: { _ in false })

    let percent = try #require(percents[653])
    #expect(abs(percent - 1.374) < 0.001)
  }

  @Test("A pid with no previous counter has no percent yet")
  func primingTick() {
    let percents = GPUDelta.percents(
      previous: [:], current: [653: 10], wallTimeNanoseconds: 1_000_000_000,
      identityChanged: { _ in false })

    #expect(percents.isEmpty)
  }

  @Test("A counter that moved backward yields no percent")
  func backwardCounter() {
    let percents = GPUDelta.percents(
      previous: [653: 500, 700: 100], current: [653: 400, 700: 100],
      wallTimeNanoseconds: 1_000_000_000,
      identityChanged: { _ in false })

    #expect(percents == [700: 0])
  }

  @Test("Zero wall time yields nothing rather than a division by zero")
  func zeroWallTime() {
    let percents = GPUDelta.percents(
      previous: [653: 1], current: [653: 2], wallTimeNanoseconds: 0,
      identityChanged: { _ in false })

    #expect(percents.isEmpty)
  }

  @Test("A reused pid is not compared against the old process's counter")
  func identityChange() {
    let percents = GPUDelta.percents(
      previous: [653: 1, 700: 1], current: [653: 500_000_001, 700: 500_000_001],
      wallTimeNanoseconds: 1_000_000_000,
      identityChanged: { $0 == 653 })

    #expect(percents == [700: 50])
  }
}
