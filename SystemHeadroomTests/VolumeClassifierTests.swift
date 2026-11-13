import Testing

@testable import SystemHeadroom

/// Fixtures carry the shapes measured on November 13, 2026
/// (Evidence/gpu-drives-spike/): an internal APFS startup volume, an
/// external USB disk, a mounted disk image, and an NFS mount.
@Suite("Volume classifier")
struct VolumeClassifierTests {
  private static func facts(
    mountPath: String = "/",
    name: String = "Macintosh HD",
    total: UInt64 = 994_662_584_320,
    available: UInt64 = 140_138_074_112,
    important: UInt64 = 179_612_178_956,
    isLocal: Bool = true,
    isStartup: Bool = true,
    format: String? = "APFS",
    physicalDisk: String? = "disk0",
    interconnect: String? = "Apple Fabric",
    location: String? = "Internal",
    medium: String? = "Solid State",
    counters: DiskCounters? = DiskCounters(readBytes: 10, writeBytes: 20)
  ) -> VolumeFacts {
    VolumeFacts(
      mountPath: mountPath, name: name, totalBytes: total, availableBytes: available,
      importantAvailableBytes: important, isLocal: isLocal, isStartup: isStartup,
      formatDescription: format, physicalDisk: physicalDisk, interconnect: interconnect,
      interconnectLocation: location, mediumType: medium, counters: counters)
  }

  private static let external = facts(
    mountPath: "/Volumes/Backup", name: "Backup", total: 8_001_352_437_760,
    available: 4_418_738_233_344, important: 0, isStartup: false,
    format: "APFS (Case-sensitive)", physicalDisk: "disk6", interconnect: "USB",
    location: "External", medium: "Rotational",
    counters: DiskCounters(readBytes: 30, writeBytes: 40))

  private static let diskImage = facts(
    mountPath: "/Volumes/Installer", name: "Installer", total: 454_041_600,
    available: 55_296_000, important: 0, isStartup: false, physicalDisk: "disk26",
    interconnect: "Virtual Interface", location: "File")

  private static let networkMount = facts(
    mountPath: "/Users/me/Share", name: "Share", total: 181_126_823_936,
    available: 133_020_209_152, important: 0, isLocal: false, isStartup: false,
    format: "Network File System (NFS)", physicalDisk: nil, interconnect: nil,
    location: nil, medium: nil, counters: nil)

  @Test("The startup volume reports the free space Finder shows")
  func startupUsesImportantUsage() throws {
    let volume = try #require(VolumeClassifier.snapshots(from: [Self.facts()]).first)

    #expect(volume.freeBytes == 179_612_178_956)
    #expect(volume.usedBytes == 994_662_584_320 - 179_612_178_956)
    #expect(volume.isStartup)
    #expect(volume.location == .internal)
    #expect(volume.medium == .solidState)
    #expect(volume.physicalDisk == "disk0")
    #expect(volume.formatDescription == "APFS")
    #expect(volume.id == "volume:/")
  }

  @Test("A volume with no important-usage figure falls back to plain available space")
  func externalFallsBack() throws {
    let volume = try #require(VolumeClassifier.snapshots(from: [Self.external]).first)

    #expect(volume.freeBytes == 4_418_738_233_344)
    #expect(volume.location == .external)
    #expect(volume.medium == .rotational)
    #expect(volume.interconnect == "USB")
  }

  @Test("Disk images and network mounts are not drives")
  func dropsImagesAndNetworkMounts() {
    let snapshots = VolumeClassifier.snapshots(
      from: [Self.diskImage, Self.networkMount, Self.facts()])

    #expect(snapshots.map(\.name) == ["Macintosh HD"])
  }

  @Test("The startup volume stays even when the registry walk found no disk")
  func keepsStartupWithoutDisk() throws {
    let orphan = Self.facts(
      physicalDisk: nil, interconnect: nil, location: nil, medium: nil, counters: nil)
    let volume = try #require(VolumeClassifier.snapshots(from: [orphan]).first)

    #expect(volume.physicalDisk == nil)
    #expect(volume.location == .unknown)
    #expect(volume.medium == nil)
  }

  @Test("A volume that reports no capacity is dropped, startup or not")
  func dropsZeroTotal() {
    let empty = Self.facts(total: 0, available: 0, important: 0)
    #expect(VolumeClassifier.snapshots(from: [empty]).isEmpty)
  }

  @Test("Startup comes first, then names in Finder order")
  func ordering() {
    let zulu = Self.facts(
      mountPath: "/Volumes/zulu", name: "zulu", isStartup: false, physicalDisk: "disk8",
      interconnect: "USB", location: "External")
    let alpha10 = Self.facts(
      mountPath: "/Volumes/Alpha 10", name: "Alpha 10", isStartup: false,
      physicalDisk: "disk9", interconnect: "USB", location: "External")
    let alpha2 = Self.facts(
      mountPath: "/Volumes/Alpha 2", name: "Alpha 2", isStartup: false,
      physicalDisk: "disk10", interconnect: "USB", location: "External")

    let names = VolumeClassifier.snapshots(from: [zulu, alpha10, Self.facts(), alpha2])
      .map(\.name)

    #expect(names == ["Macintosh HD", "Alpha 2", "Alpha 10", "zulu"])
  }

  @Test("Used space clamps when a racing read reports more free than total")
  func usedFractionClamps() throws {
    let racing = Self.facts(total: 100, available: 150, important: 0)
    let volume = try #require(VolumeClassifier.snapshots(from: [racing]).first)

    #expect(volume.usedBytes == 0)
    #expect(volume.usedFraction == 0)

    let normal = try #require(VolumeClassifier.snapshots(from: [Self.facts()]).first)
    #expect(abs(normal.usedFraction - 0.8194) < 0.0001)
  }

  @Test("Unrecognized registry strings map to unknown, not a guess")
  func unknownStrings() throws {
    let odd = Self.facts(location: "Orbit", medium: "Crystal")
    let volume = try #require(VolumeClassifier.snapshots(from: [odd]).first)

    #expect(volume.location == .unknown)
    #expect(volume.medium == nil)
  }

  @Test("Byte counters are keyed by physical disk, for kept volumes only")
  func counters() {
    let counters = VolumeClassifier.counters(
      from: [Self.facts(), Self.external, Self.diskImage, Self.networkMount])

    #expect(
      counters == [
        "disk0": DiskCounters(readBytes: 10, writeBytes: 20),
        "disk6": DiskCounters(readBytes: 30, writeBytes: 40),
      ])
  }
}
