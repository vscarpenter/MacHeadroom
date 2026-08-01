import Foundation
import Testing

@testable import MacHeadroom

/// Live tests inside the sandboxed TEST_HOST: they re-prove seatbelt
/// policy and the hand-copied pcblist_n layouts on every run. The oracle
/// is /usr/sbin/netstat -anv — Apple's own parser of the same sysctl —
/// because the sandbox denies bind() outright, so no test here can
/// create its own listener (Evidence/ports-spike/). netstat must be
/// invoked by absolute path with no shell: exec of non-system binaries
/// is denied too.
@Suite("Ports sampler live", .serialized)
struct PortsSamplerLiveTests {
  @Test("Sandboxed fetch returns parseable tables")
  func fetchAndParse() throws {
    let tcp = try #require(PortTableSampler.fetchTCPTable())
    let udp = try #require(PortTableSampler.fetchUDPTable())
    #expect(tcp.count >= MemoryLayout<mh_xinpgen>.size * 2)
    let records = try #require(
      PortTableParser.listeningSockets(tcpTable: tcp, udpTable: udp))
    // A macOS box always has system listeners (rapportd, mDNSResponder…).
    #expect(!records.isEmpty)
    #expect(records.allSatisfy { $0.pid > 0 && $0.portNumber > 0 })
  }

  @Test("Parsed TCP listeners match netstat's parse of the same table")
  func netstatCrossCheck() throws {
    var ours: Set<String> = []
    var theirs: Set<String> = []
    for _ in 0..<2 {  // one retry absorbs listener churn between the reads
      let records = try #require(
        PortTableParser.listeningSockets(
          tcpTable: PortTableSampler.fetchTCPTable(),
          udpTable: PortTableSampler.fetchUDPTable()))
      ours = Set(
        records.filter { $0.transport == .tcp }.map { "\($0.portNumber):\($0.pid)" })
      theirs = try Self.netstatTCPListeners()
      if ours == theirs { break }
    }
    #expect(ours == theirs)
  }

  @Test("UDP parse substantially agrees with netstat")
  func udpAgreement() throws {
    let records = try #require(
      PortTableParser.listeningSockets(
        tcpTable: PortTableSampler.fetchTCPTable(),
        udpTable: PortTableSampler.fetchUDPTable()))
    let ours = Set(
      records.filter { $0.transport == .udp }.map { "\($0.portNumber):\($0.pid)" })
    let theirs = try Self.netstatUDPSockets()
    #expect(!ours.isEmpty && !theirs.isEmpty)
    // UDP binds churn (QUIC, DNS); require majority overlap, not equality.
    #expect(ours.intersection(theirs).count * 2 >= theirs.count)
  }

  @Test("Tick carries sockets and fallback names for non-snapshot owners")
  func tickCarriesSockets() async throws {
    let service = SamplerService()
    _ = await service.tick(convention: .machineCapacity)  // priming tick
    let tick = await service.tick(convention: .machineCapacity)
    let sockets = try #require(tick.sockets)
    #expect(!sockets.isEmpty)
    let snapshotPIDs = Set(tick.processes.map(\.snapshot.pid))
    for (pid, name) in tick.socketFallbackNames {
      #expect(!snapshotPIDs.contains(pid))
      #expect(!name.isEmpty)
    }
    // Every socket owner is accounted for: in the snapshot set, in the
    // fallback names, or gone since the sweep (rare churn; bounded).
    let coveredPIDs = snapshotPIDs.union(tick.socketFallbackNames.keys)
    let uncovered = sockets.filter { !coveredPIDs.contains($0.pid) }
    #expect(uncovered.count < max(1, sockets.count / 4))
  }

  private static func netstatTCPListeners() throws -> Set<String> {
    try netstatPairs(protoArg: "tcp") { fields in
      fields.count > 5 && fields[5] == "LISTEN"
    }
  }

  private static func netstatUDPSockets() throws -> Set<String> {
    try netstatPairs(protoArg: "udp") { fields in
      fields.count > 4 && fields[4] == "*.*"
    }
  }

  /// Parses netstat -anv lines into "port:pid" pairs. Process names can
  /// contain spaces and IPv6 addresses contain colons, so the pid comes
  /// from the token directly before the 5-hex-digit state field (an
  /// IPv6 ":1." never matches because a dot follows, not whitespace);
  /// the port is the substring after the last "." of the local address.
  private static func netstatPairs(
    protoArg: String, isWanted: ([Substring]) -> Bool
  ) throws -> Set<String> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
    process.arguments = ["-anv", "-p", protoArg]
    let stdout = Pipe()
    process.standardOutput = stdout
    try process.run()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let pidPattern = /:(\d+)\s+[0-9a-f]{5}\s/
    var pairs: Set<String> = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      guard fields.count > 3, fields[0].hasPrefix(protoArg.prefix(3)),
        isWanted(fields),
        let portText = fields[3].split(separator: ".").last,
        let port = UInt16(portText),
        let pidMatch = line.firstMatch(of: pidPattern),
        let pid = Int32(pidMatch.1)
      else { continue }
      pairs.insert("\(port):\(pid)")
    }
    return pairs
  }
}
