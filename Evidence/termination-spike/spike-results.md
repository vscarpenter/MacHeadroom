# Process-termination sandbox spike — raw results

Date: July 26, 2026. macOS 26.5.2 (25F84), same machine as SANDBOX_NOTES.md
Phase 0. Probe: `probe.m` in this directory, compiled three ways and, for
the Apple-events leg, wrapped in two minimal signed `.app` bundles launched
via LaunchServices (`open`), results written into each container.

Sacrificial target: TextEdit, launched fresh via `open -a TextEdit`
(spawned by launchd, so NOT a sandbox child of the probe). Verified not
running beforehand; gracefully quit afterward. Finder (pid 714) used for
no-signal `kill(pid, 0)` permission checks only.

Sandbox-active proof in every sandboxed run: `open()` of
`~/Library/Preferences/com.apple.finder.plist` denied with EPERM;
allowed in every control run.

## Matrix

| Probe context | Call | Result |
| --- | --- | --- |
| Sandboxed (app-sandbox only, same as shipping app) | `kill(pid, 0)` on Finder | EPERM |
| Sandboxed | `kill(pid, 0)` on TextEdit | EPERM |
| Sandboxed | `kill(pid, SIGTERM)` on TextEdit | EPERM, target alive |
| Sandboxed | `kill(pid, SIGKILL)` on TextEdit | EPERM, target alive |
| Sandboxed | `NSRunningApplication.terminate()` | returned NO, target alive |
| Sandboxed | `NSRunningApplication.forceTerminate()` | returned NO, target alive |
| Sandboxed .app, pid addressing | `AEDeterminePermissionToAutomateTarget` (quit) | −600 procNotFound |
| Sandboxed .app, bundle-id addressing | same | −600 procNotFound |
| Sandboxed .app + `com.apple.security.automation.apple-events`, both addressings | same | −600 procNotFound |
| Control (identical binary, unsandboxed) | `kill(pid, 0)` on Finder | rc=0 |
| Control | `NSRunningApplication.terminate()` on TextEdit | YES; target actually quit |
| Control | `AEDeterminePermissionToAutomateTarget` (quit), both addressings | −1744 (would prompt; path viable) |

## Seatbelt evidence (unified log)

```
Sandbox: KillProbe(84329) deny(1) appleevent-send com.apple.textedit   ← variant A (sandbox only)
Sandbox: KillProbe(84337) deny(1) appleevent-send com.apple.textedit   ← variant B (sandbox + automation entitlement)
checker: appleeventsd, primary-filter: appleevent-destination, errno: 1
```

## Conclusion

On macOS 26.5.2, an App Sandbox app with System Headroom's entitlement set
cannot terminate any non-child process by any public path: BSD signals are
EPERM, both `NSRunningApplication` terminators are refused, and
Apple-event quit sends are denied per-destination by the seatbelt even
with the hardened-runtime automation entitlement (which Apple documents
for hardened runtime, not App Sandbox; the sandbox's own allowances are
`com.apple.security.scripting-targets` — requires targets to publish
access groups, unusable for arbitrary apps — and
`com.apple.security.temporary-exception.apple-events` — per-bundle-id,
generally rejected by App Review).

The identical unsandboxed binary quits apps cleanly, so a Developer ID
(non-sandboxed) build has the full feature available:
`NSRunningApplication.terminate()/forceTerminate()` for apps and
`kill(SIGTERM/SIGKILL)` for bare processes.
