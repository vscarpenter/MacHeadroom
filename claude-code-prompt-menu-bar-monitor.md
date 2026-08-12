# Build brief: System Headroom, a macOS menu bar resource monitor

You are building a native macOS menu bar app for me, Vinny Carpenter. I ship Swift apps to the App Store and I will review every phase. The product name is System Headroom. Keep the name in one constant so branding stays consistent across the app.

## What we are building

A menu bar app that sits idle, samples the system on a timer, and shows the top 10 CPU consumers and top 10 memory consumers. The signature feature is consolidation: all processes belonging to one application collapse into a single row with combined stats. Fourteen Chrome processes appear as one "Chrome" row showing total CPU, total memory, and a process count, expandable to see the children. The app should feel like Apple shipped it: calm, native, and instantly readable.

## Hard constraints

- Swift 6 with strict concurrency enabled, zero warnings.
- SwiftUI throughout. Use `MenuBarExtra` with the `.window` style for the popover.
- Deployment target: macOS 14.0.
- `LSUIElement = true`. No Dock icon, no main window.
- Mac App Store distribution. App Sandbox ON from the first commit. Hardened runtime.
- Public APIs only. No private frameworks, no `task_for_pid` on other processes, no spawning `ps` or `top`, no helper tools, no root privileges.
- Zero third-party dependencies. Ask me before adding any.
- No network calls, no analytics, no data collection of any kind.
- The app must be a good citizen: its own CPU stays near zero while the popover is closed.

## Phase 0: sandbox feasibility spike (do this before anything else)

The App Sandbox restricts process enumeration. Apple DTS has stated there is no entitlement to allow `proc_listpids` in a sandboxed app. Yet iStat Menus 7 and Memory Diag ship on the Mac App Store with top-app lists, so a sandbox-legal path exists. Your first job is to find it and prove it.

Build a minimal sandboxed target that attempts, in order:

1. `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)` for the pid list and process names.
2. `proc_pidinfo(PROC_PIDTASKINFO)` per pid for CPU time and resident memory.
3. `proc_pid_rusage` per pid for `phys_footprint`.
4. `NSWorkspace.shared.runningApplications` for app metadata, bundle IDs, and icons.

Run it with the sandbox entitlement enabled and record exactly which calls succeed, which fail, and for which classes of process (own app, same-user apps, other-user and system processes). Write the findings to `SANDBOX_NOTES.md` with the macOS version tested.

Exit criteria: with the sandbox on, you can enumerate same-user processes and read nonzero CPU deltas and memory footprints for them. If system processes are invisible, document the scope limitation and continue; we will set expectations in the UI. If per-process data is entirely unavailable, stop and report back with options before building anything else.

## Architecture

- `SamplerService` (actor): owns the sampling loop. Default interval 5 seconds, configurable to 2, 5, 10, or 30. Each tick takes one snapshot of all reachable processes. CPU percent comes from the delta in per-process CPU time between consecutive snapshots divided by wall time. The first tick after launch shows memory only, since CPU needs two samples.
- Grouping engine (pure, testable): consolidates processes into app groups. Resolution order per process: walk the parent pid chain to the nearest ancestor whose executable path lives inside a `.app` bundle, then match that bundle against `NSRunningApplication`. Fall back to name heuristics for stragglers, such as stripping "Helper" suffixes ("Google Chrome Helper (Renderer)" groups under Google Chrome). The group key is the bundle identifier, or the executable path when no bundle exists. Aggregate CPU as a sum, memory as a sum of `phys_footprint`, and keep the child list sorted descending.
- Model: `AppGroup { name, icon, bundleID, processCount, cpuPercent, memoryBytes, children }`.
- `MonitorStore` (`@Observable`, main actor): holds the latest top-10 lists for both metrics and the overall system summary. The sampler publishes into it.
- System summary: overall CPU from `host_processor_info` deltas, memory used and pressure from `host_statistics64`.

## Metric semantics

- Memory means `phys_footprint`, matching the Memory column in Activity Monitor, not RSS. Display humanized values (842 MB, 3.2 GB).
- CPU percent is normalized to total machine capacity, so the scale is 0 to 100. Add a settings toggle for the Activity Monitor per-core convention, where one saturated core reads as 100.
- Never display a stale sample as current. Show "Updated Ns ago" in the footer.

## UI specification

Menu bar item:

- A monochrome template glyph. Optional setting to render live overall CPU percent as text beside it, off by default.

Popover (340 pt wide):

- Header: segmented control switching CPU and Memory views, plus the overall system summary (CPU percent, memory used of total) right-aligned.
- List: top 10 consolidated rows. Each row shows the real app icon from `NSRunningApplication`, the app name, a small "×N" process-count badge when N is greater than 1, and the value right-aligned in monospaced digits. Under each row, a 3 pt capacity bar scaled relative to the top consumer in the list.
- Disclosure: clicking a row's chevron expands its child processes as smaller indented rows with individual values.
- Footer: "Updated Ns ago" on the left; refresh, settings, and quit controls on the right.
- Settings window: sampling interval, launch at login via `SMAppService`, menu bar text toggle, CPU convention toggle.

Design rules:

- SF Symbols only. System materials and vibrancy for the popover. Full light and dark mode support. Respect the user's accent color.
- Value changes animate gently. Rows reorder with animation. Respect Reduce Motion.
- Accessibility: every row gets a VoiceOver label like "Chrome, 14 processes, 18 percent CPU". All controls are keyboard reachable.

## Branding rules

- Display name: "System Headroom" (`CFBundleDisplayName`). App Store listing name: "System Headroom: CPU & RAM Monitor".
- Typeset "Mac" and "Headroom" with equal size, weight, and color anywhere the name appears, per Apple's trademark guidelines for the Mac mark.
- The name is a nod to the Max Headroom character, whose likeness remains under copyright. The homage stops at the name. Never depict or evoke the character in the icon, UI, or any asset: no CG head, no shutter-shade sunglasses, no glitch or zigzag motifs, no stuttering-text gags.
- All visual assets are original work. All copy plays it straight; the joke lives in the name only.

## Performance budget

- The app's own average CPU stays under 0.5 percent at the 5 second interval with the popover closed.
- One enumeration pass per tick. Reuse buffers. No timers firing faster than the sampling interval.
- Pause sampling when the popover is closed and the menu bar text option is off, then sample immediately on open.

## Testing

- Unit tests for the grouping engine using fixture process tables: helper consolidation, orphaned processes, name-heuristic fallbacks, and tie-breaking.
- Unit tests for CPU delta math, including pid reuse between samples and the first-tick case.
- SwiftUI previews covering the popover in light and dark mode, with a preview fixture dataset.

## Deliverables

- An Xcode project ready for App Store Connect: sandbox entitlements, hardened runtime, app category set to Utilities, and a privacy manifest declaring no data collection.
- `SANDBOX_NOTES.md` from Phase 0.
- A README following my vinny-voice skill. Apply vinny-voice to all prose you write, including commit messages and code comments.

## Working style

- Work in phases: Phase 0 spike, then data layer, then grouping engine with tests, then UI, then settings and polish. Commit at each phase boundary with a clear message.
- When the sandbox forces a tradeoff, present the options with your recommendation instead of silently narrowing scope.
- Ask me before any decision that changes the constraints above.
