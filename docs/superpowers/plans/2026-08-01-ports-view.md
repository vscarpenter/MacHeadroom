# Ports View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Ports segment to the popover listing every listening TCP/UDP port grouped by owning app, with quit buttons in the Direct build only.

**Architecture:** A sysctl-based sampler (`net.inet.{tcp,udp}.pcblist_n`) fetches raw kernel tables; a pure parser walks the self-framing records into `SocketRecord`s; a pure `PortGroupBuilder` folds them onto the existing `AppGroup`s; the store publishes `portGroups`; both popover skins gain a third tab. Spec: `docs/superpowers/specs/2026-08-01-ports-view-design.md`. Evidence: `Evidence/ports-spike/`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing (`@Test`/`#expect`), one C header for xnu ABI structs via bridging headers. Zero dependencies, no new entitlements.

## Global Constraints

- macOS 14+ deployment, Swift 6 strict concurrency, warnings as errors. Every new type crossing the actor boundary must be `Sendable`.
- Zero third-party dependencies; no network use; entitlements files must not change.
- Popover ideal height must never depend on list content (`PopoverLayoutTests` invariant). Ports rows are uniform height; badge overflow uses a `+N` chip, never wrapping.
- Process names are 16-char truncated (`p_comm`); `ProcessGlossary` keys are truncated form.
- The Mac App Store build must show no quit UI. Quit affordances stay behind `store.canTerminate` (existing pattern) and appear only on rows whose `PortGroup.appGroup != nil`.
- Build: `xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug build`
- Test: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64'` (append `-only-testing:SystemHeadroomTests/<Suite>` for one suite). Tests run inside the real sandboxed app (TEST_HOST) — live tests exercise real seatbelt policy.
- **Adding files to the project**: classic PBXGroups, hand-rolled IDs. Each new `.swift` file needs 4 pbxproj edits: PBXBuildFile, PBXFileReference, owning group's `children`, target Sources phase. ID series: Sampling `D1…`/`D2…` (next free: `…0008`), Grouping `F1…`/`F2…` (next: `…0004`), UI `H1…`/`H2…` (next: `…000B`), tests `E1…`/`E2…` (next: `…000C`). A `.h` file needs only PBXFileReference + group child (headers are not compiled into a Sources phase).
- Commit after every task with a Conventional Commit message ending in the trailer `Claude-Session: https://claude.ai/code/session_01MvodFnpySRf38GBntDqizw` and no Co-Authored-By footer.

---

### Task 1: ABI header, bridging wiring, and port value types

**Files:**
- Create: `SystemHeadroom/Sampling/PortTableABI.h` (C structs copied from xnu)
- Create: `SystemHeadroom/Sampling/PortTypes.swift`
- Modify: `Configuration/Shared.xcconfig` (bridging header setting — see Step 3 fallback)
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (file references + Sources entries)
- Test: `SystemHeadroomTests/PortTableABITests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: C types `xinpgen`, `xgen_n`, `mh_xsocket_n`, `mh_xinpcb_n_prefix`, `mh_xtcpcb_n_prefix`; constants `MH_XSO_SOCKET`, `MH_XSO_INPCB`, `MH_XSO_TCPCB`, `MH_TCPS_LISTEN`; Swift types `PortTransport` (`.tcp`/`.udp`), `ListeningPort { number: UInt16, transport: PortTransport }`, `SocketRecord { transport: PortTransport, portNumber: UInt16, pid: Int32, effectivePid: Int32, tcpState: Int32? }`. All `Sendable, Equatable, Hashable` (ListeningPort additionally `Comparable`: by number, `.tcp` before `.udp` on ties).

- [ ] **Step 1: Write the ABI header**

The layouts come from xnu (`bsd/sys/socketvar.h`, `bsd/netinet/in_pcb.h`, `bsd/netinet/tcp_var.h`); they are not in the macOS SDK. `mh_xinpcb_n_prefix` and `mh_xtcpcb_n_prefix` are deliberate prefixes — records advance by `xgn_len`, so trailing fields we never read are omitted; `mh_xsocket_n` must be complete because the pids sit at its end. Task 3's netstat cross-check is the oracle that these copies are right; if it fails, re-derive from the xnu source matching `uname -r` before touching anything else.

```c
// PortTableABI.h — xnu pcblist_n record layouts (not in the public SDK).
// Copied for sysctl net.inet.{tcp,udp}.pcblist_n parsing; see
// Evidence/ports-spike/ and SANDBOX_NOTES.md "Port enumeration spike".
#ifndef PORT_TABLE_ABI_H
#define PORT_TABLE_ABI_H

#include <netinet/in.h>
#include <sys/types.h>

#define MH_XSO_SOCKET 0x001
#define MH_XSO_RCVBUF 0x002
#define MH_XSO_SNDBUF 0x004
#define MH_XSO_STATS  0x008
#define MH_XSO_INPCB  0x010
#define MH_XSO_TCPCB  0x020

#define MH_TCPS_LISTEN 1

struct mh_xinpgen {
  u_int32_t xig_len;
  u_int32_t xig_count;
  u_int64_t xig_gen;
  u_int64_t xig_sogen;
};

struct mh_xgen_n {
  u_int32_t xgn_len;
  u_int32_t xgn_kind;
};

// Complete copy of xnu's struct xsocket_n: so_last_pid / so_e_pid are
// the last fields, so no prefix trick is possible here.
struct mh_xsocket_n {
  u_int32_t xso_len;
  u_int32_t xso_kind;
  u_int64_t xso_so;
  short so_type;
  u_int32_t so_options;
  short so_linger;
  short so_state;
  u_int64_t so_pcb;
  int xso_protocol;
  int xso_family;
  short so_qlen;
  short so_incqlen;
  short so_qlimit;
  short so_timeo;
  u_short so_error;
  pid_t so_pgid;
  u_int32_t so_oobmark;
  uid_t so_uid;
  pid_t so_last_pid;
  pid_t so_e_pid;
};

// Prefix of xnu's struct xinpcb_n through the ports; records are longer
// (xgn_len governs advancement), we only read these fields.
struct mh_xinpcb_n_prefix {
  u_int32_t xi_len;
  u_int32_t xi_kind;
  u_int64_t xi_inpp;
  u_short inp_fport;
  u_short inp_lport;
};

// Prefix of xnu's struct xtcpcb_n through t_state (t_timer is
// TCPT_NTIMERS_EXT == 4 ints).
struct mh_xtcpcb_n_prefix {
  u_int32_t xt_len;
  u_int32_t xt_kind;
  u_int64_t t_segq;
  int t_dupacks;
  int t_timer[4];
  int t_state;
};

#endif
```

- [ ] **Step 2: Write PortTypes.swift**

```swift
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
```

- [ ] **Step 3: Wire bridging headers**

Check whether `Configuration/Shared.xcconfig` is attached to both the app and test targets (look at `baseConfigurationReference` in the pbxproj). If yes, add one line to it:

```
SWIFT_OBJC_BRIDGING_HEADER = SystemHeadroom/Sampling/PortTableABI.h
```

If the xcconfig is not attached to both targets, instead add `SWIFT_OBJC_BRIDGING_HEADER = SystemHeadroom/Sampling/PortTableABI.h;` to all four XCBuildConfiguration blocks (app Debug/Release, tests Debug/Release) in the pbxproj.

- [ ] **Step 4: Register files in pbxproj**

Per Global Constraints: `PortTypes.swift` gets `D10000000000000000000008`/`D20000000000000000000008` (BuildFile/FileRef, Sampling group, app Sources). `PortTableABI.h` gets FileRef `D20000000000000000000009` + Sampling group child only. `PortTableABITests.swift` gets `E1000000000000000000000C`/`E2000000000000000000000C` (tests group, test Sources).

- [ ] **Step 5: Write the failing test**

```swift
import Testing

@testable import SystemHeadroom

@Suite("Port table ABI")
struct PortTableABITests {
  @Test("Copied xnu layouts have the expected sizes")
  func abiSizes() {
    #expect(MemoryLayout<mh_xinpgen>.size == 24)
    #expect(MemoryLayout<mh_xgen_n>.size == 8)
    // xsocket_n: computed from the C layout; pids at the tail.
    #expect(MemoryLayout<mh_xsocket_n>.size == 80)
    #expect(MemoryLayout<mh_xinpcb_n_prefix>.size == 24)
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
```

If `abiSizes` fails on the `mh_xsocket_n` line, the C compiler computed a different size than 80 — print `MemoryLayout<mh_xsocket_n>.size`, verify the struct against xnu source, and fix the **header**, then update the expected constant. The size constants exist to freeze the layout so an accidental header edit fails loudly.

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodebuild test … -only-testing:SystemHeadroomTests/PortTableABITests`
Expected: build FAILS (types not yet in project) or tests fail — either confirms red.

- [ ] **Step 7: Build, run test to verify it passes**

Expected: PASS. If the bridging header breaks the build for unrelated files, the header is being imported somewhere it shouldn't; it must contain only C declarations and includes shown above.

- [ ] **Step 8: Commit**

```bash
git add SystemHeadroom/Sampling/PortTableABI.h SystemHeadroom/Sampling/PortTypes.swift SystemHeadroomTests/PortTableABITests.swift SystemHeadroom.xcodeproj/project.pbxproj Configuration/Shared.xcconfig
git commit -m "feat(sampling): add pcblist_n ABI header and port value types"
```

---

### Task 2: PortTableParser (pure) with synthetic-buffer tests

**Files:**
- Create: `SystemHeadroom/Sampling/PortTableParser.swift`
- Test: `SystemHeadroomTests/PortTableParserTests.swift`
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (`D…000A` for parser, `E…000D` for tests)

**Interfaces:**
- Consumes: Task 1's C types and `SocketRecord`.
- Produces: `enum PortTableParser { static func listeningSockets(tcpTable: Data?, udpTable: Data?) -> [SocketRecord]? }`. Contract: nil if either input is nil or either table is malformed (fetch failed / layout drift); `[]` if genuinely nothing is listening. Output is deduped on `(pid, transport, portNumber)` (IPv4/IPv6 twins collapse) with no defined order.

- [ ] **Step 1: Write the failing tests, with a synthetic buffer builder**

The builder composes buffers from the real C structs so field offsets in tests and parser can never drift apart. Note `withUnsafeBytes(of:)` + `Data` padding to 8-byte multiples — records in real buffers are 8-aligned and `xgn_len` may exclude the pad, which is why the builder and parser both round up.

```swift
import Foundation
import Testing

@testable import SystemHeadroom

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

private func inpcbRecord(localPort: UInt16, foreignPort: UInt16 = 0) -> Data {
  var inp = mh_xinpcb_n_prefix()
  inp.xi_len = UInt32(MemoryLayout<mh_xinpcb_n_prefix>.size)
  inp.xi_kind = UInt32(MH_XSO_INPCB)
  inp.inp_lport = localPort.bigEndian
  inp.inp_fport = foreignPort.bigEndian
  return record(inp)
}

private func tcpcbRecord(state: Int32) -> Data {
  var tcp = mh_xtcpcb_n_prefix()
  tcp.xt_len = UInt32(MemoryLayout<mh_xtcpcb_n_prefix>.size)
  tcp.xt_kind = UInt32(MH_XSO_TCPCB)
  tcp.t_state = state
  return record(tcp)
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
      socketRecord(lastPid: 4242) + inpcbRecord(localPort: 3000)
        + tcpcbRecord(state: MH_TCPS_LISTEN))
    let records = PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP)
    #expect(records == [
      SocketRecord(
        transport: .tcp, portNumber: 3000, pid: 4242, effectivePid: 0,
        tcpState: MH_TCPS_LISTEN)
    ])
  }

  @Test("Established TCP sockets are filtered out")
  func establishedFiltered() {
    let tcp = table(
      socketRecord(lastPid: 4242) + inpcbRecord(localPort: 3000, foreignPort: 443)
        + tcpcbRecord(state: 4))  // ESTABLISHED
    #expect(
      PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP) == [])
  }

  @Test("Bound unconnected UDP socket parses; connected UDP is filtered")
  func udpFilter() {
    let udp = table(
      socketRecord(lastPid: 99) + inpcbRecord(localPort: 5353),
      socketRecord(lastPid: 99) + inpcbRecord(localPort: 60000, foreignPort: 443))
    let records = PortTableParser.listeningSockets(tcpTable: table(), udpTable: udp)
    #expect(records == [
      SocketRecord(
        transport: .udp, portNumber: 5353, pid: 99, effectivePid: 0, tcpState: nil)
    ])
  }

  @Test("IPv4 and IPv6 twins of the same listener dedupe to one record")
  func dualStackDedupe() {
    let twin =
      socketRecord(lastPid: 7) + inpcbRecord(localPort: 8080)
      + tcpcbRecord(state: MH_TCPS_LISTEN)
    let records = PortTableParser.listeningSockets(
      tcpTable: table(twin, twin), udpTable: emptyUDP)
    #expect(records?.count == 1)
  }

  @Test("Unknown record kinds are skipped, not fatal")
  func unknownKindSkipped() {
    let tcp = table(
      socketRecord(lastPid: 4242) + unknownRecord() + inpcbRecord(localPort: 3000)
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
    let grown = padded8(withUnsafeBytes(of: sock) { Data($0) } + Data(repeating: 0, count: 16))
    let tcp = table(
      grown + inpcbRecord(localPort: 3000) + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(
      PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP)?.count == 1)
  }

  @Test("A socket record shorter than our struct is layout drift: whole table rejected")
  func shrunkenRecordRejected() {
    var gen = mh_xgen_n()
    gen.xgn_len = 32  // < MemoryLayout<mh_xsocket_n>.size
    gen.xgn_kind = UInt32(MH_XSO_SOCKET)
    let shrunken = padded8(withUnsafeBytes(of: gen) { Data($0) } + Data(repeating: 0, count: 24))
    let tcp = table(shrunken + inpcbRecord(localPort: 3000) + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(PortTableParser.listeningSockets(tcpTable: tcp, udpTable: emptyUDP) == nil)
  }

  @Test("Truncated buffer is rejected, empty table parses as empty")
  func truncationAndEmpty() {
    let tcp = table(
      socketRecord(lastPid: 1) + inpcbRecord(localPort: 80)
        + tcpcbRecord(state: MH_TCPS_LISTEN))
    #expect(
      PortTableParser.listeningSockets(
        tcpTable: tcp.prefix(tcp.count - 12), udpTable: emptyUDP) == nil)
    #expect(PortTableParser.listeningSockets(tcpTable: table(), udpTable: table()) == [])
    #expect(PortTableParser.listeningSockets(tcpTable: nil, udpTable: emptyUDP) == nil)
  }
}
```

- [ ] **Step 2: Register the two files in pbxproj, run tests to verify they fail**

Expected: build failure (`PortTableParser` undefined) — red confirmed.

- [ ] **Step 3: Implement the parser**

```swift
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
    guard table.count >= genSize else { return nil }
    var records: [SocketRecord] = []
    var pending: PendingEntry?

    var offset = roundUp8(load(mh_xinpgen.self, from: table, at: 0)?.xig_len)
    guard offset >= genSize else { return nil }

    while offset + MemoryLayout<mh_xgen_n>.size <= table.count {
      guard let header = load(mh_xgen_n.self, from: table, at: offset) else { return nil }
      let length = Int(header.xgn_len)
      // Bounds first, break second: a table truncated inside its trailing
      // xinpgen (or any record) must reject, not silently succeed.
      guard length >= MemoryLayout<mh_xgen_n>.size,
        offset + length <= table.count
      else { return nil }
      if length <= genSize { break }  // trailing xinpgen terminates the list

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
        break  // rcvbuf, sndbuf, stats, future kinds: not ours to read
      }
      offset += roundUp8(header.xgn_len)
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
    var value: T?
    data.withUnsafeBytes { raw in
      value = raw.loadUnaligned(fromByteOffset: offset, as: T.self)
    }
    return value
  }

  private static func roundUp8<N: BinaryInteger>(_ value: N?) -> Int {
    let raw = Int(value ?? 0)
    return (raw + 7) & ~7
  }
}
```

- [ ] **Step 4: Run the suite, verify all PortTableParserTests pass**

Run: `xcodebuild test … -only-testing:SystemHeadroomTests/PortTableParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/Sampling/PortTableParser.swift SystemHeadroomTests/PortTableParserTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(sampling): parse pcblist_n tables into listening socket records"
```

---

### Task 3: PortTableSampler fetch + live sandbox tests (the ABI tripwire)

**Files:**
- Create: `SystemHeadroom/Sampling/PortTableSampler.swift` (`D…000B`)
- Test: `SystemHeadroomTests/PortsSamplerLiveTests.swift` (`E…000E`)
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PortTableParser.listeningSockets(tcpTable:udpTable:)`, `SocketRecord`.
- Produces: `enum PortTableSampler { static func fetchTCPTable() -> Data?; static func fetchUDPTable() -> Data? }`. nil = sysctl failure after retries.

- [ ] **Step 1: Write the failing live tests**

These run inside the sandboxed TEST_HOST — they re-prove seatbelt policy and struct layout on every run. The oracle is `/usr/sbin/netstat -anv`, which parses the same sysctl with Apple's own copy of the structs. Measured facts that shape this test (Evidence/ports-spike/): the sandbox denies `bind()` (no self-listener possible), execs `/usr/sbin/netstat` fine, and denies exec of non-system binaries — so absolute path, no shell, no pipelines.

netstat line parsing: LISTEN rows look like
`tcp4  0 0  *.8123  *.*  LISTEN  0 0 131072 131072  Python:77444 00106 …`.
Process names can contain spaces (`Google Chrome He:33693`), and IPv6 addresses contain colons, so the pid is extracted with the regex `:(\d+)\s+[0-7]{5}\s` (pid token directly before the 5-digit octal state field); the local port is the substring after the last `.` of field 4 (works for `*.8123` and `::1.3000` alike).

```swift
import Foundation
import Testing

@testable import SystemHeadroom

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

  private static func netstatTCPListeners() throws -> Set<String> {
    try netstatPairs(protoArg: "tcp") { fields in fields.count > 5 && fields[5] == "LISTEN" }
  }

  private static func netstatUDPSockets() throws -> Set<String> {
    try netstatPairs(protoArg: "udp") { fields in fields.count > 4 && fields[4] == "*.*" }
  }

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
    let pidPattern = /:(\d+)\s+[0-7]{5}\s/
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
```

- [ ] **Step 2: Register files, run tests to verify they fail**

Expected: build failure (`PortTableSampler` undefined) — red confirmed.

- [ ] **Step 3: Implement the fetcher**

Same grow-and-retry idiom as `ProcessTableSampler.enumerateProcesses` (the table can grow between size query and fetch):

```swift
import Darwin
import Foundation

/// Fetches the kernel's TCP and UDP connection tables. This is the same
/// interface netstat -anv reads, and the only port→pid path the App
/// Sandbox permits: the lsof-style fd walk is EPERM for every non-self
/// process (Evidence/ports-spike/). Parsing lives in PortTableParser.
enum PortTableSampler {
  static func fetchTCPTable() -> Data? { fetch("net.inet.tcp.pcblist_n") }
  static func fetchUDPTable() -> Data? { fetch("net.inet.udp.pcblist_n") }

  private static func fetch(_ name: String) -> Data? {
    for _ in 1...3 {
      var byteCount = 0
      guard sysctlbyname(name, nil, &byteCount, nil, 0) == 0, byteCount > 0 else {
        return nil
      }
      var buffer = Data(count: byteCount + byteCount / 4)
      var resultBytes = buffer.count
      let status = buffer.withUnsafeMutableBytes { raw in
        sysctlbyname(name, raw.baseAddress, &resultBytes, nil, 0)
      }
      if status == 0 {
        return buffer.prefix(resultBytes)
      }
      if errno != ENOMEM { return nil }
    }
    return nil
  }
}
```

- [ ] **Step 4: Run the live suite, verify it passes**

Run: `xcodebuild test … -only-testing:SystemHeadroomTests/PortsSamplerLiveTests`
Expected: PASS. **If `netstatCrossCheck` fails while `fetchAndParse` passes, the hand-copied ABI in Task 1's header is wrong — diff our (port, pid) set against netstat's, fix the header against xnu source, and do not proceed until this passes.** This test is the whole risk-containment story; it must be green, not skipped.

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/Sampling/PortTableSampler.swift SystemHeadroomTests/PortsSamplerLiveTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(sampling): fetch pcblist_n tables with netstat cross-check tests"
```

---

### Task 4: Thread sockets through ProcessTableSampler, MonitorTick, SamplerService

**Files:**
- Modify: `SystemHeadroom/Sampling/ProcessTableSampler.swift` (add `sampleTable()`)
- Modify: `SystemHeadroom/Sampling/MonitorTick.swift`
- Modify: `SystemHeadroom/Sampling/SamplerService.swift`
- Test: extend `SystemHeadroomTests/PortsSamplerLiveTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `struct ProcessTable: Sendable { let snapshots: [ProcessSnapshot]; let commandNamesByPID: [Int32: String] }`; `ProcessTableSampler.sampleTable() -> ProcessTable` (existing `sampleReachableProcesses()` becomes `sampleTable().snapshots` — keep it, existing tests use it); `MonitorTick` gains `let sockets: [SocketRecord]?` and `let socketFallbackNames: [Int32: String]` (names for socket-owning pids that have no `ProcessSnapshot` — root listeners; key absent when the process vanished mid-tick).

- [ ] **Step 1: Write the failing test (append to PortsSamplerLiveTests)**

```swift
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
    // fallback names, or gone since the sweep (rare; can't be asserted).
    let coveredPIDs = snapshotPIDs.union(tick.socketFallbackNames.keys)
    let uncovered = sockets.filter { !coveredPIDs.contains($0.pid) }
    #expect(uncovered.count < sockets.count / 4)
  }
```

- [ ] **Step 2: Run, verify it fails** (no `sockets` member on `MonitorTick`).

- [ ] **Step 3: Implement**

`ProcessTableSampler`: extract the current body of `sampleReachableProcesses()` into `sampleTable()`, which also builds `commandNamesByPID` for **every** enumerated pid (all users — `kinfo_proc.p_comm` is readable for all rows even though task info is not):

```swift
struct ProcessTable: Sendable {
  let snapshots: [ProcessSnapshot]
  let commandNamesByPID: [Int32: String]
}

// In ProcessTableSampler:
static func sampleTable() -> ProcessTable {
  let ownUID = geteuid()
  let identities = enumerateProcesses()
  let names = Dictionary(
    identities.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
  let snapshots = identities
    .filter { $0.userID == ownUID }
    .compactMap { identity -> ProcessSnapshot? in
      guard let task = taskMeasurement(for: identity.pid) else { return nil }
      return ProcessSnapshot(
        pid: identity.pid, parentPID: identity.parentPID, userID: identity.userID,
        name: identity.name, startIdentity: identity.startIdentity,
        cpuTimeTicks: task.cpuTimeTicks, residentBytes: task.residentBytes)
    }
  return ProcessTable(snapshots: snapshots, commandNamesByPID: names)
}

static func sampleReachableProcesses() -> [ProcessSnapshot] {
  sampleTable().snapshots
}
```

`MonitorTick`:

```swift
struct MonitorTick: Sendable, Equatable {
  let processes: [ProcessMeasurement]
  let system: SystemSummary
  let sockets: [SocketRecord]?
  let socketFallbackNames: [Int32: String]
}
```

`SamplerService.tick`: replace `let snapshots = ProcessTableSampler.sampleReachableProcesses()` with the table call, fetch+parse the port tables in the same sweep, and log parse failure only on the transition (an actor-held `var lastSocketsFailed = false`), not every tick:

```swift
    let table = ProcessTableSampler.sampleTable()
    let snapshots = table.snapshots
    let sockets = PortTableParser.listeningSockets(
      tcpTable: PortTableSampler.fetchTCPTable(),
      udpTable: PortTableSampler.fetchUDPTable())
    if sockets == nil, !lastSocketsFailed {
      Self.log.fault("port table fetch or parse failed; ports pane unavailable")
    }
    lastSocketsFailed = sockets == nil

    let snapshotPIDs = Set(snapshots.map(\.pid))
    var fallbackNames: [Int32: String] = [:]
    for record in sockets ?? [] where !snapshotPIDs.contains(record.pid) {
      fallbackNames[record.pid] = table.commandNamesByPID[record.pid]
    }
```

with `private static let log = Logger(subsystem: "com.vinnycarpenter.SystemHeadroom", category: "ports")` (`import os`) and both new fields added to the returned `MonitorTick`.

- [ ] **Step 4: Run the full suite** — `SamplerBurstTests` and everything else must stay green (they construct ticks only through `SamplerService`, so no fixture updates are expected; if any test constructs `MonitorTick` directly, add `sockets: nil, socketFallbackNames: [:]`).

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/Sampling/ProcessTableSampler.swift SystemHeadroom/Sampling/MonitorTick.swift SystemHeadroom/Sampling/SamplerService.swift SystemHeadroomTests/PortsSamplerLiveTests.swift
git commit -m "feat(sampling): carry listening sockets and fallback names in each tick"
```

---

### Task 5: PortGroupBuilder (pure) + PortGroup

**Files:**
- Create: `SystemHeadroom/Grouping/PortGroup.swift` (`F…0004`)
- Create: `SystemHeadroom/Grouping/PortGroupBuilder.swift` (`F…0005`)
- Test: `SystemHeadroomTests/PortGroupBuilderTests.swift` (`E…000F`)
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SocketRecord`, `ListeningPort`, `AppGroup`, `ProcessMeasurement`, `ProcessSnapshot`.
- Produces:

```swift
struct PortGroup: Sendable, Equatable, Identifiable {
  let groupKey: String
  let name: String
  let bundleIdentifier: String?
  let representativePID: Int32
  let ports: [ListeningPort]  // sorted ascending, tcp before udp on ties
  /// Present for same-user rows; carries the children ProcessTerminator
  /// needs. nil marks a system row: no quit affordance, generic icon.
  let appGroup: AppGroup?

  var id: String { groupKey }
  var isSystem: Bool { appGroup == nil }
}

enum PortGroupBuilder {
  /// nil in → nil out (ports unavailable). Groups whose pids own no
  /// listening socket are dropped. Row order: same-user rows first, then
  /// system rows; localizedStandardCompare on name within each, groupKey
  /// as the final tiebreaker so equal names never reorder run to run.
  static func build(
    sockets: [SocketRecord]?,
    groups: [AppGroup],
    fallbackNamesByPID: [Int32: String]
  ) -> [PortGroup]?
}
```

- [ ] **Step 1: Write the failing tests**

Build fixtures by hand from the existing value types (see `GroupingEngineTests` for the house fixture style — plain constructors, no helpers beyond a local `func`):

```swift
import Testing

@testable import SystemHeadroom

@Suite("Port group builder")
struct PortGroupBuilderTests {
  private func measurement(pid: Int32, name: String) -> ProcessMeasurement {
    ProcessMeasurement(
      snapshot: ProcessSnapshot(
        pid: pid, parentPID: 1, userID: 501, name: name,
        startIdentity: "\(pid):0", cpuTimeTicks: 0, residentBytes: 0),
      cpuPercent: nil)
  }

  private func appGroup(key: String, name: String, pids: [Int32]) -> AppGroup {
    AppGroup(
      groupKey: key, name: name, bundleIdentifier: nil,
      representativePID: pids[0], cpuPercent: nil, memoryBytes: 0,
      children: pids.map { measurement(pid: $0, name: name) })
  }

  private func tcp(_ port: UInt16, pid: Int32) -> SocketRecord {
    SocketRecord(
      transport: .tcp, portNumber: port, pid: pid, effectivePid: 0,
      tcpState: MH_TCPS_LISTEN)
  }

  @Test("Helper pids fold their ports into the owning app's row")
  func helperPortsFold() throws {
    let node = appGroup(key: "pid:100", name: "node", pids: [100, 101])
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(3000, pid: 100), tcp(5173, pid: 101)],
        groups: [node], fallbackNamesByPID: [:]))
    #expect(rows.count == 1)
    #expect(rows[0].ports == [
      ListeningPort(number: 3000, transport: .tcp),
      ListeningPort(number: 5173, transport: .tcp),
    ])
    #expect(rows[0].appGroup == node)
  }

  @Test("Groups with no listening sockets are dropped")
  func silentGroupsDropped() throws {
    let idle = appGroup(key: "pid:200", name: "idle", pids: [200])
    let rows = try #require(
      PortGroupBuilder.build(sockets: [], groups: [idle], fallbackNamesByPID: [:]))
    #expect(rows.isEmpty)
  }

  @Test("Root listeners become system rows named from the fallback map")
  func rootFallbackRow() throws {
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(445, pid: 88)], groups: [], fallbackNamesByPID: [88: "smbd"]))
    #expect(rows.count == 1)
    #expect(rows[0].isSystem)
    #expect(rows[0].name == "smbd")
    #expect(rows[0].representativePID == 88)
  }

  @Test("A vanished owner with no name still gets a row, labeled by pid")
  func vanishedOwnerLabeledByPid() throws {
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(8080, pid: 999)], groups: [], fallbackNamesByPID: [:]))
    #expect(rows[0].name == "pid 999")
  }

  @Test("Duplicate ports from one owner dedupe; sort is user rows then system, by name")
  func orderingAndDedupe() throws {
    let zsh = appGroup(key: "pid:300", name: "zsh", pids: [300])
    let node = appGroup(key: "pid:100", name: "node", pids: [100])
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [
          tcp(3000, pid: 100), tcp(3000, pid: 100), tcp(9000, pid: 300),
          tcp(445, pid: 88),
        ],
        groups: [zsh, node], fallbackNamesByPID: [88: "smbd"]))
    #expect(rows.map(\.name) == ["node", "zsh", "smbd"])
    #expect(rows[0].ports == [ListeningPort(number: 3000, transport: .tcp)])
  }

  @Test("nil sockets propagate as nil")
  func nilPropagates() {
    #expect(PortGroupBuilder.build(sockets: nil, groups: [], fallbackNamesByPID: [:]) == nil)
  }
}
```

- [ ] **Step 2: Register files, run, verify red** (types undefined).

- [ ] **Step 3: Implement**

```swift
/// Folds listening sockets onto the app groups the popover already
/// shows. Pure and fixture-testable, like GroupingEngine: no syscalls,
/// no NSWorkspace.
enum PortGroupBuilder {
  static func build(
    sockets: [SocketRecord]?,
    groups: [AppGroup],
    fallbackNamesByPID: [Int32: String]
  ) -> [PortGroup]? {
    guard let sockets else { return nil }

    var groupKeyByPID: [Int32: String] = [:]
    var groupsByKey: [String: AppGroup] = [:]
    for group in groups {
      groupsByKey[group.groupKey] = group
      for child in group.children {
        groupKeyByPID[child.snapshot.pid] = group.groupKey
      }
    }

    var portsByRowKey: [String: Set<ListeningPort>] = [:]
    var systemRowInfo: [String: (name: String, pid: Int32)] = [:]
    for record in sockets {
      let port = ListeningPort(number: record.portNumber, transport: record.transport)
      if let key = groupKeyByPID[record.pid] {
        portsByRowKey[key, default: []].insert(port)
      } else {
        let key = "port-pid:\(record.pid)"
        portsByRowKey[key, default: []].insert(port)
        systemRowInfo[key] = (
          fallbackNamesByPID[record.pid] ?? "pid \(record.pid)", record.pid
        )
      }
    }

    let rows = portsByRowKey.map { key, ports -> PortGroup in
      if let group = groupsByKey[key] {
        return PortGroup(
          groupKey: key, name: group.name,
          bundleIdentifier: group.bundleIdentifier,
          representativePID: group.representativePID,
          ports: ports.sorted(), appGroup: group)
      }
      let info = systemRowInfo[key] ?? ("pid \(key)", 0)
      return PortGroup(
        groupKey: key, name: info.name, bundleIdentifier: nil,
        representativePID: info.pid, ports: ports.sorted(), appGroup: nil)
    }

    return rows.sorted { lhs, rhs in
      if lhs.isSystem != rhs.isSystem { return !lhs.isSystem }
      let names = lhs.name.localizedStandardCompare(rhs.name)
      if names != .orderedSame { return names == .orderedAscending }
      return lhs.groupKey < rhs.groupKey
    }
  }
}
```

- [ ] **Step 4: Run `PortGroupBuilderTests`, verify PASS.**

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/Grouping/PortGroup.swift SystemHeadroom/Grouping/PortGroupBuilder.swift SystemHeadroomTests/PortGroupBuilderTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(grouping): fold listening sockets into per-app port groups"
```

---

### Task 6: MonitorStore publishes portGroups

**Files:**
- Modify: `SystemHeadroom/App/MonitorStore.swift`
- Test: extend `SystemHeadroomTests/PortsSamplerLiveTests.swift`

**Interfaces:**
- Consumes: `PortGroupBuilder.build(sockets:groups:fallbackNamesByPID:)`, `MonitorTick.sockets` / `.socketFallbackNames`.
- Produces: `MonitorStore.portGroups: [PortGroup]?` (`private(set)`; nil = ports unavailable, `[]` = nothing listening); `MonitorStore.preview(...)` gains `portGroups: [PortGroup]? = []`.

- [ ] **Step 1: Write the failing test (append to PortsSamplerLiveTests)**

```swift
  @Test("Store publishes port groups after a refresh")
  @MainActor
  func storePublishesPortGroups() async throws {
    let suiteName = "com.vinnycarpenter.SystemHeadroom.ports-tests"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = MonitorStore(defaults: defaults, capability: .sandboxed)
    await store.refreshNow()
    let rows = try #require(store.portGroups)
    #expect(!rows.isEmpty)
    // User rows sort before system rows; a system row has no quit target.
    if let firstSystem = rows.firstIndex(where: \.isSystem) {
      #expect(rows[firstSystem...].allSatisfy(\.isSystem))
    }
  }
```

- [ ] **Step 2: Run, verify red** (`portGroups` undefined).

- [ ] **Step 3: Implement**

In `MonitorStore`: add `private(set) var portGroups: [PortGroup]?` beside the top lists (initialize `= []` so launch shows the empty state, not "unavailable", before the first tick). In `refreshNow()`, after `let groups = GroupingEngine.group(…)`:

```swift
    portGroups = PortGroupBuilder.build(
      sockets: tick.sockets, groups: groups,
      fallbackNamesByPID: tick.socketFallbackNames)
```

In the `preview` factory, add parameter `portGroups: [PortGroup]? = []` and assign `store.portGroups = portGroups` with the other stored properties.

- [ ] **Step 4: Run the full suite, verify green.**

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/App/MonitorStore.swift SystemHeadroomTests/PortsSamplerLiveTests.swift
git commit -m "feat(app): publish per-app port groups from the monitor store"
```

---

### Task 7: Classic popover — PopoverTab, ports pane, layout tests

**Files:**
- Create: `SystemHeadroom/UI/PopoverTab.swift` (`H…000B`)
- Create: `SystemHeadroom/UI/PortsPaneView.swift` (`H…000C`) — pane + row + badge in one focused file
- Modify: `SystemHeadroom/UI/PopoverView.swift`
- Modify: `SystemHeadroom/UI/PreviewFixtures.swift` (add port fixtures to `makeStore`)
- Test: extend `SystemHeadroomTests/PopoverLayoutTests.swift`
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MonitorStore.portGroups`, `PortGroup`, `ListeningPort`, `QuitAffordanceView`, `AppIconProvider`, `MetricKind`.
- Produces:

```swift
enum PopoverTab: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"
  case ports = "Ports"
  var id: String { rawValue }
  /// nil for .ports — the ports pane is not a metric ranking.
  var metricKind: MetricKind? {
    switch self {
    case .cpu: .cpu
    case .memory: .memory
    case .ports: nil
    }
  }
}

struct PortsPaneView: View {  // in PortsPaneView.swift
  let store: MonitorStore
  // renders unavailable / empty / rows states; rows are PortRowView
}
```

`PopoverView.init(store:initialMetric:)` becomes `init(store: MonitorStore, initialTab: PopoverTab = .cpu)`. `SystemHeadroomApp` call sites don't pass `initialMetric` today (verify; adjust if they do).

- [ ] **Step 1: Write the failing layout tests**

Append to `PopoverLayoutTests` (house pattern: `NSHostingView.intrinsicContentSize`):

```swift
  @Test("Classic ports pane height matches the metric panes, empty and populated")
  @MainActor
  func classicPortsPaneHeightInvariant() {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let emptyStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: false, portGroups: [])
    let unavailableStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary,
      usesPorcelainAppearance: false, portGroups: nil)
    let populatedStore = PreviewFixtures.makeStore(usesPorcelainAppearance: false)

    let metricHeight = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .cpu)
    ).intrinsicContentSize.height
    let portsEmpty = NSHostingView(
      rootView: PopoverView(store: emptyStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsUnavailable = NSHostingView(
      rootView: PopoverView(store: unavailableStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsPopulated = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .ports)
    ).intrinsicContentSize.height

    #expect(portsEmpty == metricHeight)
    #expect(portsUnavailable == metricHeight)
    #expect(portsPopulated == metricHeight)
  }
```

For this to compile, `PreviewFixtures.makeStore` must pass port fixtures. Extend it: build `portGroups` from its existing `AppGroup` fixtures — e.g. one row per existing fixture group with 1–2 ports, plus one system row and one row with 7 ports so the `+N` overflow chip renders in previews:

```swift
// In PreviewFixtures, alongside the group fixtures:
static func makePortGroups(from groups: [AppGroup]) -> [PortGroup] {
  var rows = groups.prefix(2).enumerated().map { index, group in
    PortGroup(
      groupKey: group.groupKey, name: group.name,
      bundleIdentifier: group.bundleIdentifier,
      representativePID: group.representativePID,
      ports: [
        ListeningPort(number: UInt16(3000 + index), transport: .tcp),
        ListeningPort(number: UInt16(5300 + index), transport: .udp),
      ],
      appGroup: group)
  }
  if let crowded = groups.first {
    rows.append(
      PortGroup(
        groupKey: "preview-crowded", name: "crowded",
        bundleIdentifier: nil, representativePID: crowded.representativePID,
        ports: (1...7).map { ListeningPort(number: UInt16(9000 + $0), transport: .tcp) },
        appGroup: crowded))
  }
  rows.append(
    PortGroup(
      groupKey: "port-pid:1", name: "launchd", bundleIdentifier: nil,
      representativePID: 1, ports: [ListeningPort(number: 445, transport: .tcp)],
      appGroup: nil))
  return rows
}
```

and pass `portGroups: makePortGroups(from: cpuGroups)` in `makeStore`'s `MonitorStore.preview` call.

- [ ] **Step 2: Run, verify red** (`initialTab:`/`portGroups:` don't exist yet).

- [ ] **Step 3: Implement PopoverTab, PortsPaneView, and the PopoverView rewiring**

`PortsPaneView.swift` — uniform-height rows; badge overflow chip instead of wrapping (fixed-height popover invariant); quit affordance identical in shape to `GroupRowView`'s:

```swift
import AppKit
import SwiftUI

/// The classic skin's Ports pane. Three states: unavailable (sysctl or
/// parse failure this tick), empty, rows. Rows are uniform height so the
/// pane's ideal height can never depend on content.
struct PortsPaneView: View {
  let store: MonitorStore

  var body: some View {
    if let rows = store.portGroups {
      if rows.isEmpty {
        Text("No listening ports")
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
      } else {
        ForEach(rows) { row in
          PortRowView(group: row, store: store)
        }
      }
    } else {
      Text("Ports unavailable")
        .foregroundStyle(.secondary)
        .padding(.vertical, 20)
    }
  }
}

struct PortRowView: View {
  let group: PortGroup
  let store: MonitorStore
  @State private var isRowHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let maxBadges = 4

  var body: some View {
    HStack(spacing: 8) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)

      Text(group.name)
        .lineLimit(1)

      if group.isSystem {
        Text("system")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: Capsule())
      }

      Spacer()

      if let appGroup = group.appGroup {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: .accentColor, secondary: .secondary,
          isRowHovered: isRowHovered
        ) {
          badges
        }
      } else {
        badges
      }
    }
    .frame(height: 26)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .onHover { hovering in
      guard store.canTerminate, group.appGroup != nil else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
        isRowHovered = hovering
      }
    }
  }

  private var badges: some View {
    HStack(spacing: 4) {
      ForEach(group.ports.prefix(Self.maxBadges), id: \.self) { port in
        PortBadge(port: port)
      }
      if group.ports.count > Self.maxBadges {
        Text("+\(group.ports.count - Self.maxBadges)")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var icon: NSImage {
    if let appGroup = group.appGroup {
      return AppIconProvider.icon(for: appGroup)
    }
    return NSImage(
      systemSymbolName: "gearshape.fill", accessibilityDescription: group.name)
      ?? NSImage()
  }

  private var accessibilityLabel: String {
    let portsText = group.ports
      .map { "\($0.number) \($0.transport.rawValue.uppercased())" }
      .joined(separator: ", ")
    let origin = group.isSystem ? ", system process" : ""
    return "\(group.name)\(origin), listening on \(portsText)"
  }
}

struct PortBadge: View {
  let port: ListeningPort

  var body: some View {
    Text(port.transport == .udp ? "\(port.number) udp" : "\(port.number)")
      .font(.system(.caption2, design: .monospaced))
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
  }
}
```

Note `Text("\(port.number)")` renders a UInt16 with grouping separators in some locales — use `Text(String(port.number))` in both the badge and anywhere else a port number is displayed.

`PopoverView` rewiring — replace `selectedMetric: MetricKind` with `selectedTab: PopoverTab`; the picker iterates `PopoverTab.allCases`; the existing metric list renders when `selectedTab.metricKind` is non-nil, `PortsPaneView` when it's `.ports`:

```swift
  @State private var selectedTab: PopoverTab

  init(store: MonitorStore, initialTab: PopoverTab = .cpu) {
    self.store = store
    _selectedTab = State(initialValue: initialTab)
  }

  private var groups: [AppGroup] {
    selectedTab == .cpu ? store.topCPUGroups : store.topMemoryGroups
  }

  private var maxValue: Double {
    guard let metric = selectedTab.metricKind else { return 0 }
    return groups.first.flatMap { metric.value(of: $0) } ?? 0
  }

  // in list's LazyVStack, replacing the current groups branch:
        if let metric = selectedTab.metricKind {
          if groups.isEmpty {
            Text("No data yet")
              .foregroundStyle(.secondary)
              .padding(.vertical, 20)
          } else {
            ForEach(groups) { group in
              GroupRowView(group: group, metric: metric, maxValue: maxValue, store: store)
            }
          }
        } else {
          PortsPaneView(store: store)
        }
```

The `.frame(height: 360)` on the list stays untouched. The Porcelain branch of `body` keeps compiling by passing `initialMetric: selectedTab.metricKind ?? .cpu` for now — Task 8 replaces it with the tab. `.animation(…, value: groups)` gains a sibling `.animation(reduceMotion ? nil : .default, value: store.portGroups)`.

- [ ] **Step 4: Run PopoverLayoutTests and the full suite, verify green.**

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/UI/PopoverTab.swift SystemHeadroom/UI/PortsPaneView.swift SystemHeadroom/UI/PopoverView.swift SystemHeadroom/UI/PreviewFixtures.swift SystemHeadroomTests/PopoverLayoutTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(ui): add Ports tab to the classic popover"
```

---

### Task 8: Porcelain popover — tab picker, ports header, porcelain rows

**Files:**
- Modify: `SystemHeadroom/UI/MaxHeadroomPopoverView.swift`
- Modify: `SystemHeadroom/UI/PopoverView.swift` (hand the tab through)
- Test: extend `SystemHeadroomTests/PopoverLayoutTests.swift`

**Interfaces:**
- Consumes: `PopoverTab`, `PortGroup`, `PortBadge`, `QuitAffordanceView`, `PorcelainPalette`, `PorcelainSpacing`.
- Produces: `PorcelainPopoverView.init(store: MonitorStore, initialTab: PopoverTab = .cpu)` (replaces `initialMetric:`); private `PorcelainPortRowView`.

- [ ] **Step 1: Write the failing layout test**

```swift
  @Test("Porcelain ports pane height matches the metric panes")
  @MainActor
  func porcelainPortsPaneHeightInvariant() {
    let emptySummary = SystemSummary(
      cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)
    let emptyStore = MonitorStore.preview(
      cpuGroups: [], memoryGroups: [], summary: emptySummary, portGroups: [])
    let populatedStore = PreviewFixtures.makeStore()

    let metricHeight = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .cpu)
    ).intrinsicContentSize.height
    let portsEmpty = NSHostingView(
      rootView: PopoverView(store: emptyStore, initialTab: .ports)
    ).intrinsicContentSize.height
    let portsPopulated = NSHostingView(
      rootView: PopoverView(store: populatedStore, initialTab: .ports)
    ).intrinsicContentSize.height

    #expect(portsEmpty == metricHeight)
    #expect(portsPopulated == metricHeight)
  }
```

- [ ] **Step 2: Run, verify red** (Porcelain still takes `initialMetric`, tab not threaded).

- [ ] **Step 3: Implement**

In `MaxHeadroomPopoverView.swift`:

- `@State private var selectedMetric: MetricKind` → `@State private var selectedTab: PopoverTab`; init takes `initialTab: PopoverTab = .cpu`. `PopoverView` passes `PorcelainPopoverView(store: store, initialTab: selectedTab)`.
- `PorcelainMetricPicker`: `@Binding var selection: PopoverTab`, iterate `PopoverTab.allCases`; widen its frame from 174 to 240 so three segments fit (`.frame(width: 240)` at the call site). Everything else (fonts, selected background) unchanged.
- Metric-dependent computed properties guard on `selectedTab.metricKind`; for `.ports` the header shows a count instead of headroom:
  - title line: `Text(selectedTab == .ports ? "Local ports" : "\(selectedTab.rawValue) headroom")`
  - big number for `.ports`: total port count `store.portGroups.map { $0.reduce(0) { $0 + $1.ports.count } }` rendered without the `%` suffix; `"—"` when `portGroups == nil`.
  - `usageDetail` for `.ports`: `"N processes listening"` (`portGroups?.count`), or `"Ports unavailable"` when nil.
  - The header keeps its `.frame(height: 172, alignment: .topLeading)` — the invariant test would catch any drift.
- `list` for `.ports`: iterate `store.portGroups ?? []` rendering `PorcelainPortRowView` (below), with the same inter-row divider treatment as `PorcelainGroupRowView`; empty state mirrors the existing "Waiting for a signal…" block with `"No listening ports"` / unavailable shows `"Ports unavailable"`. The list keeps `.frame(height: 468)`.
- `PorcelainPortRowView` (private, in this file), full code:

```swift
private struct PorcelainPortRowView: View {
  let group: PortGroup
  let palette: PorcelainPalette
  let store: MonitorStore
  @State private var isRowHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let maxBadges = 4

  var body: some View {
    HStack(spacing: PorcelainSpacing.sm) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)

      Text(group.name)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)

      if group.isSystem {
        Text("system")
          .font(.caption2)
          .foregroundStyle(palette.textSecondary)
      }

      Spacer(minLength: PorcelainSpacing.sm)

      if let appGroup = group.appGroup {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: palette.accent, secondary: palette.textSecondary,
          isRowHovered: isRowHovered
        ) {
          badges
        }
      } else {
        badges
      }
    }
    .padding(.vertical, PorcelainSpacing.xs)
    .frame(height: 44)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .onHover { hovering in
      guard store.canTerminate, group.appGroup != nil else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
        isRowHovered = hovering
      }
    }
  }

  private var badges: some View {
    HStack(spacing: 4) {
      ForEach(group.ports.prefix(Self.maxBadges), id: \.self) { port in
        PortBadge(port: port)
      }
      if group.ports.count > Self.maxBadges {
        Text("+\(group.ports.count - Self.maxBadges)")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(palette.textSecondary)
      }
    }
  }

  private var icon: NSImage {
    if let appGroup = group.appGroup {
      return AppIconProvider.icon(for: appGroup)
    }
    return NSImage(
      systemSymbolName: "gearshape.fill", accessibilityDescription: group.name)
      ?? NSImage()
  }

  private var accessibilityLabel: String {
    let portsText = group.ports
      .map { "\($0.number) \($0.transport.rawValue.uppercased())" }
      .joined(separator: ", ")
    let origin = group.isSystem ? ", system process" : ""
    return "\(group.name)\(origin), listening on \(portsText)"
  }
}
```

- [ ] **Step 4: Run PopoverLayoutTests and the full suite, verify green.**

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/UI/MaxHeadroomPopoverView.swift SystemHeadroom/UI/PopoverView.swift SystemHeadroomTests/PopoverLayoutTests.swift
git commit -m "feat(ui): add Ports tab to the Porcelain popover"
```

---

### Task 9: Docs, full-suite gate, and live verification

**Files:**
- Modify: `CLAUDE.md` (hard-won constraints)
- Modify: `README.md` (feature list, if it enumerates features — check first)

- [ ] **Step 1: Add the constraint line to CLAUDE.md**

Append to "Hard-won constraints":

```markdown
- **Port enumeration is sysctl-only.** Under the App Sandbox,
  `proc_pidinfo(PROC_PIDLISTFDS)` is EPERM for every non-self process and
  `bind()` is EPERM outright, so ports come from
  `net.inet.{tcp,udp}.pcblist_n` (hand-copied xnu layouts in
  `PortTableABI.h`) and the live test's oracle is netstat, not a
  self-bound listener. Measured Aug 1, 2026; see the SANDBOX_NOTES.md
  ports addendum before "fixing" any of this.
```

- [ ] **Step 2: Run the entire suite**

Run: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64'`
Expected: all suites PASS. Never end red.

- [ ] **Step 3: Live verification on the dev Mac**

Build and `open` the app (SingleInstanceGuard retires the old instance automatically). Then start a disposable listener and confirm it appears:

```bash
python3 -m http.server 8123 &
/usr/bin/log show --last 2m --info --predicate 'process == "System Headroom"' | grep -i port
```

Final visual confirmation is Vinny's — the popover's Ports tab should show `Python — 8123` while the server runs, with quit buttons absent (this is the sandboxed build). Kill the python server afterward. For the Direct build, `Scripts/build-direct.sh` then confirm quit buttons appear on user rows only.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs(claude): record sysctl-only port enumeration constraint"
```

---

## Plan Self-Review Notes

- Spec coverage: data layer (Tasks 1–4), grouping (5), store (6), both UI skins with fixed-height invariants and states (7–8), quit reuse via `QuitAffordanceView` on `appGroup` rows only (7–8), error handling (parser nil-contract in 2, transition logging in 4, unavailable states in 7–8), testing including the netstat oracle (2–3), docs (9). Non-goals untouched.
- The `.quitContextMenu(for:store:)` modifier used by `GroupRowView` may also fit port rows; if its API accepts any `AppGroup`, add it to both port row views in Tasks 7–8 alongside the affordance — optional, not load-bearing.
- Type names are consistent across tasks: `SocketRecord`, `ListeningPort`, `PortTransport`, `PortGroup`, `PortGroupBuilder`, `PortTableParser`, `PortTableSampler`, `PortsPaneView`, `PortRowView`, `PortBadge`, `PopoverTab`, `ProcessTable`.
