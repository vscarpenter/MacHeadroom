import Darwin
import Foundation
import IOKit
import os

enum DriveLocation: Sendable, Equatable {
  case `internal`
  case external
  case unknown
}

enum DriveMedium: Sendable, Equatable {
  case solidState
  case rotational
}

/// Everything the sampler read about one mounted volume, before any
/// filtering. Registry-derived fields are nil when the volume has no
/// IOMedia chain (a network mount) or a key was missing.
struct VolumeFacts: Sendable, Equatable {
  var mountPath: String
  var name: String
  var totalBytes: UInt64
  var availableBytes: UInt64
  /// The figure Finder shows: available plus purgeable space. Zero
  /// means unknown, which is every volume but the startup one.
  var importantAvailableBytes: UInt64
  var isLocal: Bool
  var isStartup: Bool
  var formatDescription: String?
  /// BSD name of the whole disk behind the volume, such as "disk0".
  var physicalDisk: String?
  var interconnect: String?
  var interconnectLocation: String?
  var mediumType: String?
  var counters: DiskCounters?
}

/// One drive row's worth of facts.
struct VolumeSnapshot: Sendable, Equatable, Identifiable {
  let mountPath: String
  let name: String
  let totalBytes: UInt64
  let freeBytes: UInt64
  let isStartup: Bool
  let location: DriveLocation
  let medium: DriveMedium?
  let interconnect: String?
  let formatDescription: String?
  let physicalDisk: String?

  var id: String { "volume:\(mountPath)" }

  /// Clamped: a read that races a large delete can report more free
  /// space than capacity.
  var usedBytes: UInt64 { totalBytes - min(freeBytes, totalBytes) }

  var usedFraction: Double {
    guard totalBytes > 0 else { return 0 }
    return Double(usedBytes) / Double(totalBytes)
  }
}

/// Decides which mounted volumes are drives and shapes them for
/// display. Pure and fixture-testable: VolumeSampler does the reads.
enum VolumeClassifier {
  /// Startup volume first, then names in Finder order. A network mount
  /// has no physical disk and a disk image sits on a virtual
  /// interconnect; neither is a drive. The startup volume always stays.
  static func snapshots(from facts: [VolumeFacts]) -> [VolumeSnapshot] {
    facts.filter(isDrive).map(snapshot).sorted { lhs, rhs in
      if lhs.isStartup != rhs.isStartup { return lhs.isStartup }
      let names = lhs.name.localizedStandardCompare(rhs.name)
      if names != .orderedSame { return names == .orderedAscending }
      return lhs.mountPath < rhs.mountPath
    }
  }

  /// Byte counters keyed by physical disk, for the kept volumes only.
  static func counters(from facts: [VolumeFacts]) -> [String: DiskCounters] {
    var counters: [String: DiskCounters] = [:]
    for volume in facts where isDrive(volume) {
      guard let disk = volume.physicalDisk, let reading = volume.counters,
        counters[disk] == nil
      else { continue }
      counters[disk] = reading
    }
    return counters
  }

  private static func isDrive(_ facts: VolumeFacts) -> Bool {
    guard facts.totalBytes > 0 else { return false }
    if facts.isStartup { return true }
    return facts.isLocal && facts.physicalDisk != nil
      && facts.interconnect != "Virtual Interface"
  }

  private static func snapshot(_ facts: VolumeFacts) -> VolumeSnapshot {
    VolumeSnapshot(
      mountPath: facts.mountPath,
      name: facts.name,
      totalBytes: facts.totalBytes,
      freeBytes: facts.importantAvailableBytes > 0
        ? facts.importantAvailableBytes : facts.availableBytes,
      isStartup: facts.isStartup,
      location: location(facts.interconnectLocation),
      medium: medium(facts.mediumType),
      interconnect: facts.interconnect,
      formatDescription: facts.formatDescription,
      physicalDisk: facts.physicalDisk)
  }

  private static func location(_ value: String?) -> DriveLocation {
    switch value {
    case "Internal": .internal
    case "External": .external
    default: .unknown
    }
  }

  private static func medium(_ value: String?) -> DriveMedium? {
    switch value {
    case "Solid State": .solidState
    case "Rotational": .rotational
    default: nil
    }
  }
}

/// Reads mounted volumes and the physical disk behind each. Capacity
/// comes from Foundation's volume values. The disk comes from walking
/// the registry from the volume's IOMedia up to its
/// IOBlockStorageDriver, which also holds the byte counters. Both are
/// open under the App Sandbox (Evidence/gpu-drives-spike/).
enum VolumeSampler {
  private static let log = Logger(
    subsystem: "com.vinnycarpenter.SystemHeadroom", category: "drives")

  private static let keys: Set<URLResourceKey> = [
    .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
    .volumeIsLocalKey, .volumeIsRootFileSystemKey, .volumeLocalizedFormatDescriptionKey,
  ]

  /// The per-tick read, under 1 ms. Hidden volumes are skipped: that
  /// drops Time Machine snapshot mounts and the system's own helper
  /// volumes. `importantAvailableBytes` is left at zero here; the
  /// caller fills it from `purgeableBytes`.
  static func sampleFacts() -> [VolumeFacts] {
    let urls =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap(facts(for:))
  }

  /// Space the system can reclaim on demand: Finder's free-space figure
  /// minus plain available capacity. The important-usage read measured
  /// about 11 ms per call, against under 1 ms for everything else in
  /// the sweep, so SamplerService paces this one. nil when the volume
  /// reports no important-usage figure (every volume but the startup
  /// one, as measured).
  static func purgeableBytes(forMountPath path: String) -> UInt64? {
    do {
      let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
        .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
      ])
      guard let important = values.volumeAvailableCapacityForImportantUsage, important > 0,
        let available = values.volumeAvailableCapacity
      else { return nil }
      return UInt64(clamping: important - Int64(available))
    } catch {
      log.debug("purgeable space unreadable: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private static func facts(for url: URL) -> VolumeFacts? {
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: keys)
    } catch {
      // A volume can unmount between the listing and this read. The
      // row is simply absent this tick.
      log.debug("volume values unreadable: \(error.localizedDescription, privacy: .public)")
      return nil
    }

    var facts = VolumeFacts(
      mountPath: url.path,
      name: values.volumeName ?? url.lastPathComponent,
      totalBytes: UInt64(clamping: values.volumeTotalCapacity ?? 0),
      availableBytes: UInt64(clamping: values.volumeAvailableCapacity ?? 0),
      importantAvailableBytes: 0,
      isLocal: values.volumeIsLocal ?? false,
      isStartup: values.volumeIsRootFileSystem ?? false,
      formatDescription: values.volumeLocalizedFormatDescription)
    if let bsdName = bsdName(forMountPath: url.path) {
      attachDisk(bsdName: bsdName, to: &facts)
    }
    return facts
  }

  /// "/dev/disk3s1s1" becomes "disk3s1s1". A network mount's source is
  /// not a device node, so it has no BSD name.
  private static func bsdName(forMountPath path: String) -> String? {
    var info = statfs()
    guard statfs(path, &info) == 0 else { return nil }
    let source = withUnsafeBytes(of: &info.f_mntfromname) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
    let devicePrefix = "/dev/"
    guard source.hasPrefix(devicePrefix) else { return nil }
    return String(source.dropFirst(devicePrefix.count))
  }

  /// The key strings are the values of IOKit's storage constants
  /// (kIOPropertyProtocolCharacteristicsKey and friends), spelled out
  /// because Swift does not import those macros.
  private static func attachDisk(bsdName: String, to facts: inout VolumeFacts) {
    guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return }
    let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard media != 0 else { return }
    defer { IOObjectRelease(media) }

    if let transport = IORegistry.searchParents("Protocol Characteristics", from: media)
      as? [String: Any]
    {
      facts.interconnect = transport["Physical Interconnect"] as? String
      facts.interconnectLocation = transport["Physical Interconnect Location"] as? String
    }
    if let device = IORegistry.searchParents("Device Characteristics", from: media)
      as? [String: Any]
    {
      facts.mediumType = device["Medium Type"] as? String
    }

    let disk = IORegistry.withFirstAncestor(of: media, conformingTo: "IOBlockStorageDriver") {
      driver -> (name: String?, counters: DiskCounters?) in
      let statistics = IORegistry.property("Statistics", of: driver) as? [String: Any]
      let read = (statistics?["Bytes (Read)"] as? NSNumber)?.uint64Value
      let written = (statistics?["Bytes (Write)"] as? NSNumber)?.uint64Value
      var counters: DiskCounters?
      if let read, let written {
        counters = DiskCounters(readBytes: read, writeBytes: written)
      }
      return (IORegistry.searchChildren("BSD Name", from: driver) as? String, counters)
    }
    facts.physicalDisk = disk?.name
    facts.counters = disk?.counters
  }
}
