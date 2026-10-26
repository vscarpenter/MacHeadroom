# Port actions, memory pressure, and CPU alerts

Status: approved by Vinny on October 26, 2026.

This is the 1.5.0 release of System Headroom: one fix and three
features. The fix makes a whole port row answer the pointer. The
features add Open and Copy to port rows in both editions and show
memory pressure and swap in the popover header. They also send a
notification when an app stays above a CPU threshold.

Direct 1.1 (16) went live on October 26, 2026 at 03:18 UTC, so this
release is 1.5.0 (17). Sparkle compares build numbers, and 16 is taken.

## Summary

Each part reuses a boundary the app already has. Port actions ride the
context menu the force-quit work attached. Pressure and swap ride the
`SystemSummary` the sampler already publishes every tick. Alerts ride
the background sampling path the menu bar percent already uses. A pure
tracker sits in front of the notification call, so the decision is
fixture-testable.

Everything ships in both editions. Nothing here needs a new
entitlement, a network call, or a dependency.

## Part 0: port rows answer the whole row

Both port-row views build an HStack with a Spacer and attach hover and
the context menu to it. SwiftUI only hit-tests pixels a child draws,
so the gap between the app name and the badges ignores the pointer.
Control-click there opens nothing. Crossing the gap on the way to the
badges drops hover, which disarms an armed Quit?. The Porcelain CPU
and Memory rows already solve this in `rowChrome` with
`.contentShape(Rectangle())`.

Apply that modifier to `labeledRow` in `PortRowView`
(`SystemHeadroom/UI/PortsPaneView.swift`) and `PorcelainPortRowView`
(`SystemHeadroom/UI/MaxHeadroomPopoverView.swift`), after the frame and
before the accessibility modifiers. Nothing else changes. The existing
layout tests pin the size.

## Part 1: Open and Copy on port rows

### What the user can do

Both editions, every row, including system rows:

- Control-click a row. Each TCP port gets "Open localhost:3000", which
  opens `http://localhost:3000` in the default browser. Each port, TCP
  or UDP, gets "Copy localhost:3000", which puts `localhost:3000` on
  the clipboard.
- UDP ports get no Open item. A browser cannot open one.
- A row with more than four ports gets "Open in Browser" and "Copy
  Address" submenus instead of flat items. Four is the cutoff the
  badges already use before the +N chip, so the menu mirrors the row.
- In the Direct build, a same-user row keeps "Quit" and "Force Quit" at
  the top of the menu, then a divider, then the port items. A system
  row, or any row in the App Store build, shows only the port items.
- VoiceOver exposes every menu item as a custom action with the same
  name.

System Headroom itself makes no connection. Open hands a URL to the
browser through `NSWorkspace`, which the sandbox allows.

### Wiring

- New `SystemHeadroom/UI/PortRowActions.swift`, Foundation only, no
  AppKit: `url(for: ListeningPort) -> URL?` returns
  `http://localhost:<n>` for TCP and nil for UDP;
  `address(for:) -> String` returns `localhost:<n>`;
  `usesSubmenus(portCount:) -> Bool` is true above four.
- `PortActionHandler`, a struct with `open: (URL) -> Void` and
  `copy: (String) -> Void`. `.live` calls `NSWorkspace.shared.open` and
  `NSPasteboard.general` (clear, then set the string). Both row views
  take a handler with `.live` as the default, so the call sites in the
  two popovers do not change.
- One shared modifier, `portRowMenu(for: PortGroup, store:, handler:)`,
  in a new `SystemHeadroom/UI/PortRowMenu.swift`, replaces the
  duplicated `menuRow` property in both skins. It emits the quit items
  when `store.canTerminate` is true and `group.appGroup` is present,
  then the port items, and attaches the matching accessibility actions.
- The two quit buttons move out of `quitContextMenu` into a
  `QuitMenuItems` view so the port menu and `GroupRowView` share them.
  `quitContextMenu` keeps its signature; `GroupRowView` does not change.

### Help

In "Read the signal", after the "Ports" fact, add "Open or copy a
port": "Control-click a Ports row to open localhost and that port in
your browser, or to copy the address."

## Part 2: memory pressure and swap in the header

### Why

Memory headroom is used over total, and the README already explains why
that confuses people who compare it with Activity Monitor. Pressure is
the signal macOS itself uses to decide whether memory is short. Swap in
use is the plainest evidence of it.

### Data

Two sysctl reads, both present on this Mac (macOS 27) from the shell:

- `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4
  critical. A new `MemoryPressureLevel` enum (normal, warning,
  critical) maps those values; anything else maps to nil.
- `vm.swapusage`: an `xsw_usage` struct; `xsu_used` is the bytes on
  disk right now.

`HostSampler` gains `sampleMemoryPressure() -> MemoryPressureLevel?`
and `sampleSwapUsage() -> UInt64?`. `SamplerService.tick` calls both
next to `sampleMemory()`. `SystemSummary` gains
`memoryPressure: MemoryPressureLevel?` and `swapUsedBytes: UInt64?`,
both defaulting to nil so every existing call site compiles unchanged.

The sandbox has not been measured for these two reads. The first task
of this part is a live test in the sandboxed test host, in the style of
`PortsSamplerLiveTests`, asserting both return a value. If the sandbox
denies either, the field stays nil and the badge shows the unknown
state. SANDBOX_NOTES.md then gets an addendum with the measurement
before the UI task starts.

### Display

A shared `MemoryPressureBadge` view: a small filled circle, then the
level word, then the swap figure. Green and "Normal", orange and
"Warning", red and "Critical", gray and "Unknown" when nil. Swap reads
"Swap 1.2 GB" through `ValueFormatting.bytes`, or "Swap —" when nil.
Colors are the system semantic colors in both skins; they adapt to dark
mode on their own. The accessibility label reads "Memory pressure
normal, 1.2 GB of swap in use".

Classic: a third caption line in the header, under the CPU and memory
line, holding the badge. It renders on every tab and in every state, so
the header's height never moves.

Porcelain: the text column next to the big number is already full (the
usage detail line scales to 0.82 to fit beside the 240-point picker).
The badge goes under the metric picker instead: the right column
becomes a trailing-aligned VStack of picker, then badge at 11 points in
`textSecondary`. It renders on every tab. The header keeps its
172-point frame. This placement is my call; Vinny confirms the look.

### Tests

- `MemoryPressureLevelTests`: the raw mapping, including unknown values.
- `HostPressureLiveTests` (sandboxed host): both reads return a value;
  swap used does not exceed swap total.
- `PopoverLayoutTests`, each skin: equal intrinsic size between a
  summary with nil pressure and swap and one with critical pressure and
  3 GB of swap.

### Help

In "Read the signal", add "Memory pressure and swap": "The light stays
green while macOS has room. Orange means it is compressing memory to
keep up. Red means it is short on memory and apps may stall. Swap shows
how much memory is parked on disk right now."

## Part 3: sustained CPU alerts

### What the user can do

A new "Alerts" section in General settings:

- Toggle "Notify me about sustained CPU use". Off by default.
- Picker "Above": 50%, 75%, 90%. Default 90%.
- Picker "For at least": 30 seconds, 1 minute, 2 minutes, 5 minutes.
  Default 1 minute.
- Both pickers disable while the toggle is off.
- A caption: "Percent of one core, the way Activity Monitor counts.
  Alerts keep sampling running while the popover is closed, like the
  menu bar percent does."

Turning the toggle on asks macOS for notification permission once
(alert and sound). The app does not re-ask; if the user declined, Help
points them at System Settings.

A notification looks like: title "Google Chrome at 180% CPU", body
"Above 90% of a core for 1 minute." One notification per episode. An
episode starts when an app's CPU reaches the threshold and ends when
it drops below or leaves the top 10. After a notification, the same
app waits five minutes before it can alert again, even if a new
episode qualifies sooner.

The percent is always measured against one core, the way Activity
Monitor counts, whatever convention the list displays. The builder
check caught why: under the default machine-capacity convention one
saturated core is about 7% on a 14-core Mac, so a 75% threshold would
never fire for the runaway helper this feature exists to catch. The
notification therefore shows the per-core figure, and the Help copy
says so, because a machine-capacity row will read lower than the
alert. That is my call.

Expect some noise from apps that legitimately keep a core busy, such
as a video call or a build. The sustain picker and the five-minute
cooldown bound it to one notification per app per five minutes at
worst, and the toggle turns it off.

Both editions get alerts. Local notifications need no entitlement under
the App Sandbox and no privacy-manifest reason.

### Wiring

Core count, in `Sampling/`: `MonitorTick` gains `logicalCoreCount: Int`,
filled from the count `SamplerService` already holds. The store keeps
the latest value and converts each group's displayed percent to a
per-core percent (`cpuPercent * logicalCoreCount` under machine
capacity, unchanged under per-core) before the tracker sees it.

Pure decision, in `SystemHeadroom/Grouping/CPUAlertTracker.swift`:

- `CPUAlertPolicy`: `thresholdPercentOfCore`, `sustainSeconds`, and
  `cooldownSeconds` (fixed at 300).
- `CPUAlertCandidate`: `groupKey`, `name`, `percentOfCore`. The store
  builds these; the tracker never sees a convention.
- `CPUAlert`: `groupKey`, `name`, `percentOfCore`, and the policy it
  matched.
- `CPUAlertTracker`, a value type with
  `mutating func observe(_ candidates: [CPUAlertCandidate], at now: Date, policy:) -> [CPUAlert]`.
  It keeps an episode start per group key and a last-notified date per
  group key. No clock of its own: `now` comes in.

Delivery, in `SystemHeadroom/App/`:

- `protocol AlertDelivery` (`@MainActor`): `requestAuthorization()` and
  `deliver(_ alert: CPUAlert)`.
- `NotificationAlertDelivery` wraps `UNUserNotificationCenter`. It
  touches the center only inside those two methods, never in `init`,
  so constructing a store in a test never prompts. The request
  identifier is `cpu-alert-<groupKey>`, so a newer alert for the same
  app replaces the older one in Notification Center. It also installs
  a center delegate whose `willPresent` returns banner and sound, so a
  notification still shows while the Settings window is frontmost.
- Tests inject a recording fake.

`MonitorStore`:

- Three preferences, with keys `cpuAlertsEnabled`,
  `cpuAlertThresholdPercent`, and `cpuAlertSustainSeconds`.
- `needsBackgroundSampling`, true when either the menu bar percent or
  alerts are on, replaces the three direct `showsMenuBarText` checks
  (its `didSet`, `popoverDidDisappear`, and the launch-time start in
  `init`). Property observers do not run in `init`, so the launch path
  checks the stored value explicitly, as the menu bar option does today.
- `refreshNow` calls `evaluateAlerts(groups: topCPUGroups, now: Date())`
  after it publishes the lists. That method is internal so a test can
  drive it with fixture groups. Turning alerts off resets the tracker.
- `isSampling`, a read-only `Bool`, exposes whether the timer is
  running so the start and stop rules are testable.
- `MonitorStore.preview` takes a no-op delivery.

### Tests

- `CPUAlertTrackerTests`: below threshold, nothing; above but shorter
  than sustain, nothing; sustained, exactly one; still above, no
  repeat; drops below and re-crosses inside the cooldown, nothing;
  after the cooldown, one; a group that leaves the list resets its
  episode.
- `MonitorStorePreferencesTests`: defaults are off, 90, and 60; a
  round trip through a fresh store restores all three; enabling alerts
  with the popover closed starts sampling; disabling with the popover
  closed and the menu bar percent off stops it.
- `StoreAlertTests`: with the fake delivery, alerts on, and a zero
  sustain, `evaluateAlerts` delivers one alert for a fixture group at
  10% under machine capacity on a 14-core tick (140% of a core) and
  none for a group at 5% (70% of a core); with alerts off it delivers
  none.

### Help

A new "Alerts" section with a bell icon, after "Keep it current":

- "Sustained CPU alerts": "Turn on alerts in General to get a
  notification when an app stays above your threshold for as long as
  you choose. macOS asks once for permission. If nothing arrives, check
  System Settings, then Notifications, then System Headroom."
- "What counts": "Alerts measure against one core, the way Activity
  Monitor does, so a row shown as 7% of the whole Mac can still be a
  full core. You get one notification per episode, and the same app
  waits five minutes before it can alert again."

## Branch

This work stacks on `feat/ports-force-quit`, which is open as PR #8
and already shipped as Direct 1.1 (16). Parts 0 and 1 edit the files
that branch changed, and the bump script requires the 1.1 (16) pins.
The new branch is `feat/1.5.0-port-actions-pressure-alerts`, cut from
that branch's head. Pull requests on this repo merge with merge
commits (see PR #7), so the stack lands cleanly once #8 merges. That
is my call.

## Version

Run `python3 Scripts/bump-direct-version.py --version 1.5.0 --build 17`.
It rewrites `Configuration/Shared.xcconfig` and the two pins in
`SystemHeadroomTests/AppIdentityTests.swift` together. The release
scripts accept a three-part version (the check at
`Scripts/release-direct.sh` line 99 allows one to three components).

"1.5.0" is what Vinny asked for. Earlier releases used two parts (1.0,
1.1). Switching to "1.5" later is a one-line change to the same
command.

## Constraints carried from CLAUDE.md

- The popover's ideal height must not depend on content or capability.
  Both header additions render in every state, and the layout tests
  pin equal size across states.
- No termination UI in the App Store build. Open and Copy are not
  termination; the quit items stay behind `canTerminate`.
- Sandbox boundaries are measured, not assumed: the pressure and swap
  reads get a live test before any UI depends on them.
- Zero dependencies and no network. UserNotifications, NSWorkspace, and
  NSPasteboard are system frameworks.
- Branding is untouched.
- New source files follow the four-edit pbxproj rule and the hand-rolled
  ID scheme (UI `H1`/`H2`, Sampling `D1`/`D2`, Grouping `F1`/`F2`,
  App `G1`/`G2` beside `MonitorStore.swift`, tests `E1`/`E2`).

## Manual check (Vinny)

- Control-click a dev server row on the Ports tab. Open launches the
  browser at `localhost:<port>`; Copy pastes `localhost:<port>`.
- The header shows pressure and swap in both skins. Compare the color
  with Activity Monitor's Memory Pressure graph.
- Turn on alerts at 50% for 30 seconds, run `yes > /dev/null` in a
  terminal for 40 seconds, and watch for the notification. One core at
  100% clears the threshold under either list convention. Stop the
  command. No second notification arrives inside five minutes.
- On the sandboxed Debug build, a port row's menu has Open and Copy and
  no Quit.

## Out of scope

Memory threshold alerts, an alert history, opening the popover from a
notification (MenuBarExtra has no programmatic open on macOS 14),
killing whatever holds a port, pressure in the menu bar label, and
localization.

## Amendment (October 26, 2026, after the manual check)

Vinny found the Control-click menu undiscoverable. Each port row now
ends with a borderless ellipsis button in both skins. A plain click
opens the same menu Control-click does. The button is hidden from
VoiceOver because the row already exposes the items as custom actions.
Row height and the popover size do not change. The Help fact names the
button first and the gesture second. Chosen by Vinny from three
options; the alternatives were a header hint line plus tooltips, or
both.

## Amendment 2 (October 26, 2026): hostname aliases on the web ports

Vinny's Caddy row routes by Host header, so localhost:443 reaches it
under the wrong name and scheme. Rows listening on TCP 80 or 443 now
also offer "Open as" and "Copy as" submenus with one entry per loopback
name from /etc/hosts (names on 127.0.0.1 or ::1 lines, minus localhost
itself), as https://name when the row has 443 and http://name
otherwise, with no port suffix. Other ports keep the localhost items.
The store reads the file each time the popover opens; a read failure
means localhost only. The sandboxed test host proves the read on every
run (`HostsFileLiveTests`). Chosen by Vinny over aliases on every port
and over a list typed in Settings.

## Amendment 3 (October 26, 2026): alert identity for bundle-less processes

The manual cooldown check caught a gap. The list keys a process with
no bundle by pid, so two `node` servers get two rows. The tracker
reused that key, so a restarted `yes` alerted again 2 minutes and 40
seconds after its first notification. The alert identity is now the
bundle id when there is one and otherwise the process name, prefixed
`name:`. Same-name processes merge into one candidate at the higher
reading, so one episode lasts while any of them is over the threshold.
The notification request id follows the same key. `StoreAlertTests`
pins the keys, the merge, and a restart inside the cooldown.
