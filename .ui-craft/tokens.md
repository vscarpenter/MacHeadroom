# Headroom Monitor token spine

Headroom Monitor uses native SwiftUI semantic styles for platform behavior and a small custom layer for its default Porcelain Native appearance. Raw values live in `PorcelainPalette`; views consume semantic roles rather than introducing local colors or spacing.

## Primitive tokens

### Color

| Token | Light | Dark | Purpose |
| --- | --- | --- | --- |
| Porcelain 50 | `#FBF8F3` | — | Warm canvas |
| Porcelain 100 | `#F3EEE7` | — | Raised row and control surfaces |
| Graphite 950 | `#1E2022` | `#171819` | Strong text and dark canvas |
| Graphite 600 | `#686A6D` | `#A7A39C` | Secondary text |
| Amber 500 | `#D97A16` | `#E09A42` | Single brand accent |
| Amber 200 | `#F2C58F` | `#7B512A` | Subtle accent border |

### Spacing

`4, 8, 12, 16, 24, 32` points. Dense list rows may use 2-point internal gaps while retaining the 4-point base rhythm.

### Type

- Display metric: system rounded, 36 points, regular, monospaced digits.
- Section title: system, 17 points, medium.
- App name: system, 13 points, medium.
- Metadata: system, 11 points, regular.
- Values: system, 13 points, regular, monospaced digits.
- Broadcast labels: system monospaced, 9 points, medium, tracked.

### Radii

- Control: 7 points.
- Emphasized row: 10 points.
- Popover: supplied by the system window.
- Process count capsule: full radius.

### Shadows

- Light raised row: ambient `0 4 12 black/5%` plus direct `0 1 2 black/6%`.
- Dark raised row: no drop shadow; use a `white/10%` border ring and `white/5%` fill.

### Motion

- Mode/content change: 150 milliseconds ease-out.
- Value and indicator change: 200 milliseconds ease-in-out.
- Reduced Motion: replace spatial movement with an immediate state change.

### Z-order

The popover has only base content and native overlays. No custom numeric z-index scale is needed.

## Semantic tokens

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | Porcelain 50 | Graphite 950 |
| Raised surface | Porcelain 100 | White at 6% |
| Text primary | Graphite 950 | Porcelain 50 |
| Text secondary | Graphite 600 | Warm gray |
| Border subtle | Black at 8% | White at 10% |
| Accent | Amber 500 | Reduced-chroma amber |
| Indicator track | Graphite at 10% | White at 12% |

## Component tokens

- Porcelain popover width: 460 points.
- Porcelain header horizontal padding: 20 points.
- Porcelain list horizontal padding: 20 points.
- Porcelain list height: fixed and independent of content.
- App icon: 32 points in a softly bordered optical well.
- Indicator: 3 points high; amber is limited to the header notch, selected metric, and highest-ranked row.
- Footer controls: native buttons with at least a 28-point desktop hit target and accessible labels.
