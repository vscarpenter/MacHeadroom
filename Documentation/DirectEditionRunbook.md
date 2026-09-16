# Direct edition runbook

Use `./Scripts/direct-release` to configure the release Mac, advance the build,
run all tests, create a notarized DMG, and prepare its appcast with signed downloads.
Publishing is a separate command that uses the same DMG without rebuilding.

The Mac App Store edition remains paid and sandboxed. The Direct edition is a
free website download with Developer ID signing, Hardened Runtime, and App
Sandbox disabled. It requires no purchase, account, receipt, or claim token.
Both editions keep separate bundle identifiers and share the version and build
in `Configuration/Shared.xcconfig`.

Direct checks for Sparkle updates at launch and offers About → Check for
Updates. Automatic checking does not promise unattended installation. The App
Store edition uses App Store updates and contains no Sparkle framework.

## Set up the release Mac once

Use a full Xcode installation and install a **Developer ID Application**
certificate with its private key through Xcode → Settings → Accounts → Manage
Certificates. Certificate creation remains a manual Apple Developer step; an
Apple Development or Apple Distribution certificate cannot replace it. See
[Apple's Developer ID guidance](https://developer.apple.com/developer-id/).

From the repository root, run:

```bash
./Scripts/direct-release setup
./Scripts/fetch-sparkle.sh
./Scripts/direct-release credentials
./Scripts/direct-release doctor --online
```

For this workspace's sibling landing-page checkout, setup can also import its
existing deployment destinations:

```bash
./Scripts/direct-release setup --site-config ../macheadroom.com/.env.local
```

That option reads only the literal `S3_BUCKET` and
`CLOUDFRONT_DISTRIBUTION_ID` values, without executing the file, and stores them
as `DIRECT_SITE_BUCKET` and `DIRECT_CLOUDFRONT_DISTRIBUTION_ID`. Explicit `--set`
values override imported settings. The release bucket still needs a separate
`--set DIRECT_RELEASE_BUCKET=...` before publishing.

`setup` creates the ignored `Configuration/DirectRelease.local.json` from
`Configuration/DirectRelease.example.json`, preserves existing settings, and
selects the installed Developer ID identity when exactly one matches the
configured team. It does not create certificates or store secrets. If needed,
set your team and certificate explicitly, then rerun `doctor`:

```bash
./Scripts/direct-release setup \
  --set DIRECT_DEVELOPER_TEAM_ID='TEAMID' \
  --set DIRECT_DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
```

The default Xcode path is `/Applications/Xcode.app/Contents/Developer`. Use
`setup --set DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer` for another
installation. Nonempty exported environment values override the local JSON.
Supported settings are listed in the example file; keep passwords and private
keys out of both files and command-line arguments.

`credentials` opens Apple's interactive `notarytool store-credentials` prompts
in your terminal. Enter the Apple Account, team, and app-specific password when
asked. They are stored in Apple Keychain under the configured
`DIRECT_NOTARY_PROFILE` (default `SystemHeadroomDirect`). See
[Apple's notarytool setup](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)
for supported authentication options.

`doctor` checks local tools, signing identity, and release settings.
`doctor --online` also asks Apple to validate the notarization credentials and
signs disposable data with Sparkle's existing Keychain key, verifying it against
the app's pinned public key. macOS may request Keychain access. A successful
check does not create a release or publish anything.

### Preserve the Sparkle signing identity

`DIRECT_SPARKLE_PUBLIC_ED_KEY` is already pinned in
`Configuration/Direct.xcconfig`. The matching private EdDSA key must be in the
release Mac's Keychain; the repository supplies no private signing material.

Keep a protected backup of that existing key before distributing a release.
Sparkle's `generate_keys -x <private-backup-path>` exports it and
`generate_keys -f <private-backup-path>` restores it on another release Mac.
Use a secure location outside the checkout, transfer it to your approved secret
store, and remove any temporary export. Do not print the key or include it in a
release artifact. See [Sparkle's key documentation](https://sparkle-project.org/documentation/).

If the key is missing, restore the matching backup. Routine releases must not
generate a replacement key or change the public key: rotation needs a migration
plan for installed apps. Both online readiness checks and staging verify that
the signing key matches the app's pinned public key.

## Prepare each release

```bash
# Keep the marketing version and increment the shared integer build.
./Scripts/direct-release bump

# Choose a new directory, or omit --output-dir for an automatically unique one.
RUN="build/direct-runs/$(date +%Y%m%d-%H%M%S)-$$"
./Scripts/direct-release prepare --output-dir "$RUN"
./Scripts/direct-release status "$RUN"
```

Use `bump --version 1.2` to change the marketing version while incrementing the
build, or `bump --version 1.2 --build 20` to choose both. The build must increase
and the marketing version cannot decrease. The command updates the shared
xcconfig and exact release-identity test expectations together, refusing to
modify either when the current values disagree. This advances both editions;
the App Store archive still uses the SystemHeadroom scheme without the Direct
overlay. Review and commit the version changes with the release source.

`prepare` performs these steps in order:

1. Fetch checksum-pinned Sparkle and run online release-readiness checks.
2. Run every Python release-tooling test, Swift appcast-signature tests, and
   the complete hosted macOS app test suite.
3. Archive a universal Apple silicon/Intel Direct app, verify signing and
   entitlements, notarize and staple the app, then create, notarize, and staple
   its signed DMG.
4. Stage the free-download files and generate and verify the appcast with signed
   downloads.

Any test failure stops preparation before the archive. A zero-test run is also
rejected. Four live-port tests failed in the previous local verification; if
those failures recur, preparation stops and their cause must be resolved. The
release workflow provides no test-skip option.

Apple must return `Accepted` before the app and DMG proceed through stapling and
validation. The release checks include both architectures, bundle identity,
Developer ID signature, Hardened Runtime, disabled sandbox/debug entitlements,
embedded Sparkle, and the expected update feed/public key. The DMG includes an
Applications shortcut. `prepare` contacts Apple for signing assessment and
notarization, but uploads no files to the website.

The default run location is a unique directory under `build/direct-runs/`.
An explicit `--output-dir` must not already exist. Each run retains:

- `workflow.json`: step status, timestamps, log paths, and release location.
- `logs/`: separate test, notarization, staging, and publishing logs.
- `release/`: the versioned DMG, `release.json`, `SHA256SUMS`, app archive,
  and notarization receipts.
- `stage-<step>/`: verified `appcast.xml`, app `Info.plist`, and `updates/`
  containing the immutable DMG, stable-name DMG, and `latest.json` manifest.

Keep the printed run path, or set `RUN` to it again in a new terminal.
`./Scripts/direct-release status "$RUN"` shows the saved state and log paths.

Open the DMG, install into Applications, and test launch, process controls,
About, and Check for Updates before publishing. Verify an update offer from an
older Direct version as well. Both editions can be installed together, but
launching one closes the other through the shared single-instance guard.

## Configure hosting and publish

Save the intended deployment settings once, using an existing AWS CLI profile:

```bash
./Scripts/direct-release setup \
  --set DIRECT_RELEASE_BUCKET='your-release-bucket' \
  --set DIRECT_SITE_BUCKET='your-site-bucket' \
  --set DIRECT_CLOUDFRONT_DISTRIBUTION_ID='your-distribution-id' \
  --set AWS_PROFILE='your-aws-profile'
./Scripts/direct-release doctor --online --publishing
```

The publishing check validates Apple/Sparkle readiness plus AWS credentials and
access to both buckets and the CloudFront distribution. It does not create
buckets, configure routes, or prove public delivery. Before publication, the
site must support these HTTPS routes without authentication or claim tokens:

| Public route | S3 object |
| --- | --- |
| `/direct/updates/*` | Release bucket: `updates/*` |
| `/direct/appcast.xml` | Site bucket: `direct/appcast.xml` |

A CloudFront path behavior alone does not remove `/direct` from the URI.
Configure the rewrite/origin routing so these paths reach the specified object
keys, with CloudFront authorized to read the release bucket. A public S3 bucket
is unnecessary. Missing DMGs or feeds must not return the landing-page HTML.

The landing page's free-download button should point to:

```text
https://www.macheadroom.com/direct/updates/System-Headroom-Direct.dmg
```

Keep the paid Mac App Store link as the other purchase option. These scripts do
not edit the landing page or provision CloudFront routes. Its deployment must
preserve the publisher-managed appcast and release objects. Adding this tooling
does not establish that a public download has been deployed.

After inspecting the prepared DMG and configuring hosting, explicitly publish
that run:

```bash
./Scripts/direct-release publish "$RUN"
./Scripts/direct-release status "$RUN"
```

`publish` checks the retained DMG's checksum and size against its release
receipt, then publishes those exact bytes without rebuilding. The publisher
rejects a lower build number or replacement bytes for an existing version/build
URL. An exact retry is allowed.

It uploads the immutable DMG first and downloads it through the public URL to
verify its bytes before updating the stable download, manifest, or appcast. It
then invalidates CloudFront paths, waits for completion, and compares public
responses with the staged files. Successful delivery receipts are retained in
the run. Only a successful publication verifies those remote artifacts.

Finally, use the live landing-page button to download and install on a test Mac.
Confirm the browser download opens normally and an older Direct installation
discovers the update. The script verifies delivery of expected bytes; these
checks verify the customer experience.

## Recover a failed run

Inspect `status` and the named logs before retrying:

| Failure | Next action |
| --- | --- |
| Readiness or tests | Fix the reported issue and run `prepare` with a new output directory. |
| Archive or notarization | Inspect the logs and Apple submission receipts, fix the issue, then start a new `prepare` run. Existing output directories cannot be reused. |
| Staging after a completed notarized release | Fix the reported issue, then run `./Scripts/direct-release stage "$RUN"` to stage the same DMG. |
| Publishing | Fix credentials, hosting, or the reported delivery issue, then retry `./Scripts/direct-release publish "$RUN"`. Do not rebuild or bump the version for a delivery retry. |

Retain released DMGs and receipts. If changed source must replace an already
published release, increase the build and prepare a new run. To undo a faulty
release, build the previous good source with a higher build number. Sparkle
does not automatically downgrade installed apps.

## Underlying scripts and CI

The wrapper supplies settings from the ignored JSON and records the workflow.
The lower-level scripts remain available for individual operations; when
running them directly, export the required settings in your shell.

| Purpose | Command |
| --- | --- |
| Local build with ad-hoc signing | `./Scripts/build-direct.sh --ad-hoc` |
| Local build with project development signing | `./Scripts/build-direct.sh` |
| Local release checks only | `./Scripts/release-direct.sh --preflight` |
| Archive, sign, notarize, and package without the wrapper's test/staging steps | `./Scripts/release-direct.sh --output-dir <new-directory>` |
| Stage a retained DMG without uploading | `./Scripts/publish-direct.sh --stage-only <dmg>` |
| Explicitly publish a retained DMG | `./Scripts/publish-direct.sh --publish <dmg>` |

Staging checks the signed, stapled app and DMG, then verifies the generated
appcast's EdDSA download signature, URL, version, minimum macOS version, and
byte count. The XML feed itself does not use Sparkle's optional feed-signing
feature. Staging does not upload, though macOS may contact Apple for assessment.

`.github/workflows/xcode-build-and-test.yml` runs sandboxed app tests and a
separate Direct job for release-tooling tests, appcast-signature tests,
checksum-pinned Sparkle, and a universal ad-hoc Direct build. CI needs no release
credentials. Signing, notarization, and publication run on the release Mac;
a passing CI run does not create a customer release.

## Legacy claim service

The old purchase-transfer service is independent of free distribution. Keep
`DIRECT_EDITION_CLAIM_URL` blank and any deployed service at
`ClaimFlowEnabled=false`. Do not enable its Settings/Help flow, claim routes,
or receipt verification to offer the free download. Historical notes remain in
`DirectEditionClaimAPI.md` and `DirectEditionSettingsOptionA.md`; their
transfer-policy gates do not gate this free website release.
