import Foundation
import Testing
import os

@testable import SystemHeadroom

/// The sampler service owns the hardware baseline and paces the two
/// slow reads. These drive the real service inside the TEST_HOST, with
/// a counting stand-in for the SMART read the sandbox denies.
@Suite("Hardware tick")
struct HardwareTickTests {
  private static let health = DriveHealth(
    criticalWarning: 0, temperatureKelvin: 311, availableSpare: 100,
    availableSpareThreshold: 99, percentageUsed: 3, physicalDisk: "disk0")

  /// Short enough to keep the tests quick, long enough that the sleeps
  /// below clear it by a wide margin on a slow runner.
  private static let shortWindow: UInt64 = 20_000_000

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

  @Test("Volumes arrive on the first tick, before any delta exists")
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
    let service = SamplerService(minimumHardwareWindowNanoseconds: Self.shortWindow)

    let first = await service.tick(convention: .machineCapacity)
    try await Task.sleep(for: .milliseconds(150))
    let second = await service.tick(convention: .machineCapacity)

    let firstGPU = try #require(first.gpu)
    #expect(firstGPU.reportsProcessUsage)
    #expect(firstGPU.processPercents == nil)
    let secondGPU = try #require(second.gpu)
    _ = try #require(secondGPU.processPercents)
    #expect(!secondGPU.processNames.isEmpty)

    let disk = try #require(second.volumes.first?.physicalDisk)
    #expect(second.diskActivity[disk] != nil)
  }

  /// One WindowServer frame fills a 3 ms window, so a refresh right
  /// after a tick once read 18.6% for a process while the device read
  /// 0%. A tick inside the minimum window repeats the last figures and
  /// leaves the baseline alone, so the window keeps growing.
  @Test(
    "A tick too soon after the last one repeats its hardware figures",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical GPU and disk"))
  func burstRepeatsLastFigures() async throws {
    let service = SamplerService(minimumHardwareWindowNanoseconds: 60_000_000_000)

    let priming = await service.tick(convention: .machineCapacity)
    let tooSoon = await service.tick(convention: .machineCapacity)
    let primingGPU = try #require(priming.gpu)
    let tooSoonGPU = try #require(tooSoon.gpu)
    #expect(primingGPU.processPercents == nil)
    #expect(tooSoonGPU.processPercents == nil)
    #expect(tooSoon.diskActivity.isEmpty)

    let measured = SamplerService(minimumHardwareWindowNanoseconds: 100_000_000)
    _ = await measured.tick(convention: .machineCapacity)
    try await Task.sleep(for: .milliseconds(300))
    let real = await measured.tick(convention: .machineCapacity)
    let burst = await measured.tick(convention: .machineCapacity)

    let realGPU = try #require(real.gpu)
    let realPercents = try #require(realGPU.processPercents)
    let burstGPU = try #require(burst.gpu)
    #expect(burstGPU.processPercents == realPercents)
    #expect(burst.diskActivity == real.diskActivity)
    #expect(!real.diskActivity.isEmpty)
  }

  /// Sampling stops while the popover is closed. Without this, the
  /// first sample after reopening divided by the whole closed period:
  /// a write measured 159 MB/s that way and 1,473 MB/s two seconds on.
  @Test(
    "Resuming after a pause primes again instead of measuring across the pause",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical GPU and disk"))
  func resumePrimesAgain() async throws {
    let service = SamplerService(minimumHardwareWindowNanoseconds: Self.shortWindow)

    _ = await service.tick(convention: .machineCapacity)
    try await Task.sleep(for: .milliseconds(150))
    let warm = await service.tick(convention: .machineCapacity)
    let warmGPU = try #require(warm.gpu)
    #expect(warmGPU.processPercents != nil)
    #expect(!warm.diskActivity.isEmpty)

    try await Task.sleep(for: .milliseconds(150))
    let resumed = await service.tick(convention: .machineCapacity, resumingAfterPause: true)
    let resumedGPU = try #require(resumed.gpu)
    #expect(resumedGPU.processPercents == nil)
    #expect(resumed.diskActivity.isEmpty)

    try await Task.sleep(for: .milliseconds(150))
    let next = await service.tick(convention: .machineCapacity)
    let nextGPU = try #require(next.gpu)
    #expect(nextGPU.processPercents != nil)
    #expect(!next.diskActivity.isEmpty)
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
    // Only a Mac with real purgeable space can tell the sum from plain
    // available space, so the stricter check needs at least 4 GB of it.
    if purgeable > 4_000_000_000 {
      #expect(Double(startup.freeBytes) > Double(plainAvailable) + Double(purgeable) / 2)
    }
  }
}

@Suite("Store hardware state")
@MainActor
struct StoreHardwareTests {
  private static func makeStore(sampler: SamplerService = SamplerService()) throws -> MonitorStore {
    let suiteName = "com.vinnycarpenter.SystemHeadroomTests.hardware.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return MonitorStore(
      sampler: sampler, defaults: defaults, capability: .sandboxed,
      terminator: ProcessTerminator(
        runningApplication: { _ in nil },
        currentStartIdentity: { _ in nil },
        sendSignal: { _, _ in 0 }),
      alertDelivery: NoOpAlertDelivery())
  }

  @Test("Store publishes hardware state after two refreshes")
  func storePublishesHardware() async throws {
    let store = try Self.makeStore(
      sampler: SamplerService(minimumHardwareWindowNanoseconds: 20_000_000))

    #expect(store.gpu == nil)
    #expect(store.topGPUApps == nil)
    #expect(store.volumes.isEmpty)

    await store.refreshNow()
    try await Task.sleep(for: .milliseconds(150))
    await store.refreshNow()

    #expect(store.volumes.first?.isStartup == true)
    if !TestHardware.isVirtualMachine {
      #expect(store.gpu != nil)
      #expect(store.topGPUApps != nil)
      #expect(!store.diskActivity.isEmpty)
      // The default sampler reads SMART only when unsandboxed, so this
      // same test proves both editions' behavior from either host.
      #expect(store.driveHealth.isEmpty == (AppSandboxStatus.current == .enabled))
    }
  }

  /// Opening and closing with no await between them never lets the
  /// timer task run, so this marks a restart without taking a sample.
  @Test(
    "After sampling restarts, the next sample primes instead of spanning the pause",
    .enabled(if: !TestHardware.isVirtualMachine, "needs a physical GPU and disk"))
  func restartPrimesHardwareDeltas() async throws {
    let store = try Self.makeStore(
      sampler: SamplerService(minimumHardwareWindowNanoseconds: 20_000_000))

    await store.refreshNow()
    try await Task.sleep(for: .milliseconds(150))
    await store.refreshNow()
    #expect(store.topGPUApps != nil)
    #expect(!store.diskActivity.isEmpty)
    #expect(!store.awaitsSecondSample)

    try await Task.sleep(for: .milliseconds(150))
    store.popoverDidAppear()
    store.popoverDidDisappear()
    await store.refreshNow()

    #expect(store.topGPUApps == nil)
    #expect(store.diskActivity.isEmpty)
    #expect(store.awaitsSecondSample)
  }

  @Test("A reading that needs two samples asks for the quick follow-up")
  func awaitsSecondSample() {
    let primed = SystemSummary(cpuPercent: 12, memoryUsedBytes: 1, memoryTotalBytes: 2)
    let unprimed = SystemSummary(cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let silentGPU = GPUSample(
      model: nil, coreCount: nil, utilizationPercent: 40, rendererPercent: nil,
      tilerPercent: nil, allocatedMemoryBytes: nil, inUseMemoryBytes: nil,
      reportsProcessUsage: false, processPercents: nil, processNames: [:])

    func store(
      _ summary: SystemSummary, gpu: GPUSample? = nil, gpuApps: [GPUAppUsage]? = [],
      volumes: [VolumeSnapshot] = [], activity: [String: DiskActivity] = [:]
    ) -> MonitorStore {
      MonitorStore.preview(
        cpuGroups: [], memoryGroups: [], summary: summary, gpu: gpu, gpuApps: gpuApps,
        volumes: volumes, diskActivity: activity)
    }

    #expect(store(unprimed).awaitsSecondSample)
    #expect(!store(primed).awaitsSecondSample)
    #expect(store(primed, gpu: PreviewFixtures.gpuSample, gpuApps: nil).awaitsSecondSample)
    // A driver that never reports per-app time has nothing to wait for.
    #expect(!store(primed, gpu: silentGPU, gpuApps: nil).awaitsSecondSample)
    #expect(store(primed, volumes: PreviewFixtures.volumes).awaitsSecondSample)
    #expect(
      !store(
        primed, gpu: PreviewFixtures.gpuSample, gpuApps: [],
        volumes: PreviewFixtures.volumes, activity: PreviewFixtures.diskActivity
      ).awaitsSecondSample)
  }
}
