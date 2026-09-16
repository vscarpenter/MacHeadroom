# Direct edition runbook

The Mac App Store edition remains paid and sandboxed. The Direct edition is
a free website download, without a purchase check, account, receipt, or claim
token. It uses Developer ID signing and Hardened Runtime with App Sandbox
disabled. Both editions retain their own bundle identifiers and inherit the
version and build number from `Configuration/Shared.xcconfig`.

Direct enables Sparkle automatic update checks at app launch and offers
About → Check for Updates. Checking automatically does not mean updates install
without user interaction. The App Store edition uses App Store updates and
contains no Sparkle framework or feed configuration.

## Release-machine setup

Use a full Xcode installation. If `xcode-select -p` points to Command Line
Tools, select Xcode for this shell without changing the machine-wide setting:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
./Scripts/fetch-sparkle.sh
```

The fetch script downloads the pinned Sparkle framework and tools and verifies
their checksum. Developer ID distribution needs a **Developer ID Application**
certificate and its private key in the release machine's Keychain. List
available identities with `security find-identity -v -p codesigning`; an
Apple Development or Apple Distribution certificate is not interchangeable.
See [Apple's Developer ID guidance](https://developer.apple.com/developer-id/).

Create a notarization profile interactively, using an Apple Account with the
appropriate Developer Program team and an app-specific password:

```bash
xcrun notarytool store-credentials SystemHeadroomDirect
```

Answer its credential prompts, then set these non-secret release settings in
your shell, replacing the identity and team placeholders:

```bash
export DIRECT_DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export DIRECT_DEVELOPER_TEAM_ID='TEAMID'
export DIRECT_NOTARY_PROFILE='SystemHeadroomDirect'
```

The profile name refers to credentials held in Keychain; do not put passwords
or private keys in source, shell scripts, or CI logs. Apple also supports
App Store Connect API-key credentials for notarization. See
[Apple's notarytool setup](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

### Preserve the Sparkle signing identity

`DIRECT_SPARKLE_PUBLIC_ED_KEY` is already pinned in
`Configuration/Direct.xcconfig`. That public key is safe to commit. The matching
private EdDSA key must be available to Sparkle's tools in the release machine's
Keychain; private signing material is not supplied by this repository.

Keep a protected backup of the existing private key before distributing a
release. Sparkle's `generate_keys -x <private-backup-path>` exports it and
`generate_keys -f <private-backup-path>` restores it on another release Mac.
Use a secure location outside the checkout, transfer it to your approved secret
store, and remove any temporary export. Do not print it or include it in a
release artifact. See [Sparkle's key documentation](https://sparkle-project.org/documentation/).

Do not generate a replacement key or edit the pinned public key as part of a
routine release. Recover the matching private key from its existing backup if
it is missing. Key rotation needs a separate migration plan for installed apps.
Staging verifies the download signature against the public key embedded in the
new app and fails if they do not match.

## Build and release

| Purpose | Command | Result |
| --- | --- | --- |
| Local test without a certificate | `./Scripts/build-direct.sh --ad-hoc` | Universal Direct app under `build/direct/Build/Products/Release/` |
| Local test with development signing | `./Scripts/build-direct.sh` | Same app, using project signing settings |
| Check local release prerequisites | `./Scripts/release-direct.sh --preflight` | Reports missing tools/settings/certificate without building or contacting Apple |
| Create customer DMG | `./Scripts/release-direct.sh` | Developer ID signed, notarized app and DMG; no publication |
| Choose release output location | `./Scripts/release-direct.sh --output-dir build/direct-release/my-release` | Uses a new directory; refuses an existing path |

Preflight checks that a notarization profile name is configured. Apple validates
that profile's credentials during the actual submission. A successful preflight
does not establish notarization or Sparkle private-key availability.

Before each release, update `MARKETING_VERSION` as needed and increase the
integer `CURRENT_PROJECT_VERSION` in `Configuration/Shared.xcconfig`. Direct
inherits those values; do not add independent version values to its overlay.
The App Store archive continues to use the SystemHeadroom scheme without the
Direct xcconfig overlay and is distributed through Xcode Organizer/App Store
Connect.

The Direct release script verifies the bundle identity, both architectures,
Developer ID signature, Hardened Runtime, absence of sandbox/debug entitlements,
embedded Sparkle, and the update feed/public key. It requires an `Accepted`
notarization result before stapling and validating the app and DMG. The DMG
includes an Applications shortcut.

Default output is a unique directory under `build/direct-release/`, containing:

- `System-Headroom-Direct-<version>-<build>.dmg`
- `release.json` and `SHA256SUMS`
- The app archive and notarization submission receipts

Open the DMG, copy the app into Applications, and test launch, process controls,
About, and Check for Updates before publishing. Test from an older Direct
version as well when verifying an update offer. The two editions may be
installed together, but launching one closes the other through the shared
single-instance guard.

### Continuous integration

`.github/workflows/xcode-build-and-test.yml` runs the sandboxed app tests and a
separate Direct job: release-orchestration/metadata tests, appcast signature
tests, the pinned Sparkle fetch, and a universal ad-hoc Direct build. These
checks need no release credentials. Developer ID signing, notarization, and
publication run explicitly on the release Mac; a passing CI run is not a
customer release.

## Stage the free download

Use the actual DMG path printed by the release script:

```bash
./Scripts/publish-direct.sh --stage-only \
  'build/direct-release/<release-directory>/System-Headroom-Direct-<version>-<build>.dmg'
```

Omitting `--stage-only` has the same behavior. Staging validates the signed,
stapled DMG and app, invokes Sparkle's `generate_appcast` with the existing
Keychain signing key, and verifies the appcast's download signature, URL,
version, minimum macOS version, and byte count against the actual artifact.
The XML contains an EdDSA signature for the DMG; the XML feed itself is not
configured for Sparkle's optional feed-signing feature.

The new directory under `build/direct-publish/` contains `appcast.xml`, the app's
`Info.plist`, and `updates/` with an immutable version/build DMG, a stable-name
DMG copy, and `latest.json` with the version, download URL, size, and SHA-256.
Staging performs no uploads, though macOS may contact Apple while assessing the
signed artifact. The legacy purchase claim setting must be blank.

## Hosting and landing-page prerequisites

Configure these environment variables for the intended deployment:

```bash
export DIRECT_RELEASE_BUCKET='your-release-bucket'
export DIRECT_SITE_BUCKET='your-site-bucket'
export DIRECT_CLOUDFRONT_DISTRIBUTION_ID='your-distribution-id'
```

The publisher uses existing AWS CLI credentials. Before publishing, the site
must support these public HTTPS routes without authentication or claim tokens:

| Public route | S3 object |
| --- | --- |
| `/direct/updates/*` | Release bucket: `updates/*` |
| `/direct/appcast.xml` | Site bucket: `direct/appcast.xml` |

A CloudFront path behavior alone does not remove `/direct` from the URI.
Configure the required rewrite/origin routing so the public path reaches the
object keys above, with CloudFront authorized to read the release bucket. A
public S3 bucket is unnecessary. Ensure custom error handling does not return
the landing-page HTML for missing DMGs or XML feeds.

The site's free-download button should point to this stable URL:

```text
https://www.macheadroom.com/direct/updates/System-Headroom-Direct.dmg
```

Keep the paid Mac App Store link as the other purchase option. These scripts
do not edit the landing page or provision its CloudFront routes. The site's
existing deployment allowlist also does not create a download button or these
routes; update and verify the site separately. Its deployment must preserve
the publisher-managed appcast and release objects.

## Publish and verify delivery

After inspecting the release and configuring hosting, explicitly publish it:

```bash
./Scripts/publish-direct.sh --publish \
  'build/direct-release/<release-directory>/System-Headroom-Direct-<version>-<build>.dmg'
```

The publisher refuses a lower build number or replacement bytes for an existing
version/build URL. An exact retry is allowed. It uploads the immutable DMG first
and downloads it through the public URL to check the bytes before updating the
stable download, manifest, or appcast. It then invalidates their CloudFront
paths, waits for completion, and compares the public responses with the staged
files. Only a successful `--publish` run verifies those remote artifacts.

Finally, use the live landing-page button to download and install the DMG on a
test Mac. Confirm the browser download opens normally and an older Direct
install discovers the update. Script verification proves delivery of the
expected bytes; this end-to-end check verifies the customer experience.

## Recovery and legacy claim service

Retain each released DMG and its receipts. Never replace an immutable versioned
DMG with different bytes. To undo a faulty release, rebuild the previous good
source with a higher build number, then release and publish it normally.
Sparkle does not automatically downgrade installed apps, and the publisher
rejects attempts to publish an older build.

The old purchase-transfer service is independent of free distribution. Keep
`DIRECT_EDITION_CLAIM_URL` blank and any deployed service at
`ClaimFlowEnabled=false`. Do not enable its Settings/Help flow, claim routes,
or receipt verification to offer the free download. Historical claim-service
design notes remain in `DirectEditionClaimAPI.md` and
`DirectEditionSettingsOptionA.md`; their transfer-policy gates do not gate this
independent free website release.
