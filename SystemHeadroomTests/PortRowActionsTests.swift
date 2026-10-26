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
