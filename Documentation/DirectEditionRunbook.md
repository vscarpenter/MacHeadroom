# Direct edition runbook

Operational steps for the Direct delivery chain. Everything below assumes the
dark-launch invariant: the deployed stack has `ClaimFlowEnabled=false`, and
`DIRECT_EDITION_CLAIM_URL` is blank in `Configuration/Shared.xcconfig`. Each
"go live" step is a separate release decision of Vinny's.

## One-time setup (state as of 2026-08-22)

- [x] Sparkle EdDSA keypair generated (`Vendor/Sparkle/bin/generate_keys`);
      private key in the login Keychain, public key pinned in
      `Configuration/Direct.xcconfig` (`DIRECT_SPARKLE_PUBLIC_ED_KEY`).
- [ ] **Back up the private key**: `Vendor/Sparkle/bin/generate_keys -x
      sparkle-private-key.pem`, store it in AWS Secrets Manager
      (`aws secretsmanager create-secret --name macheadroom/sparkle-eddsa
      --secret-string file://sparkle-private-key.pem`), then delete the local
      file. Losing this key orphans every shipped Direct install.
- [ ] App Store Connect In-App Purchase key (`.p8`) in Secrets Manager;
      its ARN is the `AppStorePrivateKeySecretArn` deploy parameter.

## Publishing a Direct release

1. `./Scripts/fetch-sparkle.sh` (idempotent).
2. `DIRECT_DEVELOPER_ID_APPLICATION=… DIRECT_DEVELOPER_TEAM_ID=… \
   DIRECT_NOTARY_PROFILE=… ./Scripts/release-direct.sh`
   — archives, notarizes, staples app + DMG; refuses a build without an
   embedded signed Sparkle and a non-empty `SUPublicEDKey`.
3. `DIRECT_RELEASE_BUCKET=… DIRECT_SITE_BUCKET=… \
   DIRECT_CLOUDFRONT_DISTRIBUTION_ID=… \
   ./Scripts/publish-direct.sh build/direct-release/<ts>/System\ Headroom\ Direct.dmg`
   — stages `updates/System-Headroom-Direct-<version>.dmg`, signs the appcast
   entry with the Keychain EdDSA key, writes `updates/latest.json`, and (after
   an interactive confirm) uploads DMG + manifest to the release bucket and
   the appcast to the site, then invalidates `/direct/appcast.xml`.

Existing Direct installs pick the release up from the appcast; new customers
get it through the claim flow's presigned URL, both from the same object.

## Dark smoke test (run after any deploy)

```
curl -s https://<api>/prod/health            # 200 {"status":"ok","claimFlowEnabled":false}
curl -s -X POST https://<api>/prod/v1/claims -d garbage    # 503 generic
curl -s -X POST https://<api>/prod/v1/handoff -d garbage   # 503 generic
```

Also load `https://www.macheadroom.com/direct/claim/<random-uuid>` — the page
must render its expired state, make one same-origin POST, and set no cookies.

## Going live (only after App Review confirms the transfer model in writing)

Order matters; each step is reversible by redeploying with the previous value.

1. Re-run the dark smoke test; confirm a current release exists in the bucket
   (`updates/latest.json`).
2. `sam deploy` with `ClaimHandoffBaseUrl=https://www.macheadroom.com/direct/claim`
   and `ClaimFlowEnabled=true`.
3. Live smoke: a real claim from a TestFlight/App Store build in-hand, token
   redeems on the page, DMG downloads, checksum matches `latest.json`.
4. Set `DIRECT_EDITION_CLAIM_URL` in `Configuration/Shared.xcconfig` to the
   claim endpoint, bump the version, submit to App Review as usual. The claim
   UI in Settings/Help appears only in builds carrying that URL.

## Rollback

- Kill the flow instantly: `sam deploy` with `ClaimFlowEnabled=false` — both
  routes return 503 before parsing; the app's UI keeps working and shows its
  generic failure copy.
- Pull a bad release: `publish-direct.sh` a previous DMG (it rewrites
  `latest.json` and the appcast); Sparkle never downgrades automatically, so
  also bump the version when re-cutting.
