# Mac Headroom menu bar glyph

`render_glyph.swift` draws the menu bar's template glyph with Core
Graphics: the app icon's four ascending bars, shortened, under a thin
ceiling line. The gap between the tallest bar and the line is the
headroom. The output is a vector PDF; the asset catalog marks it as a
template image, so macOS tints it to match the menu bar and ignores the
baked-in black.

Regenerate with:

```bash
swift render_glyph.swift ../../MacHeadroom/Assets.xcassets/MenuBarGlyph.imageset
```

The bars keep the icon's proportions (10.5% margins, 16% widths, 5%
gaps) with compressed heights so the ceiling line fits inside the 18
point square. Candidate comparisons from the original selection round
lived in the working session; the ceiling-line variant won over the
verbatim icon mark because plain ascending bars read as a cellular
signal indicator at menu bar size.
