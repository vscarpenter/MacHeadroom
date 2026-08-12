import Testing

@testable import SystemHeadroom

@Suite("Port table ABI")
struct PortTableABITests {
  /// The size constants freeze the hand-copied xnu layouts: an
  /// accidental header edit fails here at the exact struct, and the
  /// netstat cross-check in PortsSamplerLiveTests validates the same
  /// layouts against the live kernel.
  @Test("Copied xnu layouts have the expected sizes")
  func abiSizes() {
    // pack(4) sizes: without the pragma, xsocket_n pads to 80 and the
    // pid fields land 4 bytes off. 76 is the canary.
    #expect(MemoryLayout<mh_xinpgen>.size == 24)
    #expect(MemoryLayout<mh_xgen_n>.size == 8)
    #expect(MemoryLayout<mh_xsocket_n>.size == 76)
    #expect(MemoryLayout<mh_xinpcb_n_prefix>.size == 20)
    #expect(MemoryLayout<mh_xtcpcb_n_prefix>.size == 40)
  }

  @Test("ListeningPort sorts by number, tcp before udp")
  func listeningPortOrder() {
    let ports: [ListeningPort] = [
      ListeningPort(number: 5353, transport: .udp),
      ListeningPort(number: 3000, transport: .udp),
      ListeningPort(number: 3000, transport: .tcp),
    ]
    #expect(ports.sorted() == [
      ListeningPort(number: 3000, transport: .tcp),
      ListeningPort(number: 3000, transport: .udp),
      ListeningPort(number: 5353, transport: .udp),
    ])
  }
}
