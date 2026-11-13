import Foundation
import IOKit

/// Whether this build may read NVMe SMART data. The read opens a user
/// client, and the App Sandbox denies that (SANDBOX_NOTES.md, November
/// 13, 2026). Like termination, the answer comes from our own code
/// signature: a sandboxed build never attempts the read and never shows
/// health rows.
enum DriveHealthCapability: Sendable, Equatable {
  case available
  case sandboxed

  static let current: DriveHealthCapability =
    forSandboxedBuild(AppSandboxStatus.current == .enabled)

  static func forSandboxedBuild(_ isSandboxed: Bool) -> DriveHealthCapability {
    isSandboxed ? .sandboxed : .available
  }
}

/// One NVMe drive's SMART health page, reduced to what the Drives tab
/// shows.
struct DriveHealth: Sendable, Equatable {
  /// BSD name of the whole disk, such as "disk0", when the registry
  /// links the SMART device to one.
  let physicalDisk: String?
  /// NVMe critical warning bits. Any bit set means the drive itself
  /// reports a problem.
  let criticalWarning: UInt8
  /// The drive's own estimate of life consumed. NVMe lets it pass 100.
  let percentageUsed: Int
  let availableSparePercent: Int
  let availableSpareThresholdPercent: Int
  /// nil when the drive reports no temperature.
  let temperatureCelsius: Int?

  init(
    criticalWarning: UInt8,
    temperatureKelvin: UInt16,
    availableSpare: UInt8,
    availableSpareThreshold: UInt8,
    percentageUsed: UInt8,
    physicalDisk: String?
  ) {
    self.physicalDisk = physicalDisk
    self.criticalWarning = criticalWarning
    self.percentageUsed = Int(percentageUsed)
    self.availableSparePercent = Int(availableSpare)
    self.availableSpareThresholdPercent = Int(availableSpareThreshold)
    // NVMe reports whole kelvins.
    self.temperatureCelsius = temperatureKelvin > 0 ? Int(temperatureKelvin) - 273 : nil
  }

  var hasWarning: Bool {
    criticalWarning != 0 || availableSparePercent < availableSpareThresholdPercent
  }
}

/// Reads SMART health from every NVMe SMART capable device. Internal
/// Apple silicon storage qualifies, and so does an NVMe drive in a
/// Thunderbolt enclosure. A USB bridge exposes no SMART interface.
/// Call only when DriveHealthCapability is available.
enum DriveHealthSampler {
  static func sample() -> [DriveHealth] {
    var drives: [DriveHealth] = []
    // The value of kIOPropertyMatchKey and kIOPropertyNVMeSMARTCapableKey.
    let matching: [String: Any] = ["IOPropertyMatch": ["NVMe SMART Capable": true]]
    IORegistry.forEachService(matching: matching as CFDictionary) { service in
      var page = HeadroomNVMeHealth()
      guard HeadroomReadNVMeHealth(service, &page) == KERN_SUCCESS else { return }
      drives.append(
        DriveHealth(
          criticalWarning: page.criticalWarning,
          temperatureKelvin: page.temperatureKelvin,
          availableSpare: page.availableSpare,
          availableSpareThreshold: page.availableSpareThreshold,
          percentageUsed: page.percentageUsed,
          physicalDisk: IORegistry.searchChildren("BSD Name", from: service) as? String))
    }
    return drives
  }
}
