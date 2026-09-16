# System Headroom

System Headroom is a native macOS menu bar app that shows your top CPU and
memory consumers at a glance. Its one real trick: it collapses every
process that belongs to one app into a single row. Fourteen Chrome
processes show up as one "Chrome" row, with a process count and a tap
to expand.

A third Ports tab lists every local listening port grouped the same
way — one row per app with its ports as badges — so a runaway `node`
or `python` dev server still squatting on port 3000 is one glance (and,
in the Direct build, one click) from gone.

## Requirements

- macOS 14.0 or later to run
- Xcode 26.6 and Swift 6 to build
- No account required; process monitoring stays on your Mac
- The Direct edition uses Sparkle and makes network requests for update checks

## Building and testing

Open `SystemHeadroom.xcodeproj` in Xcode and run the SystemHeadroom scheme, or
build from the command line:

```bash
xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug build
xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64'
```

The unit tests run hosted inside the app (`SystemHeadroomTests`, wired to
`TEST_HOST`), so they need a destination, not just a build.

## Build flavors

System Headroom has two editions from the same source: a paid, sandboxed
Mac App Store edition and a free, unsandboxed Direct download from
[macheadroom.com](https://macheadroom.com). The Direct download requires no
purchase, receipt, account, or claim token. These are distribution options;
a local build does not establish that either release is publicly available.

| | Mac App Store | Direct download |
| --- | --- | --- |
| Bundle identifier | `com.vinnycarpenter.MacHeadroom` | `com.vinnycarpenter.SystemHeadroom.Direct` |
| Sandbox | Enabled | Disabled; Hardened Runtime retained |
| Updates | Mac App Store | Sparkle automatic checks and About → Check for Updates |
| Local build | `xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug build` | `./Scripts/build-direct.sh --ad-hoc` |
| Release | Archive the SystemHeadroom scheme without a Direct overlay; distribute through Xcode Organizer/App Store Connect | `./Scripts/release-direct.sh`, then `./Scripts/publish-direct.sh --publish <dmg>` |

Both editions can be installed together, but the single-instance guard keeps
only the most recently launched copy running. The popover's process controls
work in the Direct build; the About tab identifies the running edition.

For a local Direct build with no signing certificate:

```bash
# Use this override if xcode-select currently points at Command Line Tools.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/fetch-sparkle.sh
./Scripts/build-direct.sh --ad-hoc
```

Omit `--ad-hoc` to use the project's development signing configuration.
Customer downloads use `release-direct.sh`: it requires a Developer ID
Application identity and a `notarytool` Keychain profile, produces a universal
Apple silicon/Intel app, and notarizes and staples both the app and its DMG.
Publishing defaults to local staging; only `--publish` uploads files.

Sparkle is checksum-pinned by `Scripts/fetch-sparkle.sh` and compiled and
embedded only with `Configuration/Direct.xcconfig`. Direct initializes its
updater at launch and enables automatic update checks; this does not promise
unattended installation. The App Store binary stays Sparkle-free. Signing,
release verification, hosting requirements, and the stable website download
link are in the
[Direct edition runbook](Documentation/DirectEditionRunbook.md).

The legacy App Store-purchase transfer is separate and remains disabled:
leave `DIRECT_EDITION_CLAIM_URL` blank and any deployed claim service at
`ClaimFlowEnabled=false`. The free website download does not use that service
or depend on approval of its transfer model. Historical protocol and UI notes
remain in [DirectEditionClaimAPI.md](Documentation/DirectEditionClaimAPI.md)
and [DirectEditionSettingsOptionA.md](Documentation/DirectEditionSettingsOptionA.md).

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
- `UI/` is the SwiftUI popover: a segmented CPU/Memory/Ports header,
  the list, and a footer. A built-in glossary gives system daemons like
  `corespotlightd` a friendly name, the technical name as a subtitle,
  and a one-line explanation on hover. Porcelain Native is the default
  appearance, emphasizing headroom, app identity, and warm amber signal
  details without changing measurements. A compact classic appearance
  remains available in Settings, alongside General controls, task-oriented
  Help, and an About tab with version and links. When the separately gated
  Direct transfer is configured, General shows one quiet edition-comparison
  entry point and Help owns the explanation and verification states.
- `Design/` holds the scripts that generate the app icon and the menu
  bar glyph. Edit the script and re-run it instead of touching the
  images.

## Why memory differs by build flavor

Activity Monitor's Memory column is physical footprint. App Sandbox
blocks reading any other process's physical footprint, even processes
owned by the same user; only a process's own footprint is readable.
CPU and resident size stay readable for same-user processes.

The App Store edition therefore shows resident size and visibly marks each
memory value `RSS`. RSS can be higher than Activity Monitor after grouping
many helper processes, because shared pages can be counted in each process,
or dramatically lower for GPU-backed workloads whose allocations are charged
to physical footprint. The Help screen and row tooltips explain the boundary.

The unsandboxed Direct edition reads physical footprint and uses the same
per-process memory accounting as Activity Monitor. It never silently falls
back to RSS if a footprint read fails. The full sandbox investigation and the
options considered live in
[SANDBOX_NOTES.md](SANDBOX_NOTES.md).

## Status

The core app is feature-complete and passes its test suite. That
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
and drag menu bar icons to check, or look for System Headroom in System
Settings > Control Center before assuming the app didn't launch.
