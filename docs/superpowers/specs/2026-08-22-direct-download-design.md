# Direct-edition purchaser download: delivery chain, Sparkle updates, Help enhancement

**Date:** 2026-08-22
**Status:** Approved by Vinny (design gate passed; spec → plan → implementation continuous)
**Builds on:** `Documentation/DirectEditionClaimAPI.md`, `Documentation/DirectEditionSettingsOptionA.md` (approved 2026-08-16), `docs/superpowers/specs/2026-07-26-popover-quit-design.md`, PR #3 (`fa86c1a`).

## Context

PR #3 delivered the claim *verification* half: the app-side client
(`DirectEditionClaim.swift`), the Option A Settings/Help surface, the
ClaimService SAM verifier, and the notarized Direct release pipeline
(`Scripts/release-direct.sh`) — all deliberately dark. This design adds the
missing *delivery* half so an App Store purchaser can actually download the
non-sandboxed Direct edition, plus Sparkle auto-updates for Direct and the
Help-screen enhancements Vinny asked for. Everything still ships dark.

## Decisions (locked with Vinny, 2026-08-22)

1. **Scope:** full chain end-to-end, dark-launched behind the existing flags.
2. **Handoff UX:** browser claim page at `macheadroom.com/direct/claim/<token>`
   (not a bare presigned URL returned to the app).
3. **Hosting:** extend the existing ClaimService SAM stack; site assets on the
   existing macheadroom.com AWS hosting (same account).
4. **Updates:** Sparkle 2 now, in the Direct build only.
5. **Sparkle wiring:** vendored XCFramework + xcconfig flag (no second target,
   no SPM); App Store binary must contain zero trace of Sparkle.
6. **Deployment:** Claude deploys the dark stack/site with per-step
   confirmation; flag flips remain Vinny's post-App-Review decisions.
7. **Reissues:** rate-limited (not one-shot): 5 reissues / 30 days per
   transaction hash.

## Invariants carried forward (do not violate)

- **Dark launch:** `DIRECT_EDITION_CLAIM_URL` stays blank in
  `Configuration/Shared.xcconfig`; deployed stack keeps
  `ClaimFlowEnabled=false` (claims *and* handoff return generic 503 before
  parsing). Flipping either is a separate release decision of Vinny's, made
  only after App Review confirms the transfer model in writing.
- **Privacy:** raw `appTransactionID` is never stored, logged, or embedded in
  URLs; only the keyed HMAC hash. Client sends only
  `{appTransactionID, bundleID, originalPurchaseDate}`.
- **Fail-closed UI:** Direct-edition UI appears only when
  `!canTerminate && claimEndpoint != nil`; the Direct build shows no transfer
  UI. Termination stays behind `MonitorStore.canTerminate`.
- **Uniform errors:** every server failure is the same generic 503; no oracle.
- **HTTPS-only, anti-redirect** client behavior is test-pinned and unchanged;
  the wire contract of `POST /v1/claims` → `{"claimURL": ...}` is unchanged.
- **Gating is a delivery control, not DRM.**

## Architecture

```
App Store app ──POST evidence──▶ /v1/claims (Lambda) ──▶ Apple App Store Server API
     │                              │ claim record + handoff token (DynamoDB)
     │◀── {claimURL} ───────────────┘
     ▼ NSWorkspace.open
macheadroom.com/direct/claim/<token>          static page (CloudFront)
     │ POST /direct/api/handoff {token}       same-origin CF behavior → API GW
     ▼
handoff Lambda ── consume token, cap downloads ──▶ 15-min presigned S3 URL
     ▼
System Headroom Direct.dmg   private S3 release bucket (notarized + stapled)
     └─ Sparkle: macheadroom.com/direct/appcast.xml (public via CloudFront)
```

## 1. ClaimService changes (`ClaimService/`)

### Reissue semantics (replaces hard conditional put)

After Apple verification succeeds, `GetItem` on `transactionHash`:

- **No record:** create claim record + handoff item; return fresh `claimURL`.
- **Record exists:** if reissue budget allows (≤ 5 reissues per rolling 30
  days, tracked as `reissueCount` + `reissueWindowStart`, all mutations via
  conditional `UpdateItem` so concurrent requests cannot exceed the cap),
  mint a new handoff token, update the record, return the new `claimURL`.
  Over budget → generic 503. Old handoff items are not deleted; their TTL
  expires them.

### DynamoDB single-table shapes (same `ClaimsTable`)

- **Claim record** (exists today, extended): PK `transactionHash`,
  `claimID` (latest), `status`, `reissueCount`, `reissueWindowStart`,
  `expiresAt` (1-year TTL), audit timestamps.
- **Handoff item** (new): PK `handoff#<claimID>` (UUID token from the URL),
  `transactionHash`, `downloadsIssued` (0–3), `expiresAt` (24-hour TTL).
  Strongly consistent `GetItem` by token — no GSI, no eventual-consistency
  race between claim creation and browser handoff.

### New route: `POST /v1/handoff`

Request `{"token": "<claimID>"}` (≤ 4 KB body, validated shape). Flow:
dark-flag gate (503 pre-parse) → `GetItem` handoff item → valid + unexpired +
`downloadsIssued < 3` → conditional increment → read `releases/latest.json`
from the release bucket → return
`{"downloadURL": "<15-min presigned S3 URL>", "version": "...", "sha256": "..."}`.
Any failure → generic 503. Own Lambda + least-privilege role:
`dynamodb:GetItem`/`UpdateItem` on the table, `s3:GetObject` on
`releases/*` only. Reserved concurrency 5; API Gateway throttles inherited.

### `template.yaml` additions

Handoff function + route; private release bucket (SSE, versioned, block all
public access, `DeletionPolicy: Retain`); outputs for bucket name and handoff
URL. `sam validate` must pass.

## 2. Web claim page + site wiring

- Static, framework-free `direct/claim/index.html` (+ small CSS/JS) served for
  `/direct/claim/<token>` via CloudFront rewrite on the existing
  macheadroom.com distribution. Token parsed from `location.pathname` in JS;
  never logged; no analytics, no cookies.
- **Same-origin API:** a `/direct/api/*` CloudFront behavior with API Gateway
  as origin — no CORS, no new certificate or DNS.
- Page states: exchanging → download auto-starts (`location = downloadURL`)
  with install steps (drag to Applications, Gatekeeper right-click note),
  SHA-256 display, bounded "download again" → friendly expiry state
  ("verify again from System Headroom → Settings → Help").
- Token/state logic lives in a pure JS function covered by `node --test`.
- **Precondition task:** read-only inventory of the existing macheadroom.com
  hosting (bucket, distribution, behaviors) before wiring anything.

## 3. Sparkle in the Direct build only

The termination feature stays runtime-gated because the sandbox enforces the
difference; an updater cannot — Sparkle symbols in a MAS binary are an App
Review flag. This is the project's first deliberate compile-time fork,
contained to one flag and one seam.

- **Vendoring:** `Scripts/fetch-sparkle.sh` downloads a pinned Sparkle 2.x
  XCFramework release, verifies a SHA-256 committed in the script, unpacks to
  git-ignored `Vendor/Sparkle/`. Builds needing it fail with instructions if
  absent. No binary in git.
- **`Configuration/Direct.xcconfig` additions:**
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DIRECT_EDITION`;
  `FRAMEWORK_SEARCH_PATHS` → `Vendor/Sparkle/...`; `OTHER_LDFLAGS =
  $(inherited) -framework Sparkle`; `DIRECT_EDITION_BUILD = YES`;
  `INFOPLIST_KEY_SUFeedURL = https://www.macheadroom.com/direct/appcast.xml`;
  `INFOPLIST_KEY_SUPublicEDKey = <public key>`.
- **Embedding:** one always-present Run Script build phase that no-ops unless
  `DIRECT_EDITION_BUILD=YES`, else copies the macOS slice into
  `Contents/Frameworks` and codesigns with `EXPANDED_CODE_SIGN_IDENTITY`.
  Direct is unsandboxed → no Sparkle XPC services required.
- **Source seam:** `UpdaterClient` protocol; under `#if DIRECT_EDITION` a
  wrapper around `SPUStandardUpdaterController`, otherwise a null updater.
  UI: "Check for Updates…" button on the About tab, shown only when
  `canTerminate` and the updater is non-null — invisible and layout-inert in
  the App Store build (existing gating pattern).
- **Enforcement:** `build-direct.sh` / `release-direct.sh` assert Sparkle is
  present, signed, and the two SU keys are in Info.plist; the App Store path
  gains the inverse assertion (no Sparkle in binary or bundle) — same style
  as the existing no-sandbox-entitlement checks.
- **Keys:** Sparkle `generate_keys` EdDSA pair; private key in Vinny's login
  Keychain, encrypted backup to Secrets Manager as a manual runbook step.
  Never in repo or CI.

## 4. Release → publish pipeline

- `release-direct.sh` keeps its job (archive, notarize, staple, spctl) plus
  the new Sparkle assertions.
- **New `Scripts/publish-direct.sh`:** SHA-256 + `sign_update` EdDSA
  signature → upload DMG to the private release bucket → write
  `releases/latest.json` (`{version, key, sha256, releasedAt}`) → regenerate
  `appcast.xml` from a template (version, CloudFront URL, length,
  `edSignature`, `sparkle:minimumSystemVersion` 14.0) → upload appcast +
  invalidate CloudFront. Confirms before each upload.
- **Update archives are intentionally public via CloudFront** (Sparkle cannot
  present claim tokens); one DMG object serves both the presigned claim path
  and the appcast path.

## 5. App-side Help enhancement

Within the approved Option A structure (fixed 440×510 frame preserved;
content scrolls):

- New numbered "What happens next" steps inside the Direct section:
  1 Verify purchase → 2 the download page opens in your browser →
  3 drag System Headroom Direct to Applications.
- Success button renamed **"Open download page"**; caption added noting that
  verifying again later re-downloads the latest version.
- "What Direct adds" copy's "receives updates outside the App Store" becomes
  true via Sparkle; adjust wording to say Direct checks for updates itself.
- Existing accessibility identifiers preserved; `DIRECT_EDITION_CLAIM_URL`
  stays blank; visual tests keep exercising the configured state by
  injection.

## 6. Eligibility policy (closes dark-launch gate 3)

Documented in `Documentation/DirectEditionClaimAPI.md` and surfaced in plain
language on the claim page: any Apple-verified transaction of the App Store
app is eligible; refunds are not revoked (delivery control, not DRM);
limits: 5 reissues / 30 days, 3 downloads / token, 24-hour tokens,
15-minute presigned URLs.

## 7. Testing

- **ClaimService (`node --test`):** flag gate (503 pre-parse), reissue budget
  (fresh, within-cap, over-cap, window rollover), handoff consumption
  (valid, expired, over-cap, unknown token), uniform-503 shape — via
  injected DynamoDB/S3 clients.
- **Claim page:** pure token-parse/state-machine function under `node --test`.
- **App (Swift Testing, TEST_HOST):** existing claim-contract tests stay
  green untouched; new tests for updater-presentation gating (hidden when
  sandboxed / null updater) and updated Help snapshot expectations;
  `PopoverLayoutTests` invariants must hold.
- **Infra:** `sam validate`; post-deploy dark smoke test: `/health` 200 with
  `claimFlowEnabled=false`, `/v1/claims` 503, `/v1/handoff` 503.
- **Direct-only behavior** (real Sparkle check, real download): manual
  checklist, consistent with the existing `.available`-capability policy.

## 8. Deployment order (all dark; per-step confirmation)

1. Stack update (`sam deploy`) — dark flags.
2. Site wiring: claim page upload + CloudFront behaviors.
3. Smoke test (dark responses).
4. App changes land on a feature branch; full suite green.
5. Vinny runs `release-direct.sh` (needs his Developer ID env vars) and
   `publish-direct.sh` when ready.
6. **Runbook (delivered, not executed):** post-App-Review flag flips —
   `ClaimHandoffBaseUrl`, `ClaimFlowEnabled=true`,
   `DIRECT_EDITION_CLAIM_URL` in `Shared.xcconfig` → new App Store
   submission.

## Out of scope / observed

- macheadroom.com landing-page content beyond the claim page.
- The uncommitted `project.pbxproj` 1.1 (12) inline version bump (Vinny's;
  left untouched; note it overrides the `Shared.xcconfig` convention).
- Cross-edition single-instance takeover (newest launch wins across
  editions) is treated as intended behavior; "installs alongside" copy
  remains accurate.
