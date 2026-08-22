# Direct delivery chain — implementation ledger (2026-08-22)

Deviations from docs/superpowers/plans/2026-08-22-direct-download-delivery.md,
each already distilled to its durable home:

1. INFOPLIST_KEY_ passthrough silently drops unknown keys — the merged
   Info.plist/InfoDirect.plist approach replaced it, and it exposed the
   latent DirectEditionClaimURL bug. -> CLAUDE.md constraint + test pin.
2. Xcode user-script sandbox blocks the embed phase; guard inlined in the
   pbxproj phase, ENABLE_USER_SCRIPT_SANDBOXING=NO in Direct.xcconfig only.
   -> xcconfig comment.
3. Script phases must not mutate the generated Info.plist (regeneration
   race on incremental builds). -> CLAUDE.md constraint.
4. generate_appcast's first Keychain access blocks until Allow is clicked.
   -> DirectEditionRunbook.md.

(The former ports-view ledger's items are all captured in CLAUDE.md's ports
constraints and the test comments; deleted per convention.)
