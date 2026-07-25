# Max Headroom mode design

Date: July 25, 2026. Approved by Vinny through the Porcelain Native broadcast mockup.

## Goal

Add an optional appearance named Max Headroom mode. When it is off, the current popover remains unchanged. When it is on, the popover uses the approved Porcelain Native treatment with a restrained retro-broadcast identity.

## Settings and persistence

- Add “Turn on Max Headroom mode” to an Appearance section in General settings.
- Default to off for new and existing users.
- Persist the value in the app's existing `UserDefaults` store.
- Changes apply the next time the popover is presented and may update an already-visible popover without restarting the app.

## Porcelain popover

The opt-in popover keeps the same app-level data, disclosure behavior, refresh behavior, accessibility labels, and fixed-content-height invariant as the standard popover.

### Header

- Warm porcelain surface in light appearance and an intentional warm graphite adaptation in dark appearance.
- “CPU headroom” or “Memory headroom” is the section title.
- The primary metric is the remaining percentage, derived from the selected system usage.
- Supporting copy always includes the exact usage measurement and installed memory total.
- A compact CPU/Memory segmented control stays native and keyboard accessible.
- An original synthetic broadcast-host cameo, horizontal scanlines, broken amber ceiling ticks, and a small dynamic `CH` label provide the signature detail.
- The host is decorative, carries no accessible label, and never overlaps or distorts telemetry.

### Process list

- Use 24-point app icons and aligned two-line labels.
- Show process count as quiet metadata rather than a compact multiplication badge.
- Keep values right-aligned with monospaced digits.
- Use one aligned two-point indicator track. The leading notch and highest-ranked value use amber; remaining values stay neutral.
- Preserve child-process expansion and glossary help.

### Footer

- Keep the update timestamp and refresh button.
- Combine Settings and Quit into a native overflow menu to reduce persistent chrome.
- Retain explicit accessibility labels and native keyboard behavior.

## Accessibility and motion

- All controls retain native focus behavior and accessible names.
- Color is not the only indication of the selected metric or highest-ranked app.
- Resource values use text labels and are never conveyed only by a bar.
- Existing Reduce Motion behavior remains in force.
- Light and dark appearances both maintain readable contrast.

## Architecture

- `MonitorStore` owns and persists the appearance preference.
- `PopoverView` keeps lifecycle behavior and selects either the standard or Porcelain presentation.
- Porcelain-specific composition and drawing live in a separate SwiftUI file.
- The synthetic host mark is drawn in SwiftUI so the implementation has no network, third-party, or raster-asset dependency.

## Verification

- Preference tests cover default-off behavior and persistence.
- Layout tests cover content-independent intrinsic height in both appearances.
- The complete hosted test suite and Debug build must pass.
- Render light and dark fixture images from a hosted SwiftUI view for visual inspection; final confirmation remains in the running app.
