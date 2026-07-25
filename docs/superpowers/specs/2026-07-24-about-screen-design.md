# About screen design

Date: July 24, 2026. Approved by Vinny (placement: a tab in the
Settings window).

## Problem

The app has no place that says what it is, what version is running, or
who made it. A rudimentary About screen is wanted now, with room to
grow later (acknowledgements, update notes).

## Design

The Settings window becomes a standard macOS tabbed settings window:

- **General**: the existing sampling, login, menu bar, and CPU
  convention controls, unchanged.
- **About**: the app icon, the app name, "Version X.Y.Z (build)",
  "Created by Vinny Carpenter" linking to https://vinny.dev/, and a
  link to https://macheadroom.com (the app's landing page).

`AppIdentity` grows a `versionDescription` ("Version 0.1.0 (1)") read
from the bundle's `CFBundleShortVersionString` and `CFBundleVersion`,
next to the existing display-name resolution. The About tab renders it,
so bumping `MARKETING_VERSION` in Shared.xcconfig is the only step a
release needs.

Branding rule honored: "Mac" and "Headroom" render with equal size,
weight, and color (one plain Text of the display name).

## Testing

- `versionDescription` contains the bundle's short version string and
  matches the "Version … (…)" shape.
- Existing display-name test keeps covering the name.

## Later

The About tab is the growth point: acknowledgements, a "what's new"
line, or a support link slot in beneath the links without touching
General.
