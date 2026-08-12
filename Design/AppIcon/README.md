# System Headroom app icon

`render_icon.swift` draws the icon with Core Graphics: a graphite gradient
background and four amber bars, flat and full-bleed, no baked-in corner
mask or shadow. Xcode and macOS apply the rounded-square mask and system
shadow at render time.

Regenerate with:

```bash
swift render_icon.swift .
```

That produces three files. `AppIcon-1024.png` is the composite, already
downsized into `SystemHeadroom/Assets.xcassets/AppIcon.appiconset` at all ten
required sizes. `layer-background-1024.png` and `layer-bars-1024.png` are
the same two layers, separated, for Icon Composer.

## Upgrading to Icon Composer

The current build ships the traditional flat iconset, since Icon Composer
is a GUI-only tool with no scriptable interface. It still passes App Store
review, but it skips Apple's newer Liquid Glass depth and per-appearance
variants. To add those:

1. Open Icon Composer (Xcode > Open Developer Tool > Icon Composer).
2. Create a new document. Import `layer-background-1024.png` as the
   background group and `layer-bars-1024.png` as one foreground group.
3. Leave the specular and blur toggles off for both groups. The flat
   gradients already carry the icon's identity; added glass effects
   render inconsistently on a design this simple.
4. Set the Dark variant to the same two layers, optionally dropping the
   bars' brightness by 8 to 10 percent. For Clear and Tinted, let Icon
   Composer derive its own tint from the bars' alpha shape.
5. Save as `AppIcon.icon`, drag it into the Xcode project navigator, and
   set the target's "App Icon Set Name" build setting to `AppIcon`.
   Remove the `Assets.xcassets/AppIcon.appiconset` folder once this is in
   place. Xcode generates the macOS 14.0 fallback images from the same
   file, so nothing else changes.
