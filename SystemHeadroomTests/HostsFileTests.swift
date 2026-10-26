import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Hosts file parsing")
struct HostsFileTests {
  @Test("Loopback names are collected, de-duplicated, sorted, and localhost is dropped")
  func parsesLoopbackNames() {
    let contents = """
      # Host Database
      127.0.0.1       localhost
      255.255.255.255 broadcasthost
      ::1             localhost
      fe80::1%lo0     localhost
      0.0.0.0 ads.example.com
      127.0.0.1 localhost.localdomain
      127.0.0.1 dev.local # trailing comment
      127.0.0.1  home.vinny.dev gsd.home.vinny.dev
      ::1 gsd.home.vinny.dev

      """
    #expect(
      HostsFile.loopbackNames(in: contents) == ["dev.local", "gsd.home.vinny.dev", "home.vinny.dev"])
  }

  @Test("A file with only the stock entries yields no names")
  func stockFileIsEmpty() {
    let contents = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n"
    #expect(HostsFile.loopbackNames(in: contents).isEmpty)
  }
}

/// Live read inside the sandboxed TEST_HOST: proves the App Sandbox lets
/// the app read /etc/hosts. The names themselves vary per Mac.
@Suite("Hosts file live")
struct HostsFileLiveTests {
  @Test("Sandboxed read of /etc/hosts returns a list")
  func sandboxedRead() throws {
    let names = try #require(HostsFile.readLoopbackNames())
    #expect(names.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
  }
}

@Suite("Store hostname aliases")
@MainActor
struct StoreHostnamesTests {
  @Test("Opening the popover loads the loopback names through the injected reader")
  func popoverLoadsNames() {
    let suiteName = "com.vinnycarpenter.SystemHeadroomTests.hosts.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = MonitorStore(
      defaults: defaults, capability: .sandboxed,
      terminator: ProcessTerminator(
        runningApplication: { _ in nil },
        currentStartIdentity: { _ in nil },
        sendSignal: { _, _ in 0 }),
      alertDelivery: RecordingAlertDelivery(),
      hostnamesReader: { ["gsd.home.vinny.dev"] })

    #expect(store.localHostnames.isEmpty)
    store.popoverDidAppear()
    defer { store.popoverDidDisappear() }
    #expect(store.localHostnames == ["gsd.home.vinny.dev"])
  }
}
