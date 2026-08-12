enum PortTransport: String, Sendable, Equatable, Hashable, CaseIterable {
  case tcp
  case udp
}

struct ListeningPort: Sendable, Equatable, Hashable, Comparable {
  let number: UInt16
  let transport: PortTransport

  static func < (lhs: ListeningPort, rhs: ListeningPort) -> Bool {
    if lhs.number != rhs.number { return lhs.number < rhs.number }
    return lhs.transport == .tcp && rhs.transport == .udp
  }
}

/// One listening socket as parsed from a pcblist_n table. `tcpState` is
/// nil for UDP records; TCP records that reach consumers are always
/// LISTEN (the parser filters), the field exists so tests can assert
/// the filter itself.
struct SocketRecord: Sendable, Equatable, Hashable {
  let transport: PortTransport
  let portNumber: UInt16
  let pid: Int32
  let effectivePid: Int32
  let tcpState: Int32?
}
