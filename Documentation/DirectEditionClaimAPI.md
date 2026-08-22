# Direct edition claim API

The App Store build makes no claim-service request until its
`DIRECT_EDITION_CLAIM_URL` build setting contains an HTTPS endpoint. Do not
enable that setting or expose the UI in an App Store submission until Apple has
confirmed this transfer model in writing.

## Client contract

`POST <DIRECT_EDITION_CLAIM_URL>`

```json
{
  "appTransactionID": "Apple-generated app transaction ID",
  "bundleID": "com.vinnycarpenter.MacHeadroom",
  "originalPurchaseDate": "2026-08-13T18:42:00Z"
}
```

Successful responses are `201 Created` and contain only a short-lived HTTPS
handoff URL:

```json
{
  "claimURL": "https://www.macheadroom.com/direct/claim/<one-time-token>"
}
```

The client never transmits process samples, computer names, preferences, or an
App Store receipt. It treats all failures as generic, user-safe errors and
never exposes a claim-service host or response body in the UI. The endpoint and
handoff URL must be HTTPS with a host, and the endpoint must not redirect.

## Required server checks

The endpoint is not a receipt validator. The server must use a protected App
Store Connect API key to call Apple's **Get App Transaction Info** API with the
submitted `appTransactionID`, then validate the signed response with Apple's
App Store Server Library. It must reject requests unless all of these hold:

1. The returned app bundle identifier is `com.vinnycarpenter.MacHeadroom`.
2. The returned App Store app ID is the production System Headroom app ID.
3. The signed app transaction ID exactly matches the submitted ID.
4. The claim is rate-limited by a keyed hash of the app transaction ID, with at
   most one active handoff token at a time.

`Get App Transaction Info` establishes that an Apple Account downloaded this
specific app; it isn't a standalone, current-paid-entitlement or refund-status
signal. The app transaction ID persists if the customer redownloads, receives
a refund, or repurchases the app. The handoff policy must therefore define
additional eligibility handling before any Direct download is issued.

Store only a keyed hash of the app transaction ID, the eligibility result, and
an audit timestamp. Treat the raw transaction ID as a durable account-linked
identifier: do not log it, put it in a URL, or reuse it as a license key.

## Handoff contract (implemented 2026-08-22)

The claim page at `https://www.macheadroom.com/direct/claim/<token>` exchanges
its token same-origin (a CloudFront `/direct/api/*` behavior fronting the same
API):

`POST /v1/handoff` with `{"token": "<one-time-token>"}` returns, on success:

```json
{
  "downloadURL": "<15-minute presigned URL for the current notarized DMG>",
  "version": "1.1",
  "sha256": "<hex digest of the DMG>"
}
```

Every failure — unknown, expired, or exhausted token, missing release
manifest, disabled flag — is the same generic `503`. Like the claim route, the
handoff route returns `503` before parsing while `ClaimFlowEnabled` is false.

## Eligibility policy

Any Apple-verified app transaction of the App Store app is eligible. Refunds
are not revoked — download gating is a delivery control, not DRM — and no
account, email, or license key is ever involved. Abuse is bounded by limits,
enforced server-side and mirrored in `ClaimService/src/store.mjs`:

- **5 reissues per rolling 30 days** per transaction hash (`POST /v1/claims`
  repeats within budget mint a fresh token; beyond it, generic `503`).
- **24-hour handoff tokens**, each good for **3 download URLs**.
- **15-minute presigned download URLs.**

## Accountless Direct download

The handoff page consumes a short-lived, one-time token and returns a
short-lived protected CDN URL for the current notarized DMG. It does not ask
the customer to create an account, supply an email address, or enter a license
key. A customer can return to the App Store edition and verify again when a
replacement download is needed; the claim service rate-limits reissues rather
than permanently rejecting a transaction after its first claim.

Updates ride Sparkle: the Direct app checks
`https://www.macheadroom.com/direct/appcast.xml`, whose entries are EdDSA-signed
by `Scripts/publish-direct.sh`. Update archives under `/direct/updates/` are
public through the CDN by design — Sparkle cannot present claim tokens, and
the doctrine above already treats gating as delivery control.

The Direct app has the separate bundle identifier
`com.vinnycarpenter.SystemHeadroom.Direct` and uses a signed Direct update
channel. Do not make the DMG a public, unguarded URL if purchase-only access is
intended. Download gating is a delivery control, not DRM: once downloaded, a
DMG can be copied.

The customer-facing DMG comes from `Scripts/release-direct.sh`, which requires
a Developer ID Application certificate and a `notarytool` keychain profile. It
is separate from the ordinary developer-signed `Scripts/build-direct.sh` build.

## Deployed verifier

`ClaimService/` is a separately deployed AWS SAM stack. It uses API Gateway,
Lambda, DynamoDB, and Secrets Manager, and stores only a keyed hash of the
transaction ID. The production stack is deployed with `ClaimFlowEnabled=false`;
its claim route returns `503` before parsing, logging, or transmitting a
customer app transaction. It remains disabled until all of the following are
true:

1. App Review has confirmed the customer-transfer model in writing.
2. One-time handoff consumption, rate-limited reissues, and protected Direct
   DMG delivery are implemented.
3. The customer eligibility/refund policy is published and operationalized.

The public health route is only a deployment probe. Neither endpoint belongs in
`DIRECT_EDITION_CLAIM_URL` until the preceding conditions are met.
