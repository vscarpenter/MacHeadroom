import Foundation
import Testing

@testable import SystemHeadroom

/// Live reads inside the TEST_HOST. They re-prove on every run that the
/// App Sandbox allows the registry walk and the byte counters. They do
/// not prove the volume values: those are file-backed reads, and the
/// test action gives the host read-only access to "/". The proof for
/// those is the probe in Evidence/gpu-drives-spike/, signed with only
/// the app-sandbox entitlement. Here they guard against regressions.
@Suite("Drive sampler live")
struct DriveSamplerLiveTests {
  @Test("Sandboxed volume read returns the startup volume with capacity")
  func startupVolume() throws {
    let facts = VolumeSampler.sampleFacts()
    let startup = try #require(facts.first { $0.isStartup })

    #expect(startup.mountPath == "/")
    #expect(startup.totalBytes > 0)
    #expect(startup.availableBytes <= startup.totalBytes)
    #expect(!startup.name.isEmpty)
    #expect(VolumeClassifier.snapshots(from: facts).first?.isStartup == true)
  }

  @Test(
    "Sandboxed registry walk finds the startup volume's disk and byte counters",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical disk"))
  func physicalDisk() throws {
    let startup = try #require(VolumeSampler.sampleFacts().first { $0.isStartup })

    #expect(startup.physicalDisk?.hasPrefix("disk") == true)
    #expect(startup.interconnectLocation == "Internal")
    #expect(startup.mediumType != nil)
    let counters = try #require(startup.counters)
    #expect(counters.readBytes > 0)
    #expect(counters.writeBytes > 0)
  }

  @Test(
    "Sandboxed purgeable-space read returns a figure that fits the startup volume",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical startup disk"))
  func purgeableSpace() throws {
    let startup = try #require(VolumeSampler.sampleFacts().first { $0.isStartup })
    let purgeable = try #require(VolumeSampler.purgeableBytes(forMountPath: "/"))

    #expect(purgeable < startup.totalBytes)
  }

  /// The purgeable read is the slow one and is paced separately, so
  /// this budget covers only what every tick pays.
  @Test("The per-tick volume sweep is cheap enough to ride every tick")
  func sweepCost() {
    let elapsed = ContinuousClock().measure { _ = VolumeSampler.sampleFacts() }
    print("VOLUME_SWEEP \(elapsed)")
    // A cold call measured 4 to 10 ms and CI runs up to 2.6x slower,
    // so this leaves about ten times the worst case.
    #expect(elapsed < .milliseconds(250))
  }
}
