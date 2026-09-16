# Direct runbook automation (2026-09-15)

- Added `Scripts/direct-release`: setup, credentials, doctor, bump, prepare,
  stage, publish, and status commands. Local JSON stores only non-secret values;
  exported environment settings take precedence and credentials remain in Keychain.
- Setup detects the signing identity and can import the existing site's bucket
  and CloudFront distribution without executing its environment file. This Mac's
  ignored config was initialized; the release bucket was verified from the
  existing CloudFormation stack and saved locally. No AWS resources changed.
- Preparation fetches Sparkle, checks Apple credentials and update-key continuity,
  requires all tooling and app tests to pass, notarizes, and stages the DMG.
  Each step has a durable status and log. Failed/zero-test runs never archive.
- Publishing explicitly reuses the chosen run's checksummed DMG, supports retries,
  and records a publication receipt only after all public bytes are verified.
- Build-number updates also update the app identity test pins; no version was
  bumped while implementing this workflow (still 1.1 / 15).
- Verification: 65 Python automation/release tests passed; shell syntax and
  whitespace checks passed. No app source or runtime behavior changed this turn.
- Live readiness still requires a Developer ID Application identity. Notary and
  Sparkle private-key availability have not been probed; configure credentials
  interactively, then run `doctor --online`. Prior live-port test failures remain
  a preparation gate; no test-skipping option was added.
- No customer notarization, publication, landing-page changes, or key creation.

# Free Direct distribution (2026-09-15)

## Design and implementation

- Paid, sandboxed Mac App Store edition keeps its existing identity and updates.
- Free, unsandboxed Direct edition uses its existing identity and Sparkle checks.
- Free downloads do not use the historical purchase-claim service; its flags stay disabled.
- Implemented universal local builds, release preflight, Developer ID validation,
  explicit notarization acceptance, signed DMGs with Applications shortcuts,
  and version/build filenames plus release receipts and checksums.
- Publishing stages locally by default. Explicit `--publish` uploads an immutable
  DMG, public stable download, manifest, and appcast after verifying the embedded
  update key; public bytes are checked before and after CDN invalidation.
- Added Direct CI build and release/signature tests. Updated the operator runbook.

## Validation and remaining release work

- Universal Direct 1.1 (15) local build passed; both arm64 and x86_64 confirmed,
  empty entitlements confirmed, and Sparkle/feed configuration present.
- 12 Python release/metadata tests and 34 Swift appcast verification cases passed.
- App Store test host built with development signing: 102 of 106 tests passed.
  Four existing live-port test methods failed (`fetchAndParse`, `udpAgreement`,
  `tickCarriesSockets`, `storePublishesPortGroups`); no app/test source changed.
  The updater-gating suite passed. Log: `build/distribution-tests-development.log`.
- Xcode 27 is installed; use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  while the default developer selection points to Command Line Tools.
- No Developer ID Application identity was available in the release Mac's valid
  signing identities. Configure that certificate and a notarytool profile before
  producing the customer DMG. Sparkle private-key availability was not accessed.
- No customer notarization, cloud upload, landing-page edit, or publication was
  performed. Hosting routes and the free-download button remain release steps.

The older purchase-transfer plans below are historical. Their claim-flow gates
do not apply to the independent free website download.

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
