# Direct-Edition Delivery Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the dark-launched Direct-edition delivery half — claim reissues, one-time handoff with presigned S3 delivery, the macheadroom.com claim page, Sparkle 2.9.6 in the Direct build only, a publish pipeline, and the Help-screen enhancements.

**Architecture:** Extend the existing ClaimService SAM stack with a handoff route and private release bucket; a static same-origin claim page exchanges the one-time token for a 15-minute presigned DMG URL; Sparkle is vendored as a checksum-pinned framework compiled/embedded only under `Direct.xcconfig`; everything stays behind `ClaimFlowEnabled=false` and a blank `DIRECT_EDITION_CLAIM_URL`.

**Tech Stack:** Swift 6 / SwiftUI (app), Node 22 ESM + `node --test` (service & page logic), AWS SAM (Lambda/API GW/DynamoDB/S3/Secrets), Sparkle 2.9.6, zsh scripts.

**Spec:** `docs/superpowers/specs/2026-08-22-direct-download-design.md`

## Global Constraints

- Dark launch: `DIRECT_EDITION_CLAIM_URL` stays blank; deployed `ClaimFlowEnabled=false`; flag flips are Vinny's, post-App-Review, runbook-only.
- Raw `appTransactionID` never stored/logged/URL-embedded; only HMAC hash.
- All server failures are uniform generic 503; no error oracle.
- App Store binary/bundle must contain zero Sparkle (test-pinned).
- Wire contract of `POST /v1/claims` → `{"claimURL": ...}` unchanged; existing `DirectEditionClaimTests` stay green untouched.
- Limits: 5 reissues/30 days, 3 downloads/token, 24 h tokens, 900 s presigned URLs.
- Sparkle pin: 2.9.6, tar.xz SHA-256 `52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192`.
- pbxproj ID scheme: `A1…`=app build file, `A2…`=app file ref, next free numeric suffix; new script phase uses `A8…`.
- Fixed Help frame 440×510; popover intrinsic-size invariants (PopoverLayoutTests) must hold.
- Preserve accessibility identifiers: `system-headroom-help`, `direct-edition-help-section`, `direct-edition-settings-section`, `compare-direct-edition-button`.
- Commits: Conventional Commits + `Claude-Session:` trailer; never stage Vinny's pbxproj version bump into feature commits without resolution (Task 0).

---

### Task 0: Baseline + version-bump resolution

**Files:** Modify (pending Vinny): `Configuration/Shared.xcconfig:10-11`, `SystemHeadroom.xcodeproj/project.pbxproj` (revert inline overrides), `SystemHeadroomTests/AppIdentityTests.swift:31-32`.

- [ ] **Step 1:** Run full suite: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64'`. Expected: `releaseIdentity` FAILS (bundle reports 1.1 (12) from Vinny's uncommitted pbxproj bump; test pins "1.0"/"11"). Everything else passes.
- [ ] **Step 2:** AskUserQuestion: move 1.1/12 into `Shared.xcconfig` (convention), revert the inline pbxproj overrides, update test literals to "1.1"/"12" — or leave his edit untouched and update only test literals. Apply his choice; commit as `chore(release): …` separate from feature work.
- [ ] **Step 3:** Re-run suite; expected all green. Commit.

### Task 1: ClaimService reissue logic (`src/store.mjs`)

**Files:** Create `ClaimService/src/store.mjs`, `ClaimService/test/store.test.mjs`.

**Interfaces — Produces:**
`recordClaim({store, tableName, transactionHash, originalPurchaseDate, now, newClaimID}) -> Promise<string /*claimID*/>`;
`consumeHandoff({store, tableName, token, now}) -> Promise<void>` (throws if not redeemable);
constants `REISSUE_LIMIT=5`, `REISSUE_WINDOW_SECONDS=2592000`, `HANDOFF_TTL_SECONDS=86400`, `DOWNLOADS_PER_HANDOFF=3`, `CLAIM_TTL_SECONDS=31536000`. `store` is any `{send(command)}` (DynamoDBDocumentClient-compatible).

- [ ] **Step 1: Failing tests** in `test/store.test.mjs` using a fake `{send}` dispatching on `command.constructor.name` (`GetCommand`/`PutCommand`/`UpdateCommand` imported from `@aws-sdk/lib-dynamodb`): fresh claim creates claim item (reissueCount 0, status "active", 1-year TTL) + handoff item (`transactionHash: "handoff#<uuid>"`, downloadsIssued 0, 24 h TTL); reissue within budget increments count via conditional update keyed on previous `claimID` and mints new handoff; reissue over budget (count=5 in window) throws without writes; window rollover (now − windowStart ≥ 30 d) resets count to 1; legacy record (no reissueCount fields) treated as count 0.
- [ ] **Step 2:** `cd ClaimService && npm test` → FAIL (module missing).
- [ ] **Step 3: Implement** `recordClaim`: consistent `GetCommand`; absent → `PutCommand` with `attribute_not_exists(transactionHash)`; present → budget check then `UpdateCommand` `SET claimID=:c, reissueCount=:n, reissueWindowStart=:w, expiresAt=:e, validatedAt=:v` with `ConditionExpression: "claimID = :previous"`; then handoff `PutCommand` with `attribute_not_exists`. `consumeHandoff`: UUID-v4 regex prefilter; consistent `GetCommand` on `handoff#<token>`; explicit `expiresAt > now` and `downloadsIssued < 3` checks; conditional increment `UpdateCommand`.
- [ ] **Step 4:** `npm test` → PASS. **Step 5:** Commit `feat(claims): add rate-limited reissue and handoff-token store`.

### Task 2: Release lookup + presign (`src/releases.mjs`)

**Files:** Create `ClaimService/src/releases.mjs`, `ClaimService/test/releases.test.mjs`; Modify `ClaimService/package.json` (add `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner` pinned `3.1110.0`, adjust to nearest published if npm rejects; run `npm install`).

**Interfaces — Produces:** `latestRelease({client, bucket}) -> Promise<{version, build, key, sha256}>` (validates `key` starts `"updates/"`); `presignDownload(key, {client, bucket}) -> Promise<string>`; `DOWNLOAD_URL_TTL_SECONDS = 900`.

- [ ] **Step 1: Failing tests:** fake S3 client returns `{Body: {transformToString: async () => JSON.stringify(manifest)}}`; valid manifest parses; missing/malformed fields throw; key outside `updates/` throws.
- [ ] **Step 2:** FAIL. **Step 3:** Implement per spec (GetObject `updates/latest.json`; `getSignedUrl(..., {expiresIn: DOWNLOAD_URL_TTL_SECONDS})`). **Step 4:** PASS. **Step 5:** Commit `feat(claims): read release manifest and presign downloads`.

### Task 3: Wire handlers + template

**Files:** Modify `ClaimService/src/handler.mjs` (replace lines 162-176 claim write with `recordClaim`; add `export async function handoff(event)` with dark gate → parse `{token}` (≤1 KB) → `consumeHandoff` → `latestRelease` → `presignDownload` → `200 {downloadURL, version, sha256}`; any failure → generic 503 with hashed correlationID, mirroring lines 179-185); Modify `ClaimService/template.yaml` (ReleaseBucket: Retain, AES256 SSE, versioned, full PublicAccessBlock; HandoffFunction: `src/handler.handoff`, reserved concurrency 5, env `CLAIM_FLOW_ENABLED`/`CLAIMS_TABLE_NAME`/`RELEASE_BUCKET_NAME`, policy `dynamodb:GetItem,UpdateItem` on table + `s3:GetObject` on `${ReleaseBucket.Arn}/updates/*`, event POST `/v1/handoff`; extend ClaimFunction policy with `dynamodb:GetItem,UpdateItem`; Outputs `HandoffEndpoint`, `ReleaseBucketName`); extend `test/handler.test.mjs` with dark-gate tests (`CLAIM_FLOW_ENABLED` unset → both `handler` and `handoff` return 503 with generic body before parsing garbage input).

- [ ] Steps: failing gate tests → FAIL → implement → `npm run check && npm test` PASS → `sam validate --lint` (in ClaimService/) → Commit `feat(claims): add dark-gated handoff route and release bucket`.

### Task 4: Claim page

**Files:** Create `Site/direct/lib/claim-core.mjs`, `Site/test/claim-core.test.mjs`, `Site/package.json` (`{"name":"macheadroom-site","private":true,"type":"module","scripts":{"test":"node --test"}}`), `Site/direct/claim/index.html`, `Site/direct/claim/claim.css`, `Site/direct/claim/claim.js`.

**Interfaces — Produces:** `tokenFromPath(pathname) -> string|null` (accepts `/direct/claim/<uuid-v4>` with optional trailing slash); `handoffOutcome(status, payload) -> {kind:"ready", downloadURL, version, sha256} | {kind:"expired"}` (ready only for 200 + https downloadURL + string version/sha256).

- [ ] **Step 1: Failing tests** for both functions (valid token, junk, traversal attempts; 200-valid, 200-malformed, 503). **Step 2:** FAIL. **Step 3:** Implement core; then page: `claim.js` (module, absolute `import "/direct/lib/claim-core.mjs"`) parses token, `fetch("/direct/api/handoff", {method:"POST", headers:{"content-type":"application/json"}, body: JSON.stringify({token})})`, on ready sets `location.href = downloadURL` and reveals install steps (open DMG → drag to Applications → Gatekeeper note) + version + SHA-256 `<code>`, retry button (page-local cap 3); expired state points back to System Headroom → Settings → Help → Verify. No cookies/analytics/external requests; token never logged. Porcelain-inspired self-contained CSS (system font stack, charcoal/amber echoing the app icon, light+dark via `prefers-color-scheme`). **Step 4:** `cd Site && npm test` PASS. **Step 5:** Commit `feat(site): add one-time claim page for the Direct download`.

### Task 5: Vendor Sparkle

**Files:** Create `Scripts/fetch-sparkle.sh` (+x); Modify `.gitignore` (add `Vendor/`).

- [ ] Script: pin `version=2.9.6`, `sha256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192`; skip if `Vendor/Sparkle/.version` matches; curl → shasum verify → extract tar.xz (flat layout: `Sparkle.framework`, `bin/`) → `ditto` framework + bin into `Vendor/Sparkle/` → write `.version`. Verify: run twice (fetch, then idempotent skip); `Vendor/Sparkle/bin/sign_update` exists. Commit `build(direct): vendor Sparkle 2.9.6 behind a checksum-pinned fetch`.

### Task 6: Updater seam + App Store cleanliness

**Files:** Create `SystemHeadroom/App/UpdaterClient.swift` (4 pbxproj entries: clone `DirectEditionClaim.swift` pattern at pbxproj lines 12/78/185/396 with next free `A1…`/`A2…` suffix); Modify `SystemHeadroomTests/AppIdentityTests.swift`.

**Interfaces — Produces:** `@MainActor protocol UpdaterClient { var canCheckForUpdates: Bool { get }; func checkForUpdates() }`; `@MainActor func makeUpdaterClient() -> UpdaterClient?` (nil unless `DIRECT_EDITION`); `@MainActor enum UpdaterProvider { static let shared: UpdaterClient? }`; `enum UpdaterPresentation { static func isVisible(capability: TerminationCapability, hasUpdater: Bool) -> Bool }` (true only for `.available && hasUpdater`).

- [ ] **Step 1: Failing tests** in AppIdentityTests: truth table of `UpdaterPresentation.isVisible` (4 cases); `appStoreBuildHasNoSparkle` (`NSClassFromString("SPUStandardUpdaterController") == nil` + no `Sparkle.framework` in `Bundle.main.privateFrameworksURL` listing). **Step 2:** build fails (type missing). **Step 3:** Implement — `#if DIRECT_EDITION` imports Sparkle, `SparkleUpdaterClient` wraps `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`; `#else` `makeUpdaterClient()` returns nil. **Step 4:** suite PASS. **Step 5:** Commit `feat(direct): add compile-gated Sparkle updater seam`.

### Task 7: About-tab update button

**Files:** Modify `SystemHeadroom/UI/AboutView.swift` (add `var updater: UpdaterClient? = UpdaterProvider.shared`, `var capability: TerminationCapability = .current`; after the links VStack: `if UpdaterPresentation.isVisible(capability: capability, hasUpdater: updater != nil), let updater { Button("Check for Updates…") { updater.checkForUpdates() } .padding(.top, 8) .accessibilityIdentifier("check-for-updates-button") }`); Modify `SystemHeadroomTests/PopoverVisualTests.swift` (render AboutView injected both ways; sandboxed/default → identical fitting size, no button).

- [ ] TDD steps as above; suite PASS; commit `feat(direct): surface Check for Updates in the Direct About tab`.

### Task 8: Direct build wiring

**Files:** Modify `Configuration/Direct.xcconfig` (append: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DIRECT_EDITION`; `DIRECT_EDITION_BUILD = YES`; `FRAMEWORK_SEARCH_PATHS = $(inherited) $(SRCROOT)/Vendor/Sparkle`; `OTHER_LDFLAGS = $(inherited) -framework Sparkle`; `INFOPLIST_KEY_SUFeedURL = https:/$()/www.macheadroom.com/direct/appcast.xml` — `$()` defeats xcconfig `//` comment; `INFOPLIST_KEY_SUEnableAutomaticChecks = YES`; `INFOPLIST_KEY_SUPublicEDKey = $(DIRECT_SPARKLE_PUBLIC_ED_KEY)`; `DIRECT_SPARKLE_PUBLIC_ED_KEY =` blank until Task 9); Create `Scripts/embed-sparkle.sh` (no-op unless `DIRECT_EDITION_BUILD=YES`; ditto framework into `${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}`; codesign inner XPCServices/Autoupdate/Updater.app then framework with `--force --options runtime --timestamp --sign "${EXPANDED_CODE_SIGN_IDENTITY}"` when identity ≠ "-"); Modify pbxproj (new `A80000000000000000000001` PBXShellScriptBuildPhase invoking the script, `alwaysOutOfDate = 1`, appended to app target buildPhases after Resources at line ~303); Modify `Scripts/build-direct.sh` (assert `Contents/Frameworks/Sparkle.framework` present + SUFeedURL exact; WARN-only on empty SUPublicEDKey).

- [ ] Verify red→green: `./Scripts/build-direct.sh` fails before wiring (no Sparkle assertion fails), passes after; normal suite still green and `appStoreBuildHasNoSparkle` still passes. Commit `build(direct): compile, embed, and verify Sparkle in the Direct flavor only`.

### Task 9: Release hardening + EdDSA keys

**Files:** Modify `Scripts/release-direct.sh` (hard-fail on missing Sparkle.framework, empty SUPublicEDKey, or unsigned embedded framework: `codesign --verify --strict "$app/Contents/Frameworks/Sparkle.framework"`); Modify `Configuration/Direct.xcconfig` (`DIRECT_SPARKLE_PUBLIC_ED_KEY = <output>`).

- [ ] Ask Vinny to run `! Vendor/Sparkle/bin/generate_keys` (private key → his login Keychain; paste printed public key). If deferred: leave blank, record in runbook, release-direct.sh still hard-fails (correct). Commit `build(direct): require Sparkle signing material in customer releases`.

### Task 10: Help enhancements

**Files:** Modify `SystemHeadroom/UI/HelpView.swift` (in `directEditionTransfer`: "What Direct adds" detail ends "…installs alongside this edition, and keeps itself up to date with built-in update checks."; after third HelpFact add three `HelpStep`s — 1 "Verify your purchase" / "System Headroom sends only your App Store purchase evidence to the transfer service."; 2 "Open the download page" / "Your browser opens macheadroom.com with a private link to the notarized installer."; 3 "Install Direct" / "Open the downloaded disk image and drag System Headroom Direct into Applications."; rename button `Open claim page` → `Open download page`; under it add `Text("Verify again anytime to download the newest version.").font(.caption).foregroundStyle(.secondary)`); Modify `SystemHeadroomTests/PopoverVisualTests.swift` if snapshot expectations shift.

- [ ] Suite PASS (PopoverLayoutTests untouched — Help scrolls inside fixed 440×510). Commit `feat(help): explain the Direct download and update path`.

### Task 11: Publish script

**Files:** Create `Scripts/publish-direct.sh` (+x): require `DIRECT_RELEASE_BUCKET`, `DIRECT_SITE_BUCKET`, `DIRECT_CLOUDFRONT_DISTRIBUTION_ID`; arg = notarized DMG; mount read-only → extract version/build/SUPublicEDKey (fail if key empty) → stage `updates/System-Headroom-Direct-<version>.dmg` → shasum → `Vendor/Sparkle/bin/generate_appcast --download-url-prefix https://www.macheadroom.com/direct/updates/ -o appcast.xml` → write `latest.json {version,build,key,sha256,releasedAt}` → interactive confirm → `aws s3 cp` DMG+latest.json to release bucket, appcast to site bucket → CloudFront invalidation `/direct/appcast.xml`.

- [ ] Verify with `zsh -n` + a dry-run against a scratch dir (skip uploads by answering n). Commit `build(direct): add publish pipeline for releases and appcast`.

### Task 12: Docs + runbook

**Files:** Modify `Documentation/DirectEditionClaimAPI.md` (handoff contract `{token} → {downloadURL, version, sha256}`, limits, eligibility policy: any verified transaction eligible, refunds not revoked, delivery-control-not-DRM); Create `Documentation/DirectEditionRunbook.md` (flag-flip sequence post-App-Review, key backup to Secrets Manager, publish flow, dark smoke checks); Modify `README.md` Build flavors + `CLAUDE.md` (Sparkle-only-in-Direct constraint).

- [ ] Commit `docs(direct): document handoff contract, eligibility policy, and runbook`.

### Task 13: AWS inventory (read-only)

- [ ] `aws sts get-caller-identity`; `aws cloudformation list-stacks` (find claim stack or confirm absent); `aws s3api list-buckets`; `aws cloudfront list-distributions` (find macheadroom.com alias, origins, behaviors). Record findings in `tasks/todo.md`. No mutations.

### Task 14: Deploy dark + site wiring + smoke

- [ ] With per-step confirmation: `sam build && sam deploy` (dark params); upload `Site/direct/**` to site bucket; add CloudFront behaviors — `/direct/api/*` → API GW origin (origin path `/prod`, CF Function rewriting `/direct/api/handoff` → `/v1/handoff`), `/direct/claim/*` → site origin (CF Function rewrite to `/direct/claim/index.html`), `/direct/updates/*` → release bucket via OAC (+ bucket policy for the distribution ARN); invalidate. Smoke: `/health` 200 `claimFlowEnabled:false`; `/v1/claims` and `/direct/api/handoff` → 503; claim page renders expired state for a junk token.

### Task 15: Close out

- [ ] Full suite green; `./Scripts/build-direct.sh` green; ClaimService + Site `npm test` green; update `tasks/todo.md`; distill notes; change report + comprehension quiz; ask Vinny about push/PR (never push unasked).

## Self-review
Spec coverage: reissue→T1, handoff→T2/T3, bucket/template→T3, page→T4/T14, Sparkle→T5-T9, publish→T11, Help→T10, policy/docs→T12, deploy/smoke→T13/T14 — no gaps. Types cross-checked (`recordClaim`/`consumeHandoff`/`latestRelease`/`UpdaterClient`/`UpdaterPresentation` consistent across tasks). No placeholders remain (SUPublicEDKey blank-until-generated is a modeled state, not a TBD).
