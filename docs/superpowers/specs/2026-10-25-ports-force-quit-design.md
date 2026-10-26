# Ports Force Quit

Status: approved by Vinny on October 25, 2026.

This completes the quit contract in
`docs/superpowers/specs/2026-08-01-ports-view-design.md`. That spec
requires same-user port rows to reuse the existing quit UI and call
both `ProcessTerminator.quit` and `ProcessTerminator.forceQuit`. The
hover control calls `quit`. The Force Quit menu was never attached.

## Summary

On the Ports tab, a same-user row in the Direct build gets the same
Control-click menu and VoiceOver actions as a CPU or Memory row: Quit
and Force Quit. The hover × stays a graceful quit. Root and other-user
rows stay without a menu. The Mac App Store build still shows no quit
UI.

No new termination primitive. The row already carries the `AppGroup`
that `ProcessTerminator` expects.

## What the user can do

Direct build, `MonitorStore.canTerminate == true`:

- Same-user port row, pointer hover: the port badges crossfade to ×.
  The first click arms "Quit?". The second click calls `store.quit` on
  that row's `appGroup`. Mouse-out or four seconds disarms it. This
  path already exists and does not change.
- Same-user port row, Control-click: "Quit \<name\>" calls
  `store.quit`. "Force Quit \<name\>" calls `store.forceQuit`. VoiceOver
  exposes the same two named actions, "Quit" and "Force Quit".
- Root or other-user port row (`appGroup == nil`): no ×, no menu, no
  VoiceOver quit actions. Those listeners cannot be signalled without
  root, and this app does not gain a privileged helper.

App Store build, `canTerminate == false`:

- No ×, no menu, and no VoiceOver quit actions on any port row. The
  modifier renders the row unchanged when termination is unavailable,
  which is the same rule the CPU and Memory rows already follow.

Both gestures target the owning app group, which is the same group the
hover Quit already uses. An app row asks `NSRunningApplication` to
quit or force-quit, and its helpers die with it. A standalone row, such
as a `node` or `python` server that grouped as its own `AppGroup`,
receives SIGTERM for Quit and SIGKILL for Force Quit. `ProcessTerminator`
re-checks `startIdentity` before every signal. A failed quit does not
escalate. The next sample is the only feedback.

## Wiring

`quitContextMenu(for:store:)` in `SystemHeadroom/UI/QuitAffordanceView.swift`
already builds the menu, the destructive Force Quit button, and the two
accessibility actions, and it returns the view unchanged when
`canTerminate` is false. CPU and Memory rows apply it unconditionally.
Port rows apply it the same way whenever `PortGroup.appGroup` is
present.

Attach it to the whole row, after the row's accessibility element is
combined:

- `PortRowView` in `SystemHeadroom/UI/PortsPaneView.swift`
- `PorcelainPortRowView` in `SystemHeadroom/UI/MaxHeadroomPopoverView.swift`

Leave these untouched:

- `QuitAffordanceView`'s hover confirm. It keeps calling `store.quit`.
- `ProcessTerminator`, `MonitorStore.quit`, and `MonitorStore.forceQuit`.
- `PortGroupBuilder`. Same-user sockets already resolve to an `AppGroup`;
  everyone else already gets `appGroup: nil`.
- Entitlements, the Direct overlay, and the sandbox capability check.

## Help

In the Direct edition's Process controls section, change the "Quit an
app group" detail from:

> Move the pointer over a CPU or Memory row, select the ×, then select Quit? within four seconds to confirm.

to:

> Move the pointer over a CPU, Memory, or Ports row, select the ×, then select Quit? within four seconds to confirm.

Leave "Force Quit only when needed" as it stands. It already says
Control-click a row, and that the action covers the whole app group
rather than one helper. The sandboxed "This edition monitors only"
section stays as it is.

## Testing

`ProcessTerminator` and `MonitorStore.forceQuit` already cover the
signal decision and the `canTerminate` no-op. This change does not add
terminator cases.

SwiftUI context menus are not inspected by the hosted layout tests.
What those tests can pin is the popover-size invariant: attaching the
menu must not change intrinsic size. Add two tests to
`SystemHeadroomTests/PopoverLayoutTests.swift`, beside the existing
capability-size tests:

- Classic compact, `initialTab: .ports`, `canTerminate` false versus
  true, equal `intrinsicContentSize`.
- Porcelain Native, the same pair, equal `intrinsicContentSize`.

Use `PreviewFixtures.makeStore(usesPorcelainAppearance:canTerminate:)`.
The existing ports height tests stay as they are. They already compare
empty, unavailable, and populated panes with termination off.

## Manual check

On a Direct build (`./Scripts/build-direct.sh`), open Ports:

- Control-click a sacrificial same-user listener, such as a standalone
  `python` or `node` server, and choose Force Quit. The process exits,
  and the following sample no longer lists that row.
- A system row has no Quit or Force Quit menu.
- The hover × on a same-user row still ends in "Quit?" and does not
  offer Force Quit.

On a sandboxed Debug build, a same-user port row has no × and no quit
menu.

## Out of scope

Per-child kill, a Force Quit label inside the hover confirm, auto
escalation from Quit to Force Quit, signalling root listeners, quit UI
on the Mac App Store build, and any change to port enumeration.
