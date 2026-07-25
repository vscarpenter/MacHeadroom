# Mac Headroom

Mac Headroom is a native macOS menu bar app that shows your top CPU and
memory consumers at a glance. Its one real trick: it collapses every
process that belongs to one app into a single row. Fourteen Chrome
processes show up as one "Chrome" row, with a process count and a tap
to expand.

## Requirements

- macOS 14.0 or later to run
- Xcode 26.6 and Swift 6 to build
- No accounts, no network calls, no third-party dependencies

## Building and testing

Open `MacHeadroom.xcodeproj` in Xcode and run the MacHeadroom scheme, or
build from the command line:

```bash
xcodebuild -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug build
xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64'
```

The unit tests run hosted inside the app (`MacHeadroomTests`, wired to
`TEST_HOST`), so they need a destination, not just a build.

## How it's built

- `Sampling/` reads the process table through `sysctl` and
  `proc_pidinfo`, then computes CPU percent from the delta between two
  samples. `SamplerService` is the actor that owns that state and runs
  the timer loop.
- `Grouping/` is pure. `GroupingEngine` consolidates a flat process
  list into `AppGroup` rows. It walks the parent pid chain to the
  nearest app, then falls back to name matching. No syscalls live in
  this file, so fixtures test it directly.
- `App/MonitorStore.swift` is the `@Observable` bridge between the
  sampler and the UI: it ticks, pulls live app metadata from
  `NSWorkspace`, and republishes the top-10 lists.
- `App/SingleInstanceGuard.swift` keeps one copy running. A new launch
  broadcasts a takeover notice and any older instance quits, so the
  newest build always wins.
- `UI/` is the SwiftUI popover: a segmented CPU/Memory header, the
  list, and a footer. A built-in glossary gives system daemons like
  `corespotlightd` a friendly name, the technical name as a subtitle,
  and a one-line explanation on hover. An optional Max Headroom mode
  switches the popover to the Porcelain Native broadcast appearance
  without changing its measurements. Settings is a tabbed window:
  General controls plus an About tab with version and links.
- `Design/` holds the scripts that generate the app icon and the menu
  bar glyph. Edit the script and re-run it instead of touching the
  images.

## Why memory means resident size, not physical footprint

Activity Monitor's Memory column is physical footprint. App Sandbox
blocks reading any other process's physical footprint, even processes
owned by the same user; only a process's own footprint is readable.
CPU and resident size stay readable for same-user processes.

Mac Headroom keeps the Sandbox and Mac App Store distribution, and
shows resident size instead. That number runs higher than Activity
Monitor's for apps with many helper processes. Resident size counts
shared framework pages once per process, not once per app. The full
investigation and the options considered live in
[SANDBOX_NOTES.md](SANDBOX_NOTES.md).

## Status

The core app is feature-complete and passes its 32-test suite. That
covers the sampler, the grouping engine, the popover, the process
glossary, the single-instance guard, the tabbed Settings window with
its About screen, and the brand glyph in the menu bar. The icon ships
as a traditional flat iconset for now; see
[Design/AppIcon](Design/AppIcon/README.md) for the source layers and
how to upgrade it to Icon Composer. Left to do: a final accessibility
and Reduce Motion pass in a running build, the
[macheadroom.com](https://macheadroom.com) landing page, and the
actual App Store Connect submission.

## If you don't see the menu bar icon

On a crowded menu bar, macOS can tuck a newly launched item into Control
Center's hidden overflow section instead of the visible strip. Hold Cmd
and drag menu bar icons to check, or look for Mac Headroom in System
Settings > Control Center before assuming the app didn't launch.
