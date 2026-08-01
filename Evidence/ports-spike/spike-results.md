# Ports-view sandbox spike — raw results

Date: August 1, 2026. macOS 26.6 (25G72), same machine as SANDBOX_NOTES.md
Phase 0. Probe: `probe.c` in this directory, compiled once and signed three
ways: ad-hoc + `com.apple.security.app-sandbox` only (matching the shipping
app's entitlement set), ad-hoc + app-sandbox + `com.apple.security.network.client`,
and ad-hoc with no entitlements (control). Raw transcripts:
`out-sandboxed.txt`, `out-sandboxed-net.txt`, `out-unsandboxed.txt`.

Ground truth: `python3 -m http.server 8123`, spawned by the invoking shell —
a same-user process that is NOT a child of the probe (pid 77444).

Sandbox-active proof in both sandboxed runs: containers were created at
`~/Library/Containers/com.vinnycarpenter.PortProbe{,.net}` and `$HOME` was
redirected into them (the Finder-plist read returned ENOENT from the empty
container rather than the unsandboxed OPENED). The 679/679 same-user EPERM
flip below, from the byte-identical binary, is the operative proof.

## Matrix

| Probe context | Call | Result |
| --- | --- | --- |
| Control (no entitlements) | `proc_pidinfo(PROC_PIDLISTFDS)` same-user | 678 / 678 ok |
| Control | fd walk + `PROC_PIDFDSOCKETINFO` | 22 TCP LISTEN sockets across 14 pids; ground-truth port 8123 found with owner pid |
| Control | `sysctl net.inet.tcp.pcblist_n` | rc=0, 106,616 bytes; ground-truth port AND pid bytes present, pid within 512 B after port |
| Sandboxed (app-sandbox only) | `proc_pidinfo(PROC_PIDLISTFDS)` self | ok |
| Sandboxed | `proc_pidinfo(PROC_PIDLISTFDS)` same-user | **0 / 679 ok — all EPERM** |
| Sandboxed | `proc_pidinfo(PROC_PIDLISTFDS)` root / other-user | all EPERM (219 / 150) |
| Sandboxed | `sysctl net.inet.tcp.pcblist_n` | **rc=0, 106,000 bytes; ground-truth port AND pid bytes present**, pid within 512 B after port |
| Sandboxed | `sysctl net.inet.udp.pcblist_n` | rc=0, 27,792 bytes |
| Sandboxed + network.client | all of the above | identical to sandbox-only (entitlement changes nothing) |

## Conclusion

On macOS 26.6, an App Sandbox app with Mac Headroom's entitlement set:

- **Cannot** walk other processes' file descriptors. `PROC_PIDLISTFDS` is
  EPERM for every non-self process, even same-user — the same boundary
  shape as `proc_pid_rusage` in Phase 0. The lsof-style port mapping is
  self-only under sandbox.
- **Can** read the global TCP/UDP connection tables via
  `sysctlbyname("net.inet.tcp.pcblist_n")` / `("net.inet.udp.pcblist_n")` —
  the same interface `netstat -anv` uses — and the returned records carry
  owning pids (`so_last_pid` / `so_e_pid` in `xsocket_n`). The buffer is the
  same size sandboxed as unsandboxed; the table is not filtered by uid, so
  root-owned listeners are visible too, unlike every per-process metric.
- `com.apple.security.network.client` neither helps nor is needed.

API-status caveat: the `pcblist_n` record layouts (`xinpgen`, `xgen_n`,
`xsocket_n`, `xinpcb_n`, `xtcpcb_n`) are **not in the public macOS SDK**
headers; they exist only in xnu source. Consuming them means hand-copied
struct definitions — one step beyond the accepted `libproc` precedent
(SANDBOX_NOTES.md resolution), where the functions at least appear in the
SDK. `sysctlbyname` itself is public and the sysctl name is a string, but
the interface is undocumented and its App Store review status is unknown.
The records are self-framing (`xgn_len`/`xgn_kind`), which permits
defensive parsing that skips unknown record kinds and tolerates appended
fields.

The unsandboxed control also proves the Direct build can use the
lsof-style fd walk with SDK-declared `libproc` calls, and can therefore
avoid the hand-copied structs entirely if it wants to.

## Follow-up: test-oracle measurements (same day)

`bindprobe.c` / `out-bindprobe.txt`, same signing matrix. Two facts that
shape the live test in the sandboxed test host:

| Probe context | Call | Result |
| --- | --- | --- |
| Sandboxed | `bind()` TCP or UDP, wildcard or loopback, ephemeral port | **EPERM, all four** (no `network.server`) |
| Sandboxed | `popen("/usr/sbin/netstat -anv -p tcp")` | **runs**, prints the `process:pid` column (child inherits the sandbox; the sysctl is allowed) |
| Control | all of the above | bind+listen ok; netstat ok |

So a self-listener test inside the sandboxed test host is impossible —
the sandbox denies creating the listener itself. The live-test oracle is
instead a cross-check against `netstat -anv` output, which exercises the
same sysctl through Apple's own parser. (Exec of non-system binaries,
e.g. Homebrew coreutils in `PATH`, is denied — the test must invoke
`/usr/sbin/netstat` by absolute path with no shell pipeline.)
