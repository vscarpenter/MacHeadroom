import Foundation

/// One row of the GPU or Drives pane. Both popover appearances draw the
/// same values, so every string and number is decided here, away from
/// SwiftUI, where a fixture can pin it.
struct StatRow: Equatable, Identifiable {
  let id: String
  /// SF Symbol name for the row's icon.
  let symbol: String
  let title: String
  let subtitle: String
  let value: String
  /// The share that is used, 0 through 1. Every bar in these panes
  /// means the same thing. nil draws no bar.
  let usedFraction: Double?
  let isAccented: Bool

  var accessibilityLabel: String { "\(title), \(value), \(subtitle)" }
}

enum GPUPresentation {
  static func headroomPercent(_ gpu: GPUSample?) -> Int? {
    ValueFormatting.headroomPercent(used: gpu?.utilizationPercent, capacity: 100)
  }

  static func usageDetail(_ gpu: GPUSample?) -> String {
    guard let gpu else { return "GPU statistics unavailable" }
    let inUse = "\(ValueFormatting.percent(gpu.utilizationPercent)) in use"
    guard let allocated = gpu.allocatedMemoryBytes else { return inUse }
    return "\(inUse) · \(ValueFormatting.bytes(allocated)) GPU memory"
  }

  /// Utilization, then GPU memory when the driver reports it.
  /// `installedMemoryBytes` is the Mac's memory: on Apple silicon the
  /// GPU allocates out of it, so that is the honest scale for the bar.
  static func statRows(_ gpu: GPUSample, installedMemoryBytes: UInt64) -> [StatRow] {
    var rows = [
      StatRow(
        id: "gpu-utilization",
        symbol: "cpu",
        title: "GPU Utilization",
        subtitle: utilizationSubtitle(gpu),
        value: ValueFormatting.percent(gpu.utilizationPercent),
        usedFraction: min(max(gpu.utilizationPercent / 100, 0), 1),
        isAccented: true)
    ]
    if let allocated = gpu.allocatedMemoryBytes {
      rows.append(
        StatRow(
          id: "gpu-memory",
          symbol: "memorychip",
          title: "GPU Memory",
          subtitle: gpu.inUseMemoryBytes.map { "\(ValueFormatting.bytes($0)) in active use" }
            ?? "Shared with system memory",
          value: ValueFormatting.bytes(allocated),
          usedFraction: installedMemoryBytes > 0
            ? min(Double(allocated) / Double(installedMemoryBytes), 1) : nil,
          isAccented: false))
    }
    return rows
  }

  private static func utilizationSubtitle(_ gpu: GPUSample) -> String {
    let breakdown = [
      gpu.rendererPercent.map { "Renderer \(ValueFormatting.percent($0))" },
      gpu.tilerPercent.map { "Tiler \(ValueFormatting.percent($0))" },
    ].compactMap { $0 }
    if !breakdown.isEmpty { return breakdown.joined(separator: " · ") }

    let chip = [
      gpu.model,
      gpu.coreCount.map { $0 == 1 ? "1 core" : "\($0) cores" },
    ].compactMap { $0 }
    return chip.isEmpty ? "Graphics processor" : chip.joined(separator: " · ")
  }
}

enum DrivesPresentation {
  static func headroomPercent(_ volumes: [VolumeSnapshot]) -> Int? {
    guard let startup = volumes.first(where: \.isStartup) else { return nil }
    return ValueFormatting.headroomPercent(
      used: Double(startup.usedBytes), capacity: Double(startup.totalBytes))
  }

  static func usageDetail(_ volumes: [VolumeSnapshot]) -> String {
    guard let startup = volumes.first(where: \.isStartup) else { return "Drives unavailable" }
    let place =
      switch startup.location {
      case .internal: "internal"
      case .external: "external"
      case .unknown: "total"
      }
    return "\(ValueFormatting.diskBytes(startup.usedBytes)) in use · "
      + "\(ValueFormatting.diskBytes(startup.totalBytes)) \(place)"
  }

  /// "Internal SSD · 994.66 GB · APFS". An internal drive ends with its
  /// format; an external one ends with its bus when the registry names
  /// it, since the bus is what the reader can act on.
  static func kindLine(_ volume: VolumeSnapshot) -> String {
    let kind: String
    switch (volume.location, volume.medium) {
    case (.internal, .solidState): kind = "Internal SSD"
    case (.internal, .rotational): kind = "Internal HDD"
    case (.internal, nil): kind = "Internal"
    case (.external, .solidState): kind = "External SSD"
    case (.external, .rotational): kind = "External HDD"
    case (.external, nil): kind = "External"
    case (.unknown, _): kind = "Drive"
    }
    let tail =
      volume.location == .external
      ? volume.interconnect ?? volume.formatDescription : volume.formatDescription
    return [kind, ValueFormatting.diskBytes(volume.totalBytes), tail]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  /// Volumes, then one activity row per physical disk, then the health
  /// rows. `health` is empty in the sandboxed build, so that build
  /// simply has no health rows.
  static func rows(
    volumes: [VolumeSnapshot],
    activity: [String: DiskActivity],
    health: [DriveHealth],
    locale: Locale
  ) -> [StatRow] {
    var rows = volumes.map { volume in
      StatRow(
        id: volume.id,
        symbol: volume.location == .external ? "externaldrive" : "internaldrive",
        title: volume.name,
        subtitle: kindLine(volume),
        value: "\(ValueFormatting.diskBytes(volume.freeBytes)) free",
        usedFraction: volume.usedFraction,
        isAccented: volume.isStartup)
    }

    var disksInOrder: [String] = []
    var namesByDisk: [String: [String]] = [:]
    for volume in volumes {
      guard let disk = volume.physicalDisk else { continue }
      if namesByDisk[disk] == nil { disksInOrder.append(disk) }
      namesByDisk[disk, default: []].append(volume.name)
    }

    for disk in disksInOrder {
      rows.append(
        StatRow(
          id: "activity:\(disk)",
          symbol: "waveform.path.ecg",
          title: "Disk Activity",
          subtitle: (namesByDisk[disk] ?? []).joined(separator: ", "),
          value: ValueFormatting.throughput(activity[disk]),
          usedFraction: nil,
          isAccented: false))
    }

    for (index, drive) in health.enumerated() {
      let driveName =
        drive.physicalDisk.flatMap { namesByDisk[$0] }?.joined(separator: ", ") ?? "NVMe drive"
      rows.append(
        StatRow(
          id: "health:\(index)",
          symbol: "heart",
          title: "SSD Health",
          subtitle: "\(drive.hasWarning ? "Warning reported" : "No warnings") · "
            + "\(drive.percentageUsed)% wear",
          value: drive.hasWarning ? "Check drive" : "Healthy",
          usedFraction: min(Double(drive.percentageUsed) / 100, 1),
          isAccented: false))
      if let celsius = drive.temperatureCelsius {
        rows.append(
          StatRow(
            id: "temperature:\(index)",
            symbol: "thermometer.medium",
            title: "Drive Temperature",
            subtitle: driveName,
            value: ValueFormatting.temperature(celsius: celsius, locale: locale),
            usedFraction: nil,
            isAccented: false))
      }
    }
    return rows
  }
}
