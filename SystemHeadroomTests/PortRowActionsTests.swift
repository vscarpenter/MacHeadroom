import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Port row actions")
struct PortRowActionsTests {
  @Test("TCP ports open as http localhost URLs")
  func tcpURL() {
    let port = ListeningPort(number: 3000, transport: .tcp)
    #expect(PortRowActions.url(for: port) == URL(string: "http://localhost:3000"))
  }

  @Test("UDP ports have no URL")
  func udpURL() {
    #expect(PortRowActions.url(for: ListeningPort(number: 5353, transport: .udp)) == nil)
  }

  @Test("Address copies as localhost and port, no locale grouping")
  func address() {
    #expect(
      PortRowActions.address(for: ListeningPort(number: 65000, transport: .tcp))
        == "localhost:65000")
  }

  @Test(
    "Submenus start above four ports",
    arguments: [(1, false), (4, false), (5, true), (7, true)])
  func submenuCutoff(count: Int, expected: Bool) {
    #expect(PortRowActions.usesSubmenus(portCount: count) == expected)
  }
}

@Suite("Port row actions, hostname aliases")
struct PortRowActionsAliasTests {
  @Test("Only TCP 80 and 443 count as web ports")
  func webPorts() {
    #expect(PortRowActions.isWebPort(ListeningPort(number: 443, transport: .tcp)))
    #expect(PortRowActions.isWebPort(ListeningPort(number: 80, transport: .tcp)))
    #expect(!PortRowActions.isWebPort(ListeningPort(number: 3000, transport: .tcp)))
    #expect(!PortRowActions.isWebPort(ListeningPort(number: 443, transport: .udp)))
  }

  @Test("Alias URLs take the scheme from the port and drop the port suffix")
  func aliasURLs() {
    let host = "gsd.home.vinny.dev"
    #expect(
      PortRowActions.url(for: ListeningPort(number: 443, transport: .tcp), host: host)
        == URL(string: "https://gsd.home.vinny.dev"))
    #expect(
      PortRowActions.url(for: ListeningPort(number: 80, transport: .tcp), host: host)
        == URL(string: "http://gsd.home.vinny.dev"))
    #expect(PortRowActions.url(for: ListeningPort(number: 3000, transport: .tcp), host: host) == nil)
    #expect(PortRowActions.url(for: ListeningPort(number: 443, transport: .udp), host: host) == nil)
  }

  @Test("The preferred web port is 443 when present, else 80, else nil")
  func preferredWebPort() {
    let both = [ListeningPort(number: 80, transport: .tcp), ListeningPort(number: 443, transport: .tcp)]
    #expect(PortRowActions.preferredWebPort(in: both)?.number == 443)
    #expect(PortRowActions.preferredWebPort(in: [both[0]])?.number == 80)
    #expect(PortRowActions.preferredWebPort(in: [ListeningPort(number: 3000, transport: .tcp)]) == nil)
  }
}
