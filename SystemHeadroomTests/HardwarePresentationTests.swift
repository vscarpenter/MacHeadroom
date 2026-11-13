import Foundation
import Testing

@testable import SystemHeadroom

@Suite("GPU presentation")
struct GPUPresentationTests {
  private static func gpu(
    utilization: Double = 27, renderer: Double? = 27, tiler: Double? = 12,
    allocated: UInt64? = 5_182_881_792, inUse: UInt64? = 1_850_884_096,
    model: String? = "Apple M4 Pro", cores: Int? = 20
  ) -> GPUSample {
    GPUSample(
      model: model, coreCount: cores, utilizationPercent: utilization,
      rendererPercent: renderer, tilerPercent: tiler, allocatedMemoryBytes: allocated,
      inUseMemoryBytes: inUse, processPercents: nil, processNames: [:])
  }

  @Test("Headroom is what utilization leaves, and unknown without a GPU")
  func headroom() {
    #expect(GPUPresentation.headroomPercent(Self.gpu()) == 73)
    #expect(GPUPresentation.headroomPercent(Self.gpu(utilization: 140)) == 0)
    #expect(GPUPresentation.headroomPercent(nil) == nil)
  }

  @Test("The header detail names utilization and allocated memory")
  func usageDetail() {
    #expect(
      GPUPresentation.usageDetail(Self.gpu())
        == "27% in use · \(ValueFormatting.bytes(5_182_881_792)) GPU memory")
    #expect(GPUPresentation.usageDetail(Self.gpu(allocated: nil)) == "27% in use")
    #expect(GPUPresentation.usageDetail(nil) == "GPU statistics unavailable")
  }

  @Test("Before the first sample the pane waits; after it, a missing GPU is unavailable")
  func paneState() {
    #expect(GPUPresentation.paneState(gpu: nil, hasSampled: false) == .waiting)
    #expect(GPUPresentation.paneState(gpu: nil, hasSampled: true) == .unavailable)
    #expect(GPUPresentation.paneState(gpu: Self.gpu(), hasSampled: true) == .ready)
    #expect(
      GPUPresentation.usageDetail(nil, hasSampled: false) == "Waiting for the first sample")
  }

  @Test("The utilization row carries the renderer and tiler breakdown")
  func utilizationRow() throws {
    let row = try #require(
      GPUPresentation.statRows(Self.gpu(), installedMemoryBytes: 51_539_607_552).first)

    #expect(row.id == "gpu-utilization")
    #expect(row.title == "GPU Utilization")
    #expect(row.value == "27%")
    #expect(row.subtitle == "Renderer 27% · Tiler 12%")
    #expect(row.usedFraction == 0.27)
    #expect(row.isAccented)
  }

  @Test("Without a breakdown the utilization row names the chip")
  func utilizationFallbackSubtitle() throws {
    let named = try #require(
      GPUPresentation.statRows(
        Self.gpu(renderer: nil, tiler: nil), installedMemoryBytes: 1).first)
    #expect(named.subtitle == "Apple M4 Pro · 20 cores")

    let anonymous = try #require(
      GPUPresentation.statRows(
        Self.gpu(renderer: nil, tiler: nil, model: nil, cores: nil),
        installedMemoryBytes: 1
      ).first)
    #expect(anonymous.subtitle == "Graphics processor")

    let oneCore = try #require(
      GPUPresentation.statRows(
        Self.gpu(renderer: nil, tiler: nil, model: "Test GPU", cores: 1),
        installedMemoryBytes: 1
      ).first)
    #expect(oneCore.subtitle == "Test GPU · 1 core")
  }

  @Test("A runaway utilization reading cannot overdraw the bar")
  func utilizationBarClamps() throws {
    let row = try #require(
      GPUPresentation.statRows(Self.gpu(utilization: 140), installedMemoryBytes: 1).first)
    #expect(row.usedFraction == 1)
  }

  @Test("The memory row leads with allocated memory against installed memory")
  func memoryRow() throws {
    let rows = GPUPresentation.statRows(Self.gpu(), installedMemoryBytes: 51_539_607_552)
    let row = try #require(rows.last)

    #expect(rows.count == 2)
    #expect(row.id == "gpu-memory")
    #expect(row.title == "GPU Memory")
    #expect(row.value == ValueFormatting.bytes(5_182_881_792))
    #expect(row.subtitle == "\(ValueFormatting.bytes(1_850_884_096)) in active use")
    let fraction = try #require(row.usedFraction)
    #expect(abs(fraction - 5_182_881_792.0 / 51_539_607_552.0) < 0.000_001)
    #expect(!row.isAccented)
  }

  @Test("The memory row adapts to missing counters")
  func memoryRowMissingCounters() throws {
    let noInUse = try #require(
      GPUPresentation.statRows(Self.gpu(inUse: nil), installedMemoryBytes: 1).last)
    #expect(noInUse.subtitle == "Shared with system memory")

    let noInstalled = try #require(
      GPUPresentation.statRows(Self.gpu(), installedMemoryBytes: 0).last)
    #expect(noInstalled.usedFraction == nil)

    let noAllocated = GPUPresentation.statRows(
      Self.gpu(allocated: nil), installedMemoryBytes: 1)
    #expect(noAllocated.map(\.id) == ["gpu-utilization"])
  }
}

@Suite("Drives presentation")
struct DrivesPresentationTests {
  private static let startup = VolumeSnapshot(
    mountPath: "/", name: "Macintosh HD", totalBytes: 994_662_584_320,
    freeBytes: 179_612_178_956, isStartup: true, location: .internal, medium: .solidState,
    interconnect: "Apple Fabric", formatDescription: "APFS", physicalDisk: "disk0")

  private static let external = VolumeSnapshot(
    mountPath: "/Volumes/Backup", name: "Backup", totalBytes: 8_001_352_437_760,
    freeBytes: 4_418_738_233_344, isStartup: false, location: .external,
    medium: .rotational, interconnect: "USB", formatDescription: "APFS (Case-sensitive)",
    physicalDisk: "disk6")

  private static func health(
    warning: UInt8 = 0, kelvin: UInt16 = 311, used: UInt8 = 3, disk: String? = "disk0"
  ) -> DriveHealth {
    DriveHealth(
      criticalWarning: warning, temperatureKelvin: kelvin, availableSpare: 100,
      availableSpareThreshold: 99, percentageUsed: used, physicalDisk: disk)
  }

  private static let britain = Locale(identifier: "en_GB")

  private static func rows(
    volumes: [VolumeSnapshot] = [startup, external],
    activity: [String: DiskActivity] = [:],
    health: [DriveHealth] = [],
    locale: Locale = britain
  ) -> [StatRow] {
    DrivesPresentation.rows(
      volumes: volumes, activity: activity, health: health, locale: locale)
  }

  @Test("Headroom is the startup volume's free share")
  func headroom() {
    #expect(DrivesPresentation.headroomPercent([Self.external, Self.startup]) == 18)
    #expect(DrivesPresentation.headroomPercent([Self.external]) == nil)
    #expect(DrivesPresentation.headroomPercent([]) == nil)
  }

  @Test("The header detail names used space, capacity, and where the drive sits")
  func usageDetail() {
    let used = ValueFormatting.diskBytes(994_662_584_320 - 179_612_178_956)
    let total = ValueFormatting.diskBytes(994_662_584_320)
    #expect(
      DrivesPresentation.usageDetail([Self.startup]) == "\(used) in use · \(total) internal")
    #expect(DrivesPresentation.usageDetail([]) == "Drives unavailable")
  }

  @Test("Before the first sample the pane waits; after it, no volumes is unavailable")
  func paneState() {
    #expect(DrivesPresentation.paneState(volumes: [], hasSampled: false) == .waiting)
    #expect(DrivesPresentation.paneState(volumes: [], hasSampled: true) == .unavailable)
    #expect(DrivesPresentation.paneState(volumes: [Self.startup], hasSampled: false) == .ready)
    #expect(
      DrivesPresentation.usageDetail([], hasSampled: false) == "Waiting for the first sample")
  }

  @Test("Kind lines follow location, medium, and bus")
  func kindLines() {
    let internalTotal = ValueFormatting.diskBytes(994_662_584_320)
    let externalTotal = ValueFormatting.diskBytes(8_001_352_437_760)
    #expect(DrivesPresentation.kindLine(Self.startup) == "Internal SSD · \(internalTotal) · APFS")
    #expect(DrivesPresentation.kindLine(Self.external) == "External HDD · \(externalTotal) · USB")

    let bare = VolumeSnapshot(
      mountPath: "/Volumes/X", name: "X", totalBytes: 1_000_000_000, freeBytes: 0,
      isStartup: false, location: .unknown, medium: nil, interconnect: nil,
      formatDescription: nil, physicalDisk: "disk9")
    #expect(DrivesPresentation.kindLine(bare) == "Drive · \(ValueFormatting.diskBytes(1_000_000_000))")

    let externalNoBus = VolumeSnapshot(
      mountPath: "/Volumes/Y", name: "Y", totalBytes: 1_000_000_000, freeBytes: 0,
      isStartup: false, location: .external, medium: .solidState, interconnect: nil,
      formatDescription: "ExFAT", physicalDisk: "disk10")
    #expect(
      DrivesPresentation.kindLine(externalNoBus)
        == "External SSD · \(ValueFormatting.diskBytes(1_000_000_000)) · ExFAT")
  }

  @Test("Each volume gets a row with free space and a used-share bar")
  func volumeRows() throws {
    let rows = Self.rows()
    let first = try #require(rows.first)

    #expect(first.id == "volume:/")
    #expect(first.title == "Macintosh HD")
    #expect(first.value == "\(ValueFormatting.diskBytes(179_612_178_956)) free")
    #expect(first.subtitle == DrivesPresentation.kindLine(Self.startup))
    #expect(first.symbol == "internaldrive")
    #expect(first.isAccented)
    let fraction = try #require(first.usedFraction)
    #expect(abs(fraction - 0.8194) < 0.0001)

    let second = rows[1]
    #expect(second.title == "Backup")
    #expect(second.symbol == "externaldrive")
    #expect(!second.isAccented)
  }

  @Test("Each physical disk gets one activity row, dashes until a reading exists")
  func activityRows() throws {
    let rows = Self.rows(
      activity: ["disk0": DiskActivity(readBytesPerSecond: 221_184, writeBytesPerSecond: 51_314_688)])

    let internalActivity = try #require(rows.first { $0.id == "activity:disk0" })
    #expect(internalActivity.title == "Disk Activity")
    #expect(internalActivity.subtitle == "Macintosh HD")
    #expect(internalActivity.value == "R 0.2 · W 51 MB/s")
    #expect(internalActivity.usedFraction == nil)

    let externalActivity = try #require(rows.first { $0.id == "activity:disk6" })
    #expect(externalActivity.subtitle == "Backup")
    #expect(externalActivity.value == "R — · W — MB/s")

    #expect(
      rows.map(\.id) == ["volume:/", "volume:/Volumes/Backup", "activity:disk0", "activity:disk6"])
  }

  @Test("Two volumes on one disk share an activity row; a volume with no disk gets none")
  func activityGrouping() {
    let sibling = VolumeSnapshot(
      mountPath: "/Volumes/Data", name: "Data", totalBytes: 10, freeBytes: 5,
      isStartup: false, location: .internal, medium: .solidState, interconnect: nil,
      formatDescription: "APFS", physicalDisk: "disk0")
    let orphan = VolumeSnapshot(
      mountPath: "/Volumes/Odd", name: "Odd", totalBytes: 10, freeBytes: 5,
      isStartup: false, location: .unknown, medium: nil, interconnect: nil,
      formatDescription: nil, physicalDisk: nil)

    let activity = Self.rows(volumes: [Self.startup, sibling, orphan])
      .filter { $0.id.hasPrefix("activity:") }

    #expect(activity.map(\.id) == ["activity:disk0"])
    #expect(activity.first?.subtitle == "Macintosh HD, Data")
  }

  @Test("A healthy drive reads Healthy with its wear, and the bar is wear")
  func healthyDrive() throws {
    let rows = Self.rows(health: [Self.health()])

    let health = try #require(rows.first { $0.id == "health:0" })
    #expect(health.title == "SSD Health")
    #expect(health.value == "Healthy")
    #expect(health.subtitle == "No warnings · 3% wear")
    #expect(health.usedFraction == 0.03)

    let temperature = try #require(rows.first { $0.id == "temperature:0" })
    #expect(temperature.title == "Drive Temperature")
    #expect(temperature.subtitle == "Macintosh HD")
    #expect(temperature.usedFraction == nil)
    #expect(rows.suffix(2).map(\.id) == ["health:0", "temperature:0"])
  }

  @Test("A drive that reports a warning says so")
  func warningDrive() throws {
    let health = try #require(
      Self.rows(health: [Self.health(warning: 4)]).first { $0.id == "health:0" })

    #expect(health.value == "Check drive")
    #expect(health.subtitle == "Warning reported · 3% wear")
  }

  @Test("Wear past 100 percent keeps its number and clamps its bar")
  func wearPastEndOfLife() throws {
    let health = try #require(
      Self.rows(health: [Self.health(used: 130)]).first { $0.id == "health:0" })

    #expect(health.subtitle == "No warnings · 130% wear")
    #expect(health.usedFraction == 1)
  }

  @Test("A drive with no temperature gets no temperature row")
  func missingTemperature() {
    let rows = Self.rows(health: [Self.health(kelvin: 0)])

    #expect(rows.contains { $0.id == "health:0" })
    #expect(!rows.contains { $0.id == "temperature:0" })
  }

  @Test("A SMART device with no matching volume is named generically")
  func unmatchedHealthDevice() throws {
    let temperature = try #require(
      Self.rows(health: [Self.health(disk: nil)]).first { $0.id == "temperature:0" })

    #expect(temperature.subtitle == "NVMe drive")
  }

  @Test("No health readings means no health rows, as in the sandboxed build")
  func noHealthRows() {
    #expect(!Self.rows().contains { $0.id.hasPrefix("health:") })
  }

  @Test("Temperature follows the reader's region")
  func temperatureByLocale() throws {
    let celsius = try #require(
      Self.rows(health: [Self.health()], locale: Self.britain)
        .first { $0.id == "temperature:0" })
    #expect(celsius.value.contains("38"))
    #expect(celsius.value.contains("C"))

    let fahrenheit = try #require(
      Self.rows(health: [Self.health()], locale: Locale(identifier: "en_US"))
        .first { $0.id == "temperature:0" })
    #expect(fahrenheit.value.contains("100"))
    #expect(fahrenheit.value.contains("F"))
  }
}

@Suite("Hardware value formatting")
struct HardwareValueFormattingTests {
  @Test("Drive sizes use decimal units, the way Finder counts")
  func diskBytes() {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    #expect(
      ValueFormatting.diskBytes(994_662_584_320)
        == formatter.string(fromByteCount: 994_662_584_320))
    #expect(ValueFormatting.diskBytes(994_662_584_320) != ValueFormatting.bytes(994_662_584_320))
  }

  @Test(
    "Megabytes per second keep one decimal below 10",
    arguments: [
      (0.0, "0.0"), (221_184.0, "0.2"), (9_940_000.0, "9.9"), (9_960_000.0, "10"),
      (51_314_688.0, "51"), (212_400_000.0, "212"), (-5.0, "0.0"),
    ])
  func megabytesPerSecond(bytesPerSecond: Double, expected: String) {
    #expect(ValueFormatting.megabytesPerSecond(bytesPerSecond) == expected)
  }

  @Test("Throughput reads as one line, with dashes before the first reading")
  func throughput() {
    #expect(
      ValueFormatting.throughput(
        DiskActivity(readBytesPerSecond: 212_000_000, writeBytesPerSecond: 88_000_000))
        == "R 212 · W 88 MB/s")
    #expect(ValueFormatting.throughput(nil) == "R — · W — MB/s")
  }

  @Test("A stat row's accessibility label reads title, value, then detail")
  func accessibilityLabel() {
    let row = StatRow(
      id: "x", symbol: "cpu", title: "GPU Utilization", subtitle: "Renderer 27% · Tiler 12%",
      value: "27%", usedFraction: 0.27, isAccented: true)
    #expect(row.accessibilityLabel == "GPU Utilization, 27%, Renderer 27% · Tiler 12%")
  }
}
