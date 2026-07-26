# Mac Headroom sandbox feasibility spike

**Decision:** STOP. On macOS 26.5.2, sandboxed `proc_pid_rusage` returned
`EPERM` for every non-self same-user process, and no approved public
alternative was established.

**Resolved:** July 24, 2026. Vinny picked option 1 below. See
[Resolution](#resolution-july-24-2026) at the end of this document. Phase 1
is unblocked.

**Test date:** July 24, 2026

**Probe source:** `44ab12713a5f4a3fc1303cc82452176e5d80e953`

**Tester:** Codex, on Vinny Carpenter's development Mac

## What passed and what did not

- `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)` enumerated 1,048 processes in the
  signed sandboxed app.
- `proc_pidinfo(PROC_PIDTASKINFO)` returned full task records for all 679
  non-self same-user processes in both snapshots. All 679 records had nonzero
  resident memory.
- Two samples produced positive CPU deltas for 101 same-user processes.
- `NSWorkspace.shared.runningApplications` returned usable names, bundle IDs,
  icons, and executable URLs.
- `proc_pid_rusage(RUSAGE_INFO_V4)` failed with `EPERM` for every one of the
  679 non-self same-user processes. Only Mac Headroom could read its own
  `phys_footprint`.

CPU and resident set size are available for same-user processes. The required
Activity Monitor-style memory value is not.

## Test environment

- macOS: 26.5.2 (25F84)
- Hardware: Mac16,11, Apple silicon (`arm64`)
- Logical processors: 14
- Xcode: 26.6 (17F113)
- Swift: 6.3.3
- SDK: macOS 26.5
- Deployment target: macOS 14.0
- Build: Release, Swift 6 strict concurrency, warnings as errors
- Sample interval requested: 2.000 seconds
- Sample interval measured: 2.054084042 seconds
- Mach timebase: 125 / 3
- Signed product:
  `DerivedData/Build/Products/Release/Mac Headroom.app`
- Launch method: direct execution of the signed app bundle's executable with
  `--phase-zero-probe`

This result proves behavior on macOS 26.5.2. It does not prove that every
supported macOS 14-26 release has an identical sandbox boundary.

## Sandbox and constraint proof

The release app was signed with an Apple Development identity. The signature
contained only the sandbox entitlement:

```text
[Key] com.apple.security.app-sandbox
[Value] true
```

`codesign -dvvv` reported:

```text
Identifier=com.vinnycarpenter.MacHeadroom
flags=0x10000(runtime)
Runtime Version=26.5.0
```

The generated `Info.plist` contained:

```text
LSMinimumSystemVersion = 14.0
LSUIElement = true
LSApplicationCategoryType = public.app-category.utilities
```

The app used no subprocesses, helper tools, elevated privileges, network calls,
analytics, or third-party dependencies. It did not invoke `ps` or `top`, and it
used only the platform paths required by the brief. The privacy manifest
declares no tracking and no collected data.

One constraint conflict was discovered: the installed SDK's `libproc.h`
describes its process-information functions as private interfaces that are
subject to change. The requested Phase 0 calls were tested because the brief
explicitly required them, but shipping `proc_pidinfo` or `proc_pid_rusage`
needs a decision about the brief's public-APIs-only rule.

## Process classification

The report used four mutually exclusive classes:

1. **Own app:** PID equals the probe's PID.
2. **Same-user:** effective UID equals the probe's UID, excluding its PID.
3. **System/root:** effective UID is 0.
4. **Other-user:** every other effective UID.

An `NSWorkspace` match means the enumerated PID directly matched an
`NSRunningApplication`. Helper processes remain valid same-user processes even
when they do not match directly.

## Test protocol

Each snapshot called the requested paths in this order:

1. `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)`
2. `proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` for every PID
3. `proc_pid_rusage(pid, RUSAGE_INFO_V4, ...)` for every PID
4. `NSWorkspace.shared.runningApplications`
5. a second `KERN_PROC_ALL` enumeration used only to revalidate PID, start time,
   and UID after the measurement sweep

The first CPU sample is a baseline, not a zero-percent reading. PID plus process
start time guards the delta calculation against PID reuse. A proof is rejected
unless its identity also survives the post-sweep revalidation. The report
separately accounts for entries, exits, class transitions, unavailable task
pairs, counter regressions, and reused identities. `pti_total_user` and
`pti_total_system` are Mach ticks; the report converts their delta with
`mach_timebase_info` before calculating CPU percentage.

## Global call results

| Snapshot | Call | Return | `errno` | Bytes | Result |
| --- | --- | ---: | ---: | ---: | --- |
| T0 | `sysctl` size query | 0 | 0 | 682,344 | Success |
| T0 | `sysctl` data fetch | 0 | 0 | 679,104 | 1,048 processes |
| T0 | `NSWorkspace.runningApplications` | — | — | — | 135 applications |
| T0 | identity-revalidation `sysctl` data fetch | 0 | 0 | 679,104 | 1,048 / 1,048 identities revalidated |
| T1 | `sysctl` size query | 0 | 0 | 682,344 | Success |
| T1 | `sysctl` data fetch | 0 | 0 | 679,104 | 1,048 processes |
| T1 | `NSWorkspace.runningApplications` | — | — | — | 135 applications |
| T1 | identity-revalidation `sysctl` data fetch | 0 | 0 | 679,104 | 1,048 / 1,048 identities revalidated |

## Exact per-class counts

Every attempted call is counted once. A task-info success required the exact
`MemoryLayout<proc_taskinfo>.size`; an rusage success required return value 0.
Useful footprint additionally required `ri_phys_footprint > 0`.

| Snapshot | Class | PIDs | Task success / attempts | Resident > 0 | Rusage success / attempts | Footprint > 0 | Workspace matches |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| T0 | Own app | 1 | 1 / 1 | 1 | 1 / 1 | 1 | 0 |
| T0 | Same-user | 679 | 679 / 679 | 679 | 0 / 679 | 0 | 133 |
| T0 | System/root | 222 | 0 / 222 | 0 | 0 / 222 | 0 | 2 |
| T0 | Other-user | 146 | 0 / 146 | 0 | 0 / 146 | 0 | 0 |
| T1 | Own app | 1 | 1 / 1 | 1 | 1 / 1 | 1 | 0 |
| T1 | Same-user | 679 | 679 / 679 | 679 | 0 / 679 | 0 | 133 |
| T1 | System/root | 222 | 0 / 222 | 0 | 0 / 222 | 0 | 2 |
| T1 | Other-user | 146 | 0 / 146 | 0 | 0 / 146 | 0 | 0 |

## Failure breakdown

The final sandboxed run observed no process-churn failures. Every non-self
failure was a permission denial:

| Snapshot | Class | API | Failure | Count |
| --- | --- | --- | --- | ---: |
| T0 | Same-user | `proc_pid_rusage` | `EPERM` | 679 |
| T0 | System/root | `proc_pidinfo` | `EPERM` | 222 |
| T0 | System/root | `proc_pid_rusage` | `EPERM` | 222 |
| T0 | Other-user | `proc_pidinfo` | `EPERM` | 146 |
| T0 | Other-user | `proc_pid_rusage` | `EPERM` | 146 |
| T1 | Same-user | `proc_pid_rusage` | `EPERM` | 679 |
| T1 | System/root | `proc_pidinfo` | `EPERM` | 222 |
| T1 | System/root | `proc_pid_rusage` | `EPERM` | 222 |
| T1 | Other-user | `proc_pidinfo` | `EPERM` | 146 |
| T1 | Other-user | `proc_pid_rusage` | `EPERM` | 146 |

## CPU-delta proof

Finder provided a stable, non-self, same-user application proof:

| Field | Value |
| --- | ---: |
| PID | 714 |
| Bundle identifier | `com.apple.finder` |
| Icon available | Yes |
| T0 CPU ticks | 48,574,845,362 |
| T1 CPU ticks | 48,576,235,211 |
| Delta ticks | 1,389,849 |
| Delta CPU time | 57,910,375 ns |
| Delta wall time | 2,054,084,042 ns |
| Per-core convention | 2.8193% |
| Machine-capacity convention | 0.2014% |
| Resident bytes | 248,954,880 |
| `phys_footprint` | Unavailable (`EPERM`) |

Across the same stable interval, 101 of 679 same-user processes had positive
CPU deltas; 578 were unchanged. All 679 PIDs reconciled as stable pairs, with
zero entries, exits, class transitions, task-unavailable pairs, counter
regressions, or invalid/reused identities.

## Physical-footprint proof

| Class | Process | Rusage result | `phys_footprint` |
| --- | --- | --- | ---: |
| Own app | Mac Headroom | Success | 7,930,432 bytes |
| Same-user app | Finder | `EPERM` | Unavailable |
| System/root | Representative root process | `EPERM` | Unavailable |
| Other-user | Representative other-user process | `EPERM` | Unavailable |

Resident memory is not an acceptable synonym here. The same Finder sample had
248,954,880 resident bytes, but the product brief explicitly defines
memory as physical footprint.

## NSWorkspace metadata proof

`NSWorkspace.shared.runningApplications` returned 135 applications. All 135 had
names, icons, and executable URLs; 111 had bundle identifiers. All 135 PIDs also
appeared in the `KERN_PROC_ALL` table. Of those direct matches, 133 were
same-user and two were system/root.

The Finder CPU proof had a localized app name, bundle identifier, icon, and
executable URL. Metadata access is viable.

## Unsandboxed comparison

To isolate the cause, a temporary copy of the same release app was re-signed
with hardened runtime and no sandbox entitlement. No source or project setting
was changed.

- T0: 677 / 677 same-user `proc_pid_rusage` calls succeeded; all 677 footprints
  were nonzero.
- T1: 685 / 685 same-user calls succeeded; all 685 footprints were nonzero.
- Two identities changed or exited during T0 revalidation and were excluded.
  Across snapshots, nine same-user PIDs entered and one exited.
- A stable same-user app had both a positive CPU delta and a 39,158,768-byte
  physical footprint. The largest directly matched application footprint proof
  was Google Chrome at 350,538,344 bytes.
- System/root and other-user metrics remained unavailable to the normal user.

This proves the App Sandbox caused the same-user footprint denial. The temporary
unsandboxed copy was moved to Trash after the test.

The machine-readable reports are preserved in
[`Evidence/phase-zero-sandbox-report.json`](Evidence/phase-zero-sandbox-report.json)
and
[`Evidence/phase-zero-unsandboxed-report.json`](Evidence/phase-zero-unsandboxed-report.json).
Build, signing, executable-hash, entitlement, command, and report-hash
provenance is preserved in
[`Evidence/phase-zero-provenance.md`](Evidence/phase-zero-provenance.md).

## Exit decision

| Required result | Outcome |
| --- | --- |
| Sandboxed PID enumeration includes non-self same-user apps | Pass |
| Non-self same-user CPU deltas are readable | Pass |
| Non-self same-user resident memory is readable | Pass |
| Non-self same-user `phys_footprint` is readable | **Fail** |
| `NSWorkspace` supplies app metadata and icons | Pass |
| Public-API-only production path established | **Fail / unresolved** |

The Phase 0 exit criteria are not met. Per the build brief, work stops before
the data layer and UI.

## Options

1. **Keep Mac App Store distribution and App Sandbox.** Change the memory metric
   to resident set size and label it honestly. This preserves distribution but
   changes the metric semantics. It also still requires explicit acceptance of,
   or Apple confirmation about, the SDK's private-interface warning for
   `proc_pidinfo`.
2. **Keep exact CPU and `phys_footprint` semantics.** Distribute outside the Mac
   App Store without App Sandbox. This path was measured successfully for
   same-user processes, but it changes two hard constraints and retains the
   `libproc` API-status concern.
3. **Keep App Sandbox and a strict public-API interpretation.** Re-scope the app
   to overall system CPU and memory plus application metadata, without per-app
   rankings. This preserves the platform constraints but removes the product's
   signature feature.
4. **Ask Apple Developer Technical Support for a sanctioned path.** Request a
   written answer covering both non-self `phys_footprint` in App Sandbox and the
   App Store status of the required `libproc` calls before investing in the
   production architecture.

Recommendation: do not silently substitute RSS for physical footprint. If Mac
App Store distribution is non-negotiable, pursue option 4 first and treat
option 1 as the fallback. If exact Activity Monitor-style metrics are the
non-negotiable product requirement, option 2 is the only path this spike
actually proved.

## Resolution (July 24, 2026)

Vinny chose option 1: keep the Sandbox and the App Store, and swap the
memory metric from physical footprint to resident size.

`proc_pidinfo(PROC_PIDTASKINFO)` already returns `pti_resident_size` for
every same-user process, so the app does not need `proc_pid_rusage` at all
going forward. Dropping that call also removes 679 guaranteed `EPERM`
attempts per tick, which helps the 0.5 percent CPU budget in the brief.

The UI labels this value plainly instead of calling it unqualified "Memory,"
so it never claims Activity Monitor parity it cannot deliver. Grouped totals
will run higher than Activity Monitor's phys_footprint numbers for apps with
many helper processes. RSS counts shared framework pages once per process,
not once per app. Chrome and Safari will show this drift the most.

Filing an Apple DTS request about non-self `phys_footprint` access under
Sandbox remains worthwhile, and it can happen independently of the app
build. It does not block Phase 1.

Phase 1 starts from this commit. The `PhaseZero` probe target is retired: its
findings are permanent above, and its source is recoverable from git history
at `44ab12713a5f4a3fc1303cc82452176e5d80e953` if it is ever needed again.

## Process termination spike (July 26, 2026)

Same machine, macOS 26.5.2 (25F84). Probe source and raw results live in
[`Evidence/termination-spike/`](Evidence/termination-spike/). The design
that consumed these findings is
`docs/superpowers/specs/2026-07-26-popover-quit-design.md`.

A probe carrying only `com.apple.security.app-sandbox`, matching the
shipping app, cannot terminate any non-child process:

- `kill()` returned `EPERM` for signal 0, SIGTERM, and SIGKILL.
- `NSRunningApplication` `terminate()` and `forceTerminate()` returned
  `NO`, and the target survived.
- Apple-event quit sends failed with `procNotFound` (-600) under both
  pid and bundle-id addressing. The seatbelt logged
  `deny(1) appleevent-send com.apple.textedit` (checker `appleeventsd`)
  with and without `com.apple.security.automation.apple-events`. That
  entitlement belongs to hardened runtime and does not open the sandbox.
  The sandbox's own allowances, `scripting-targets` and per-app
  temporary exceptions, cannot cover arbitrary apps.

The identical unsandboxed binary quit TextEdit via `terminate()`, and so
did a hardened-runtime signed copy, which notarization requires.

Consequence: the popover quit feature is capability-gated. The Mac App
Store build shows no quit UI, and only the unsandboxed Developer ID
build terminates processes. Do not "fix" the sandboxed build by adding
termination UI; the OS denies the operation itself.
