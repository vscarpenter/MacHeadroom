# Popover quit: capability-gated process termination

Status: approved by Vinny on July 26, 2026. Spike evidence lives in
`Evidence/termination-spike/` and in the SANDBOX_NOTES.md addendum.

## Summary

Clicking a row in the top-10 list quits that app: gracefully by default,
forcibly on explicit request. The App Sandbox denies every termination
path, so the affordance exists only where the OS grants it. A new
Developer ID build for macheadroom.com gets the feature. The Mac App
Store build keeps today's UI exactly. One codebase serves both: the app
checks its own sandbox entitlement at launch and shows only what it can
actually do. No compile-time forks.

## What the spike proved (July 26, 2026, macOS 26.5.2)

A probe signed with the shipping app's exact entitlement set could not
terminate any non-child process:

| Path | Sandboxed | Unsandboxed control |
| --- | --- | --- |
| `kill()` with 0, SIGTERM, or SIGKILL | `EPERM` | works |
| `NSRunningApplication.terminate()` | returns `NO` | quit TextEdit |
| `NSRunningApplication.forceTerminate()` | returns `NO` | works |
| Apple-event quit, with `automation.apple-events`, pid and bundle-id addressing | seatbelt denies `appleevent-send` | viable (-1744) |

The unified log names the blocker: `Sandbox: KillProbe deny(1)
appleevent-send com.apple.textedit`, checker `appleeventsd`. The denial
fired with and without the automation entitlement. That entitlement
belongs to hardened runtime, not the App Sandbox. The sandbox's own
allowances (`scripting-targets`, per-app temporary exceptions) cannot
cover arbitrary top-10 apps. A hardened-runtime signed probe, required
for notarization, still quit TextEdit cleanly. The Developer ID path is
proven, and the sandboxed path is closed.

## Capability gate

`TerminationCapability` runs once at launch. It reads our own signature
via `SecTaskCopyValueForEntitlement` for `com.apple.security.app-sandbox`.
This is a public API and deterministic; no probing of other processes.
`MonitorStore` exposes the result as `canTerminate`. When sandboxed,
every quit affordance is absent and the popover renders exactly as
today, so `PopoverLayoutTests` and the App Review posture are untouched.

## Termination semantics and safety

A new `ProcessTerminator` service lives in `App/`, `@MainActor` beside
the store. Rules:

- App groups, meaning rows with an `NSRunningApplication`: `terminate()`
  for Quit, `forceTerminate()` for Force Quit. These objects bind to the
  process instance, so PID reuse cannot misfire. Helpers die with their
  app.
- Version 1 acts on groups only, never individual child rows. Killing
  one of Chrome's helpers out from under it has no user story.
- Standalone process groups: SIGTERM for Quit, SIGKILL for Force Quit.
  Immediately before signaling, re-fetch that pid via
  `sysctl KERN_PROC_PID` and compare `startIdentity` against the row's
  snapshot. On mismatch, abort silently and refresh. Rows can be up to
  one sampling interval stale, and PID reuse in that window must never
  kill a stranger.
- No auto-escalation, ever. A quit that does not work leaves the row
  visible, and the user chooses Force Quit deliberately.
- After any action the store schedules `refreshNow()` after about one
  second. The refreshed list is the feedback. Failures log via `os_log`.
  No result state machine.

## Interaction, both skins

- Hovering a group row reveals an ✕ where the value text sits, as a
  crossfade with no layout shift. Row height does not change, which
  preserves the fixed popover-height invariant.
- First click flips the ✕ to an inline "Quit?" confirm. Second click
  quits. Mouse-out or Escape reverts. No modal dialogs; `MenuBarExtra`
  popovers and `NSAlert` do not mix.
- Right-click opens a context menu with Quit and Force Quit. The menu is
  also the VoiceOver path via accessibility actions. Reduce Motion
  disables the crossfade.
- One shared control takes its colors from the skin: standard material
  or the Porcelain palette. Child rows get no affordance in version 1.
- Branding rules hold. No new imagery, and telemetry stays undistorted.

## Build and distribution

- New `Release-Direct` build configuration: no sandbox entitlement (new
  `SystemHeadroomDirect.entitlements`), hardened runtime on, same team and
  xcconfig structure. The Mac App Store `Release` configuration does not
  change.
- The About tab gains one line naming the build flavor, App Store or
  Direct, so screenshots identify the build.
- Notarization scripting and update mechanics stay out of scope. They
  belong to the macheadroom.com distribution task.

## Testing

- Pure fixture tests: identity-revalidation decisions, confirm-state
  transitions, and group-to-action mapping (app versus standalone).
- Sandboxed test host, as today: `canTerminate` is false there, so tests
  assert affordances hide, store guards no-op safely, and layout
  invariants hold in hover and confirm states via forced-capability
  fixtures.
- Real signal delivery cannot run in the sandboxed test host. The plan
  ends with a manual checklist on the Direct build: sacrificial
  TextEdit, Quit, Force Quit, and Mac App Store visual parity. Final
  visual confirmation is Vinny's.

## Documentation

- SANDBOX_NOTES.md gains a dated addendum with the denial matrix, log
  evidence, and probe provenance, so nobody "fixes" the Mac App Store
  build by adding a kill button.
- CLAUDE.md hard-won constraints: termination requires the unsandboxed
  build, and the UI must stay capability-gated.
- README notes the two build flavors.

## Out of scope

Per-child kill, auto-escalation, any Mac App Store affordance including
an Activity Monitor bridge, a DTS filing (worthwhile, independent),
notarization pipeline, and update mechanism.
