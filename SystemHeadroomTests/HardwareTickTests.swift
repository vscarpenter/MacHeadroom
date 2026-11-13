import Foundation
import Testing
import os

@testable import SystemHeadroom

/// The sampler service owns the previous hardware counters and paces
/// the two slow reads. These drive the real service inside the
/// sandboxed TEST_HOST, with a counting stand-in for the SMART read the
/// sandbox denies.
@Suite("Hardware tick")
struct HardwareTickTests {
  private static let health = DriveHealth(
    criticalWarning: 0, temperatureKelvin: 311, availableSpare: 100,
    availableSpareThreshold: 99, percentageUsed: 3, physicalDisk: "disk0")

  private static func service(
    calls: OSAllocatedUnfairLock<Int>, slowReadIntervalNanoseconds: UInt64
  ) -> SamplerService {
    SamplerService(
      driveHealthReader: {
        calls.withLock { $0 += 1 }
        return [health]
      },
      slowReadIntervalNanoseconds: slowReadIntervalNanoseconds)
  }

  @Test("Drive health is read once per slow interval, not once per tick")
  func healthIsPaced() async {
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let service = Self.service(calls: calls, slowReadIntervalNanoseconds: 60_000_000_000)

    let first = await service.tick(convention: .machineCapacity)
    let second = await service.tick(convention: .machineCapacity)

    #expect(calls.withLock { $0 } == 1)
    #expect(first.driveHealth == [Self.health])
    #expect(second.driveHealth == [Self.health])
  }

  @Test("A zero slow interval reads drive health on every tick")
  func healthEveryTickWhenUnpaced() async {
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let service = Self.service(calls: calls, slowReadIntervalNanoseconds: 0)

    _ = await service.tick(convention: .machineCapacity)
    _ = await service.tick(convention: .machineCapacity)

    #expect(calls.withLock { $0 } == 2)
  }

  @Test("With no reader, as in the sandboxed build, drive health stays empty")
  func noReaderNoHealth() async {
    let service = SamplerService(driveHealthReader: nil)

    let tick = await service.tick(convention: .machineCapacity)

    #expect(tick.driveHealth.isEmpty)
  }

  @Test("Only an unsandboxed build installs a drive health reader")
  func defaultReaderFollowsSandbox() {
    let isSandboxed = AppSandboxStatus.current == .enabled
    #expect((SamplerService.liveDriveHealthReader() == nil) == isSandboxed)
  }

  @Test("Volumes arrive on the first tick")
  func volumesOnFirstTick() async throws {
    let tick = await SamplerService().tick(convention: .machineCapacity)

    let startup = try #require(tick.volumes.first)
    #expect(startup.isStartup)
    #expect(startup.freeBytes <= startup.totalBytes)
    #expect(tick.diskActivity.isEmpty)
  }

  @Test(
    "GPU process percents and disk activity need a second tick",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical GPU and disk"))
  func deltasOnSecondTick() async throws {
    let service = SamplerService()

    let first = await service.tick(convention: .machineCapacity)
    try await Task.sleep(for: .milliseconds(50))
    let second = await service.tick(convention: .machineCapacity)

    let firstGPU = try #require(first.gpu)
    #expect(firstGPU.processPercents == nil)
    let secondGPU = try #require(second.gpu)
    let percents = try #require(secondGPU.processPercents)
    #expect(percents.values.allSatisfy { $0 >= 0 })
    #expect(!secondGPU.processNames.isEmpty)

    let disk = try #require(second.volumes.first?.physicalDisk)
    let activity = try #require(second.diskActivity[disk])
    #expect(activity.readBytesPerSecond >= 0)
    #expect(activity.writeBytesPerSecond >= 0)
  }

  @Test(
    "The startup volume's free space counts purgeable space",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical startup disk"))
  func freeSpaceCountsPurgeable() async throws {
    let plainAvailable = try #require(
      VolumeSampler.sampleFacts().first { $0.isStartup }?.availableBytes)
    let purgeable = try #require(VolumeSampler.purgeableBytes(forMountPath: "/"))
    let tick = await SamplerService().tick(convention: .machineCapacity)
    let startup = try #require(tick.volumes.first)

    // Free space moves between the three reads, so allow 1 GB of drift.
    let expected = Double(plainAvailable + purgeable)
    #expect(abs(Double(startup.freeBytes) - expected) < 1_000_000_000)
  }

  @Test("Store publishes hardware state after two refreshes")
  @MainActor
  func storePublishesHardware() async throws {
    let suiteName = "com.vinnycarpenter.SystemHeadroom.hardware-tests"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = MonitorStore(defaults: defaults, capability: .sandboxed)

    #expect(store.gpu == nil)
    #expect(store.topGPUApps == nil)
    #expect(store.volumes.isEmpty)

    await store.refreshNow()
    await store.refreshNow()

    #expect(store.volumes.first?.isStartup == true)
    if !TestHardware.isVirtualMachine {
      #expect(store.gpu != nil)
      #expect(store.topGPUApps != nil)
      // The default sampler reads SMART only when unsandboxed, so this
      // same test proves both editions' behavior from either host.
      #expect(store.driveHealth.isEmpty == (AppSandboxStatus.current == .enabled))
    }
  }
}
