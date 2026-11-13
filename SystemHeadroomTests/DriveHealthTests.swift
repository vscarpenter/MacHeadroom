import Testing

@testable import SystemHeadroom

@Suite("Drive health")
struct DriveHealthTests {
  private static func health(
    warning: UInt8 = 0, kelvin: UInt16 = 311, spare: UInt8 = 100, threshold: UInt8 = 99,
    used: UInt8 = 3
  ) -> DriveHealth {
    DriveHealth(
      criticalWarning: warning, temperatureKelvin: kelvin, availableSpare: spare,
      availableSpareThreshold: threshold, percentageUsed: used, physicalDisk: "disk0")
  }

  @Test("The measured SMART page reads as 38 C, 3% used, no warning")
  func measuredPage() {
    let health = Self.health()

    #expect(health.temperatureCelsius == 38)
    #expect(health.percentageUsed == 3)
    #expect(health.availableSparePercent == 100)
    #expect(health.availableSpareThresholdPercent == 99)
    #expect(!health.hasWarning)
    #expect(health.physicalDisk == "disk0")
  }

  @Test("A zero temperature is unknown, not absolute zero")
  func zeroKelvin() {
    #expect(Self.health(kelvin: 0).temperatureCelsius == nil)
  }

  @Test("Any critical warning bit is a warning")
  func warningByte() {
    #expect(Self.health(warning: 0b0000_0001).hasWarning)
    #expect(Self.health(warning: 0b0000_0100).hasWarning)
  }

  @Test("Spare capacity under its threshold is a warning even with a clear warning byte")
  func spareUnderThreshold() {
    #expect(Self.health(spare: 5, threshold: 10).hasWarning)
    #expect(!Self.health(spare: 10, threshold: 10).hasWarning)
  }

  @Test("Wear can exceed 100 percent and is kept as reported")
  func wearPastEndOfLife() {
    #expect(Self.health(used: 130).percentageUsed == 130)
  }

  @Test("The capability follows the sandbox, like termination does")
  func capabilityFollowsSandbox() {
    #expect(DriveHealthCapability.forSandboxedBuild(true) == .sandboxed)
    #expect(DriveHealthCapability.forSandboxedBuild(false) == .available)
    #expect(
      DriveHealthCapability.current
        == DriveHealthCapability.forSandboxedBuild(AppSandboxStatus.current == .enabled))
  }

  /// The sandbox denies the SMART user client, so this runs only in an
  /// unsandboxed test host (see CLAUDE.md, "Verifying UI changes").
  @Test(
    "Unsandboxed SMART read returns the internal drive",
    .enabled(
      if: AppSandboxStatus.current == .disabled && !TestHardware.isVirtualMachine,
      "needs an unsandboxed host on a physical Mac"))
  func liveRead() throws {
    let drive = try #require(DriveHealthSampler.sample().first)

    #expect(drive.physicalDisk?.hasPrefix("disk") == true)
    #expect((0...255).contains(drive.percentageUsed))
    let celsius = try #require(drive.temperatureCelsius)
    #expect((0...110).contains(celsius))
    print("DRIVE_HEALTH \(drive)")
  }
}
