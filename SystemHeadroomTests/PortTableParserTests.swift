import Foundation
import Testing

@testable import SystemHeadroom

// Synthetic pcblist_n buffers composed from the real C structs, so field
// offsets in tests and parser can never drift apart. Records in real
// buffers are 8-byte aligned and xgn_len may exclude the pad, which is
// why the builder and the parser both round up to 8.

private func padded8(_ data: Data) -> Data {
  let remainder = data.count % 8
  guard remainder != 0 else { return data }
  return data + Data(repeating: 0, count: 8 - remainder)
}

private func record<T>(_ value: T) -> Data {
  padded8(withUnsafeBytes(of: value) { Data($0) })
}

private func genHeader() -> Data {
  var gen = mh_xinpgen()
  gen.xig_len = UInt32(MemoryLayout<mh_xinpgen>.size)
  return record(gen)
}

private func socketRecord(lastPid: Int32, ePid: Int32 = 0) -> Data {
  var sock = mh_xsocket_n()
  sock.xso_len = UInt32(MemoryLayout<mh_xsocket_n>.size)
  sock.xso_kind = UInt32(MH_XSO_SOCKET)
  sock.so_last_pid = lastPid
  sock.so_e_pid = ePid
  return record(sock)
}

/// Real xnu xinpcb_n / xtcpcb_n records are far larger than our prefix
/// structs; the trailing-xinpgen terminator check relies on every real
/// record being longer than 24 bytes, so fixtures must be too. The
/// parser reads only the prefix; the rest is declared length + padding.
private func prefixRecord<T>(_ value: T, realLength: Int) -> Data {
  let prefix = withUnsafeBytes(of: value) { Data($0) }
  return padded8(prefix + Data(repeating: 0, count: realLength - prefix.count))
}

private func inpcbRecord(localPort: UInt16, foreignPort: UInt16 = 0) -> Data {
  var inp = mh_xinpcb_n_prefix()
  inp.xi_len = 128
  inp.xi_kind = UInt32(MH_XSO_INPCB)
  inp.inp_lport = localPort.bigEndian
  inp.inp_fport = foreignPort.bigEndian
  return prefixRecord(inp, realLength: 128)
}

private func tcpcbRecord(state: Int32) -> Data {
  var tcp = mh_xtcpcb_n_prefix()
  tcp.xt_len = 224
  tcp.xt_kind = UInt32(MH_XSO_TCPCB)
  tcp.t_state = state
  return prefixRecord(tcp, realLength: 224)
}

/// An unknown record kind a future macOS might add; the parser must skip it.
private func unknownRecord() -> Data {
  var gen = mh_xgen_n()
  gen.xgn_len = 48
  gen.xgn_kind = 0x400
  return padded8(withUnsafeBytes(of: gen) { Data($0) } + Data(repeating: 0, count: 40))
}

private func table(_ entries: Data...) -> Data {
  genHeader() + entries.reduce(Data(), +) + genHeader()
}

@Suite("Port table parser")
struct PortTableParserTests {
  private let emptyUDP = table()

  @Test("One IPv4 TCP listener parses with owner pid")
  func tcpListener() {
    let tcp = table(
      inpcbRecord(localPort: 3000) + socketRecord(lastPid: 4242)
        + tcpcbRecord(state: MH_TCPS_LISTEN))
    let records = PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP)
    #expect(records == [
      SocketRecord(
        transport: .tcp, portNumber: 3000, pid: 4242, effectivePid: 0,
        tcpState: MH_TCPS_LISTEN)
    ])
  }

  @Test("Two consecutive entries keep their own pid-port association")
  func noCrossEntryShift() {
    let tcp = table(
      inpcbRecord(localPort: 80) + socketRecord(lastPid: 874)
        + tcpcbRecord(state: MH_TCPS_LISTEN),
      inpcbRecord(localPort: 58906) + socketRecord(lastPid: 913)
        + tcpcbRecord(state: MH_TCPS_LISTEN))
    let records = PortTableParser.listeningSockets(tcpTable: tcp, udpTable: table())
    #expect(records == [
      SocketRecord(
        transport: .tcp, portNumber: 80, pid: 874, effectivePid: 0,
        tcpState: MH_TCPS_LISTEN),
      SocketRecord(
        transport: .tcp, portNumber: 58906, pid: 913, effectivePid: 0,
        tcpState: MH_TCPS_LISTEN),
    ])
  }

  @Test("Established TCP sockets are filtered out")
  func establishedFiltered() {
    let tcp = table(
      inpcbRecord(localPort: 3000, foreignPort: 443) + socketRecord(lastPid: 4242)
        + tcpcbRecord(state: 4))
    #expect(
      PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP) == [])
  }

  @Test("Bound unconnected UDP socket parses; connected UDP is filtered")
  func udpFilter() {
    let udp = table(
      inpcbRecord(localPort: 5353) + socketRecord(lastPid: 99),
      inpcbRecord(localPort: 60000, foreignPort: 443) + socketRecord(lastPid: 99))
    let records = PortTableParser.listeningSockets(tcpTable: table(), udpTable: udp)
    #expect(records == [
      SocketRecord(
        transport: .udp, portNumber: 5353, pid: 99, effectivePid: 0, tcpState: nil)
    ])
  }

  @Test("IPv4 and IPv6 twins of the same listener dedupe to one record")
  func dualStackDedupe() {
    let twin =
      inpcbRecord(localPort: 8080) + socketRecord(lastPid: 7)
      + tcpcbRecord(state: MH_TCPS_LISTEN)
    let records = PortTableParser.listeningSockets(
      tcpTable: table(twin, twin), udpTable: emptyUDP)
    #expect(records?.count == 1)
  }

  @Test("Unknown record kinds are skipped, not fatal")
  func unknownKindSkipped() {
    let tcp = table(
      inpcbRecord(localPort: 3000) + unknownRecord() + socketRecord(lastPid: 4242)
        + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(
      PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP)?.count == 1)
  }

  @Test("Records longer than our structs (appended fields) still parse")
  func appendedFieldsTolerated() {
    var sock = mh_xsocket_n()
    sock.xso_len = UInt32(MemoryLayout<mh_xsocket_n>.size + 16)
    sock.xso_kind = UInt32(MH_XSO_SOCKET)
    sock.so_last_pid = 4242
    let grown = padded8(
      withUnsafeBytes(of: sock) { Data($0) } + Data(repeating: 0, count: 16))
    let tcp = table(
      inpcbRecord(localPort: 3000) + grown + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(
      PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP)?.count == 1)
  }

  @Test("A socket record shorter than our struct is layout drift: whole table rejected")
  func shrunkenRecordRejected() {
    var gen = mh_xgen_n()
    gen.xgn_len = 32
    gen.xgn_kind = UInt32(MH_XSO_SOCKET)
    let shrunken = padded8(
      withUnsafeBytes(of: gen) { Data($0) } + Data(repeating: 0, count: 24))
    let tcp = table(
      inpcbRecord(localPort: 3000) + shrunken + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP) == nil)
  }

  @Test("Truncated buffer is rejected, empty table parses as empty")
  func truncationAndEmpty() {
    let tcp = table(
      inpcbRecord(localPort: 80) + socketRecord(lastPid: 1)
        + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(
      PortTableParser.listeningSockets(
        tcpTable: tcp.prefix(tcp.count - 12), udpTable: emptyUDP) == nil)
    #expect(PortTableParser.listeningSockets(tcpTable: table(), udpTable: table()) == [])
    #expect(PortTableParser.listeningSockets(tcpTable: nil, udpTable: emptyUDP) == nil)
  }
}
