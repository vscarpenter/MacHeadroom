# Product purpose

Headroom Monitor is a native macOS menu bar utility that reveals the apps using the most CPU and memory after collapsing each app's related processes into one understandable row.

# Primary user

A Mac user who opens a menu bar utility for a few seconds at a time to identify a resource-heavy app without interpreting Activity Monitor's raw process list.

# Principles

1. **The answer arrives before the ornament.** Remaining headroom and the top consumer must be readable before any brand detail is noticed.
2. **Group the app; reveal the process noise on demand.** The default surface explains app-level impact, while child processes stay behind explicit disclosure.
3. **Native behavior, ownable surface.** Controls, keyboard behavior, accessibility, and window behavior follow macOS conventions; color and one signature motif provide identity.
~~**One broadcast signature, not a costume.** The optional retro mode uses a restrained host cameo, scanlines, and amber ticks only where they reinforce hierarchy.~~ — deprecated 2026-07-25 when Porcelain Native became the default product surface.
4. **Porcelain is the product surface, not a costume.** Warm neutral depth, one amber signal, and generous hierarchy make the data feel ownable without character imagery or decorative effects.
5. **Exact data outranks reassuring language.** Friendly headroom copy always appears with the underlying CPU or memory measurement.

# Success metric for the surface

Within two seconds of opening the popover, the user can identify both the available CPU or memory headroom and the app consuming the most of the selected resource.

# Out of scope

- The sandboxed Mac App Store build does not terminate, throttle, or
  otherwise modify running processes. The unsandboxed Direct build may
  gracefully quit or explicitly force quit a whole app group; it never
  terminates individual child processes or auto-escalates.
- Does not add historical charts or long-term resource tracking.
- Does not require an account, network access, or third-party service.
- Does not replace exact measurements with status language alone.
- Does not animate or distort resource values as part of the broadcast motif.

# Learned constraints

- ~~**2026-07-25** — The existing native popover remains the default; the Porcelain Native broadcast treatment is an explicit Settings opt-in named “Turn on Max Headroom mode.”~~ — deprecated 2026-07-25 when the approved Porcelain direction became the default.
- ~~**2026-07-25** — “Mac” and “Headroom” always use equal size, weight, and color. *Why:* the product name is one identity and should not visually imitate a split-word logo.~~ — deprecated 2026-08-10 when Apple rejected “Mac” in the product name under Guideline 5.2.5.
- **2026-07-25** — Porcelain Native is the default popover appearance, while the compact classic surface remains an explicit fallback. *Why:* the warm, spacious hierarchy makes headroom and top consumers easier to scan and gives the app a distinctive product identity without decorative broadcast imagery.
- **2026-08-10** — The customer-facing product name is “Headroom Monitor”; internal target, module, and bundle identifiers remain `MacHeadroom`. *Why:* Apple required removing “Mac” from the product name while preserving the submitted bundle identifier.
