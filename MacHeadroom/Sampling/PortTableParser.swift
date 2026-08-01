import Foundation

/// Pure parser for net.inet.{tcp,udp}.pcblist_n buffers. No syscalls, no
/// logging: nil means "this buffer cannot be trusted" and the caller
/// decides what to do about it. Records are self-framing (xgn_len /
/// xgn_kind) and 8-byte aligned; unknown kinds are skipped so appended
/// record types in a future macOS do not break the walk. A recognized
/// record SHORTER than our copied struct is layout drift — the whole
/// table is rejected rather than risk misread pids.
enum PortTableParser {
  static func listeningSockets(tcpTable: Data?, udpTable: Data?) -> [SocketRecord]? {
    guard
      let tcpTable, let udpTable,
      let tcp = parse(table: tcpTable, transport: .tcp),
      let udp = parse(table: udpTable, transport: .udp)
    else { return nil }
    var seen = Set<SocketRecord>()
    return (tcp + udp).filter { seen.insert($0).inserted }
  }

  private struct PendingEntry {
    var pid: Int32
    var effectivePid: Int32
    var localPort: UInt16?
    var foreignPort: UInt16?
    var tcpState: Int32?
  }

  private static func parse(table: Data, transport: PortTransport) -> [SocketRecord]? {
    let genSize = MemoryLayout<mh_xinpgen>.size
    guard table.count >= genSize, let gen = load(mh_xinpgen.self, from: table, at: 0)
    else { return nil }
    var records: [SocketRecord] = []
    var pending: PendingEntry?

    var offset = roundUp8(Int(gen.xig_len))
    guard offset >= genSize else { return nil }

    while offset + MemoryLayout<mh_xgen_n>.size <= table.count {
      guard let header = load(mh_xgen_n.self, from: table, at: offset) else { return nil }
      let length = Int(header.xgn_len)
      // Bounds first, break second: a table truncated inside its trailing
      // xinpgen (or any record) must reject, not silently succeed.
      guard length >= MemoryLayout<mh_xgen_n>.size,
        offset + length <= table.count
      else { return nil }
      if length <= genSize { break }

      switch Int32(header.xgn_kind) {
      case MH_XSO_SOCKET:
        guard length >= MemoryLayout<mh_xsocket_n>.size,
          let sock = load(mh_xsocket_n.self, from: table, at: offset)
        else { return nil }
        if let done = pending { append(done, transport: transport, to: &records) }
        pending = PendingEntry(
          pid: sock.so_last_pid, effectivePid: sock.so_e_pid,
          localPort: nil, foreignPort: nil, tcpState: nil)
      case MH_XSO_INPCB:
        guard length >= MemoryLayout<mh_xinpcb_n_prefix>.size,
          let inp = load(mh_xinpcb_n_prefix.self, from: table, at: offset)
        else { return nil }
        pending?.localPort = UInt16(bigEndian: inp.inp_lport)
        pending?.foreignPort = UInt16(bigEndian: inp.inp_fport)
      case MH_XSO_TCPCB:
        guard length >= MemoryLayout<mh_xtcpcb_n_prefix>.size,
          let tcp = load(mh_xtcpcb_n_prefix.self, from: table, at: offset)
        else { return nil }
        pending?.tcpState = tcp.t_state
      default:
        break
      }
      offset += roundUp8(length)
    }

    if let done = pending { append(done, transport: transport, to: &records) }
    return records
  }

  private static func append(
    _ entry: PendingEntry, transport: PortTransport, to records: inout [SocketRecord]
  ) {
    guard let localPort = entry.localPort, localPort != 0 else { return }
    switch transport {
    case .tcp:
      guard entry.tcpState == MH_TCPS_LISTEN else { return }
    case .udp:
      guard entry.foreignPort == 0 else { return }
    }
    records.append(
      SocketRecord(
        transport: transport, portNumber: localPort, pid: entry.pid,
        effectivePid: entry.effectivePid, tcpState: entry.tcpState))
  }

  private static func load<T>(_ type: T.Type, from data: Data, at offset: Int) -> T? {
    let size = MemoryLayout<T>.size
    guard offset >= 0, offset + size <= data.count else { return nil }
    return data.withUnsafeBytes { raw in
      raw.loadUnaligned(fromByteOffset: offset, as: T.self)
    }
  }

  private static func roundUp8(_ value: Int) -> Int {
    (value + 7) & ~7
  }
}
