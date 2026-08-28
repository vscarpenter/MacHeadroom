# Settings window + Direct update feed (2026-08-27)

## Resuming From Here
DONE — four commits on `fix/settings-window-activation`, not pushed.
106 tests / 27 suites green (baseline was 102 passing with 1 red).

## Issue 1 — Settings window opened behind other apps (FIXED)

The app is `LSUIElement` and `MenuBarExtraWindow` is a level-101
non-activating panel: while the panel is open `NSApp.isActive` is true but
the frontmost app is still the user's. The panel dismisses on the gear tap,
the app goes inactive, and the Settings window is left ordered behind that
app. Measured on macOS 26.6.2 with an LSUIElement harness driving its own
status item, ranking the window among on-screen normal windows:

    open only                  rank 1, key = false   <-- the reported bug
    open, then NSApp.activate  rank 0, key = true

`SettingsLink` exposes no action hook, so both call sites became buttons
driving the `openSettings` environment action through `SettingsWindowPresenter`.
Measured working from the panel-content scene context. Vinny still owes a
visual confirmation.

## Issue 2 — "Update Error!" in the Direct build

Two separate causes, one fixed here and one operational:

1. FIXED: automatic checks never started. `UpdaterProvider.shared` is a lazy
   static whose only reader was AboutView, so Sparkle's controller was never
   constructed until Settings → About was opened. Measured 105s with zero
   feed requests; after the fix the feed is fetched within 5s of launch.
2. NOT A CODE DEFECT: the feed is empty. `publish-direct.sh` has never run
   for a real release.

       https://www.macheadroom.com/direct/appcast.xml   -> HTTP 404
       https://www.macheadroom.com/direct/              -> HTTP 404
       https://www.macheadroom.com/direct/latest.json   -> HTTP 404

### Pipeline verification (localhost appcast, no Keychain access)
Proven with a scratch Direct build (bundle id `.LocalTest`, build 11) against
`build/direct-publish/1.1-12/` served over 127.0.0.1:

- feed fetched and parsed, update correctly identified as newer  OK
- enclosure downloaded from the advertised URL                   OK
- install step NOT proven — the scratch bundle identity differs from the
  DMG's `System Headroom Direct`, so Sparkle rejected it with "No suitable
  install is found in the update". Harness artifact, not a pipeline result.

### GO-LIVE BLOCKER: the staged appcast predates the key rotation
`build/direct-publish/1.1-12/appcast.xml` is signed with the OLD EdDSA key
and the app now ships the ROTATED one (pinned in a4f8b13). Verified offline:

    OLD key T73F0l8J+zZ/DL7UpX5GY5w3yL6tqZwFrGLGKil0TnM=  VALID
    NEW key zM7z7Yzk7eLMWDDsD/q44/9cWUXvR3VgnoC38wzta30=  invalid

Publishing that staged appcast as-is would make every Direct update fail
signature verification. Regenerate it with the rotated key before go-live.

## Next
- Vinny: confirm the Settings window now comes forward.
- Vinny: regenerate the appcast with the rotated key, then publish when
  App Review confirmation lands (Documentation/DirectEditionRunbook.md).
- Worth closing later: prove the install step with matching bundle identity.

## Blockers
- None in code. Go-live still gated on Apple's written confirmation.

---

# Direct-edition purchaser download + Help enhancement (2026-08-22)

## Resuming From Here
DONE — all 15 plan tasks complete on branch feat/direct-download-delivery
(14 commits, not pushed; push/PR awaiting Vinny's go-ahead).

- Verified: 102 app tests / 25 suites green; ClaimService 15 green; Site 4
  green; build-direct.sh green (Sparkle embedded+signed, keys in plist);
  publish-direct.sh dry-run proven through EdDSA signing; sam validate ok.
- Deployed DARK to AWS us-east-1: stack update (handoff Lambda + release
  bucket system-headroom-direct-claims-releasebucket-obkpn5ejlqpl),
  claim page + CF function + three /direct/* behaviors on E1CMGVHA0HQHJK.
- Edge smoke green: claim page renders expired state in real Chrome, no
  console errors, no cookies; /direct/api/handoff 503 generic; landing
  page untouched.

## Next
- Vinny: push + PR when ready.
- Vinny: back up the Sparkle private key to Secrets Manager
  (DirectEditionRunbook.md, One-time setup).
- Go-live remains gated on Apple's written App Review confirmation;
  sequence in Documentation/DirectEditionRunbook.md.
- Vinny: eyeball the enhanced Help section (needs an injected claim URL or
  the UI_RENDER PNGs from PopoverVisualTests).

## Blockers
- None.

## Assumptions
- Eligibility policy as documented (refunds not revoked; 5 reissues/30d,
  3 downloads/token, 24h tokens, 15-min URLs).
- Update archives public via CDN by design (Sparkle cannot present claim
  tokens); delivery control, not DRM.
