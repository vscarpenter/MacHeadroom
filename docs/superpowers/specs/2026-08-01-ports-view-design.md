# Ports view: listening ports with owning processes

Status: approved by Vinny on August 1, 2026. Spike evidence lives in
`Evidence/ports-spike/` and in the SANDBOX_NOTES.md addendum.

## Summary

A third segment in the popover — CPU | Memory | Ports — lists every
process that is listening on a local port, grouped the way Mac Headroom
always groups: one row per app or standalone process, its ports shown
as badges. Both builds get the view. Only the Direct build gets quit
buttons on the rows, through the existing capability gate; the
termination spike settled that the Mac App Store build cannot kill
anything, and this design adds no new termination code at all.

The target user story is the runaway dev server: a `python` or `node`
process still holding port 3000 long after its terminal tab closed.
Listening sockets only — TCP in LISTEN state plus bound UDP sockets.
Established connections, traffic rates, and per-port actions are
non-goals.

## What the spike proved (August 1, 2026, macOS 26.6)

Probe signed three ways; ground truth was a non-child same-user
`python3 -m http.server` on port 8123. Raw transcripts in
`Evidence/ports-spike/`.

| Path | Sandboxed (shipping entitlements) | Unsandboxed control |
| --- | --- | --- |
| `proc_pidinfo(PROC_PIDLISTFDS)` on non-self pids | `EPERM`, all 679 same-user | 678/678 ok, truth port found with owner |
| `sysctlbyname("net.inet.tcp.pcblist_n")` | full table, truth port AND pid present | identical |
| `net.inet.udp.pcblist_n` | full table | identical |
| adding `com.apple.security.network.client` | changes nothing | — |

The lsof-style fd walk is sandbox-blocked (same boundary shape as
`phys_footprint` in Phase 0). The netstat-style global table is open,
carries owning pids (`so_last_pid`/`so_e_pid`), is not filtered by uid
(root listeners are visible, unlike every per-process metric), and
costs one ~100 KB syscall instead of ~680 fd walks.

The accepted trade-off: the `pcblist_n` record layouts (`xinpgen`,
`xgen_n`, `xsocket_n`, `xinpcb_n`, `xtcpcb_n`) are not in the public
SDK; they exist only in xnu source. The app carries hand-copied
definitions — one step beyond the `libproc` precedent accepted in the
Phase 0 resolution. `sysctlbyname` itself is public. Two containments:
the records are self-framing (`xgn_len`/`xgn_kind`), so the parser
skips what it does not recognize; and a live test inside the sandboxed
test host re-proves the whole path on every CI run (see Testing).

## Data layer

Two units in `Sampling/`, split at the house purity boundary:

- `PortTableSampler` (impure, small): fetches the raw TCP and UDP
  tables into `Data` via `sysctlbyname`, with the grow-and-retry idiom
  for the size-query/fetch race. Runs inside `SamplerService`'s tick,
  unconditionally alongside CPU/memory. One cheap syscall per 2 s tick,
  only while sampling runs at all, is not worth conditional plumbing.
- `PortTableParser` (pure, no syscalls): `Data → [SocketRecord]`,
  record = protocol, local port, pid, effective pid, TCP state. Carries
  the hand-copied layouts. Defensive by construction: iterate records
  by `xgn_len`, dispatch on `xgn_kind`, skip unknown kinds, tolerate
  appended fields; truncated or malformed input yields an empty result
  plus one `os_log` fault. Never crashes, never emits garbage rows.
  Filter to TCP LISTEN and bound UDP; collapse IPv4/IPv6 duplicates of
  the same (pid, protocol, port).

`MonitorTick` gains a `sockets` field so ports ride the existing
one-way flow: sampler → tick → store → UI.

## Grouping

`PortGroupBuilder`, pure, in `Grouping/`. Input: socket records plus
the same-user `ProcessSnapshot`s and app metadata the store already
holds. Output: `[PortGroup]`, one row per owner:

- Same-user pids resolve through the existing grouping pipeline, so a
  server and its helpers fold into one row holding the union of their
  ports.
- Pids with no snapshot (root and other-user listeners, visible only
  through this sysctl) become fallback rows named from
  `kinfo_proc.p_comm` — the 16-character truncation applies and
  `ProcessGlossary` lookups still work — with a generic icon and a
  muted "system" caption in place of an app icon's metadata.
- Sort: same-user groups first, then system; name-ordered within each;
  port badges ascending.
- `canQuit` on a group requires both `MonitorStore.canTerminate` and
  same-user ownership. Root processes cannot be signalled even by the
  unsandboxed build.

## UI

A `PopoverTab` enum (cpu, memory, ports) becomes the segmented
control's selection; `MetricKind` remains unchanged for metric logic.
The ports pane reuses the same fixed-height list region and scrolls
when content exceeds it — the popover's ideal height must not depend on
list content, and `PopoverLayoutTests` extends to assert it for the
ports pane. Rows are uniform height: icon, name, one line of port
badges, a "+N" overflow chip instead of wrapping. Badges show the port
number; UDP badges append a small "udp" suffix. Empty state: "No
listening ports." Sampler or parse failure: "Ports unavailable" — the
pane never shows stale rows after a failed tick.

Quit affordances on `canQuit` rows reuse the existing quit UI pattern
and call `ProcessTerminator.quit`/`forceQuit` with the group, keeping
the PID-reuse-safe `startIdentity` revalidation and the
app-versus-signal dispatch. The Mac App Store build renders no quit UI
anywhere, exactly as today.

## Error handling

- sysctl failure: empty socket list for that tick, logged, UI shows the
  unavailable state.
- Parse anomaly (bad length, unknown framing): abandon the buffer,
  empty result, one fault log — no partial rows.
- Terminator outcomes surface exactly as the existing quit feature
  does; no new outcome states.

## Testing

- `PortTableParserTests`: synthetic buffers built with the real framing
  — exact-value assertions plus truncated, malformed, unknown-kind, and
  appended-field cases. A wrong hand-copied offset fails here at the
  exact byte.
- `PortsSamplerLiveTests`, inside the sandboxed test host (the ABI
  tripwire): bind a TCP listener and a UDP socket on ephemeral ports,
  run the real sampler and parser, assert our own pid and ports appear.
  Layout drift or a seatbelt policy change fails CI loudly instead of
  shipping silently.
- `PortGroupBuilderTests`: pid resolution into app groups, fallback
  naming under truncation, v4/v6 dedupe, sort order, `canQuit` gating.
- `PopoverLayoutTests`: equal intrinsic height, empty versus populated
  ports pane.

## Non-goals

Established connections, traffic rates, per-port kill, search or
filtering, a Direct-build fd-walk sampler (one sampler serves both
builds), and any change to termination capability or entitlements.
