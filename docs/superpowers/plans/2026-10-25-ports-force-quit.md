# Ports Force Quit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a same-user Ports row in the Direct build the same Quit and Force Quit menu a CPU or Memory row already has.

**Architecture:** `PortGroup.appGroup` is already the `AppGroup` `ProcessTerminator` expects. Both port-row views apply the existing `quitContextMenu(for:store:)` modifier when that group is present. The modifier draws nothing when `canTerminate` is false, so the App Store build gains no quit UI. The hover × keeps calling `store.quit`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing, hosted macOS tests via `xcodebuild`.

**Spec:** `docs/superpowers/specs/2026-10-25-ports-force-quit-design.md`

## Global Constraints

- macOS 14.0 deployment target. Swift 6 strict concurrency. Zero dependencies. No network in the app.
- The Mac App Store build shows no quit UI. `quitContextMenu` returns the row unchanged when `canTerminate` is false.
- Quit and Force Quit target the owning app group. Root and other-user rows (`appGroup == nil`) get no menu.
- The hover × stays a graceful quit. It does not offer Force Quit and it does not escalate.
- Popover ideal height must not depend on list content or on termination capability.
- Do not change `ProcessTerminator`, `MonitorStore.quit`, `MonitorStore.forceQuit`, `PortGroupBuilder`, `QuitAffordanceView`'s confirm button, entitlements, or the Direct overlay.
- Tests: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:SystemHeadroomTests/PopoverLayoutTests`
- If `xcode-select` points at Command Line Tools, prefix the test command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

### Task 1: Pin the Ports popover size with termination on and off

**Files:**
- Modify: `SystemHeadroomTests/PopoverLayoutTests.swift` (append two tests before the suite's closing brace)

**Interfaces:**
- Consumes: `PreviewFixtures.makeStore(usesPorcelainAppearance:canTerminate:)` and `PopoverView(store:initialTab:)`.
- Produces: `classicPortsCapabilityDoesNotChangeSize` and `porcelainPortsCapabilityDoesNotChangeSize`. Task 2 re-runs them after the menu is attached.

The hosted tests cannot see a SwiftUI context menu. These tests pin the size invariant from the spec. They pass on the first run, before the menu exists, because a missing menu also leaves the size alone. Their job is to fail if Task 2 changes the popover's intrinsic size.

- [x] **Step 1: Add the two tests**

Append this inside `PopoverLayoutTests`, after `porcelainCapabilityDoesNotChangeSize`:

```swift
  @Test("Quit capability does not change classic ports popover size")
  @MainActor
  func classicPortsCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore(usesPorcelainAppearance: false)
    let gatedOn = PreviewFixtures.makeStore(
      usesPorcelainAppearance: false, canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff, initialTab: .ports)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn, initialTab: .ports)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }

  @Test("Quit capability does not change Porcelain ports popover size")
  @MainActor
  func porcelainPortsCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore()
    let gatedOn = PreviewFixtures.makeStore(canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff, initialTab: .ports)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn, initialTab: .ports)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }
```

- [x] **Step 2: Run the layout suite**

Run: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:SystemHeadroomTests/PopoverLayoutTests`

Expected: the suite passes, including the two new tests.

- [x] **Step 3: Commit**

```bash
git add SystemHeadroomTests/PopoverLayoutTests.swift docs/superpowers/specs/2026-10-25-ports-force-quit-design.md docs/superpowers/plans/2026-10-25-ports-force-quit.md
git commit -m "$(cat <<'EOF'
test: pin Ports popover size when termination is available

EOF
)"
```

---

### Task 2: Attach the existing quit menu to same-user port rows

**Files:**
- Modify: `SystemHeadroom/UI/PortsPaneView.swift` (`PortRowView.body`)
- Modify: `SystemHeadroom/UI/MaxHeadroomPopoverView.swift` (`PorcelainPortRowView.body`)
- Modify: `SystemHeadroom/UI/HelpView.swift` (one Direct-edition sentence)

**Interfaces:**
- Consumes: `View.quitContextMenu(for:store:)` from `QuitAffordanceView.swift`. It adds "Quit \<name\>", destructive "Force Quit \<name\>", and VoiceOver actions named "Quit" and "Force Quit" only when `store.canTerminate` is true.
- Produces: no new types. `store.forceQuit(appGroup)` runs for a same-user port row through the menu that already exists for metric rows.

- [x] **Step 1: Attach the menu in the classic row**

Replace `PortRowView.body` in `SystemHeadroom/UI/PortsPaneView.swift` with:

```swift
  var body: some View {
    menuRow
      .onHover { hovering in
        guard store.canTerminate, group.appGroup != nil else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
          isRowHovered = hovering
        }
      }
  }

  private var labeledRow: some View {
    HStack(spacing: 8) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)

      Text(group.name)
        .lineLimit(1)

      if group.isSystem {
        Text("system")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: Capsule())
      }

      Spacer()

      if let appGroup = group.appGroup {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: .accentColor, secondary: .secondary,
          isRowHovered: isRowHovered
        ) {
          badges
        }
      } else {
        badges
      }
    }
    .frame(height: 26)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var menuRow: some View {
    if let appGroup = group.appGroup {
      labeledRow.quitContextMenu(for: appGroup, store: store)
    } else {
      labeledRow
    }
  }
```

Leave `badges`, `icon`, and `accessibilityLabel` as they are.

- [x] **Step 2: Attach the menu in the Porcelain row**

Replace `PorcelainPortRowView.body` in `SystemHeadroom/UI/MaxHeadroomPopoverView.swift` with:

```swift
  var body: some View {
    menuRow
      .onHover { hovering in
        guard store.canTerminate, group.appGroup != nil else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
          isRowHovered = hovering
        }
      }
  }

  private var labeledRow: some View {
    HStack(spacing: PorcelainSpacing.sm) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)

      Text(group.name)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)

      if group.isSystem {
        Text("system")
          .font(.caption2)
          .foregroundStyle(palette.textSecondary)
      }

      Spacer(minLength: PorcelainSpacing.sm)

      if let appGroup = group.appGroup {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: palette.accent, secondary: palette.textSecondary,
          isRowHovered: isRowHovered
        ) {
          badges
        }
      } else {
        badges
      }
    }
    .padding(.vertical, PorcelainSpacing.xs)
    .frame(height: 44)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var menuRow: some View {
    if let appGroup = group.appGroup {
      labeledRow.quitContextMenu(for: appGroup, store: store)
    } else {
      labeledRow
    }
  }
```

Leave `badges`, `icon`, and `accessibilityLabel` as they are.

- [x] **Step 3: Name the Ports tab in Help**

In `SystemHeadroom/UI/HelpView.swift`, replace the Direct-edition detail:

```swift
detail: "Move the pointer over a CPU or Memory row, select the ×, then select Quit? within four seconds to confirm."
```

with:

```swift
detail: "Move the pointer over a CPU, Memory, or Ports row, select the ×, then select Quit? within four seconds to confirm."
```

Do not edit "Force Quit only when needed" or the sandboxed "This edition monitors only" section.

- [x] **Step 4: Re-run the layout suite**

Run the same `xcodebuild test` command from Task 1.

Expected: `PopoverLayoutTests` passes, including `classicPortsCapabilityDoesNotChangeSize` and `porcelainPortsCapabilityDoesNotChangeSize`.

- [x] **Step 5: Commit**

```bash
git add SystemHeadroom/UI/PortsPaneView.swift SystemHeadroom/UI/MaxHeadroomPopoverView.swift SystemHeadroom/UI/HelpView.swift
git commit -m "$(cat <<'EOF'
fix: offer Force Quit on same-user port rows

EOF
)"
```

## Manual check (Vinny)

Not part of the automated tasks. On a Direct build from `./Scripts/build-direct.sh`:

- Control-click a sacrificial same-user listener, such as a standalone `python` or `node` server, and choose Force Quit. The process exits, and the following sample no longer lists that row.
- A system row has no Quit or Force Quit menu.
- The hover × on a same-user row still ends in "Quit?" and does not offer Force Quit.

On a sandboxed Debug build, a same-user port row has no × and no quit menu.

## Self-review

- Spec coverage: menu on both skins, system rows excluded, hover path unchanged, Help sentence, both size tests, terminator and entitlements left alone. The manual check is listed and is not an automated task.
- Placeholders: none. The tests are specified to pass before the menu exists; that is the invariant, not a missing failure mode.
- Types: `quitContextMenu(for:store:)` matches `QuitAffordanceView.swift`. `appGroup` is `AppGroup?` on `PortGroup`. `makeStore(usesPorcelainAppearance:canTerminate:)` matches `PreviewFixtures`.
