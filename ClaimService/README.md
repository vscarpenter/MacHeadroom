# System Headroom Direct claim verifier

This is the AWS SAM verifier for a potential App Store-purchase transfer to
System Headroom Direct. It is intentionally deployed with the claim flow off.

## What is deployed

- API Gateway REST API with a low per-method throttle.
- A health Lambda and a claim-verifier Lambda with reserved concurrency.
- Encrypted, point-in-time-recoverable DynamoDB storage of keyed transaction
  hashes only; the raw App Store transaction ID is never logged or stored.
- A generated HMAC secret and a separate Secrets Manager secret for Apple's
  In-App Purchase private key.

The verifier uses Apple's App Store Server Node library to call **Get App
Transaction Info** and verify the resulting signed app transaction when, and
only when, the claim feature flag is explicitly enabled.

## Safe deployment state

The deployed stack must retain these settings until App Review confirms the
flow and protected delivery exists:

```text
ClaimFlowEnabled=false
ClaimHandoffBaseUrl=(empty)
```

With those settings, `POST /v1/claims` returns `503` without parsing the body
or calling Apple. `GET /health` reports `claimFlowEnabled: false` for a live
deployment check.

## Local verification

```bash
npm install
npm run check
npm test
sam validate --lint --template-file template.yaml
```

Current SAM releases pass `--unsafe-perm` to npm. If the local npm version
rejects that flag, install npm 10 in the ignored local helper directory and
place it first on `PATH` for `sam build`:

```bash
npm install --prefix .sam-tools npm@10
PATH="$PWD/.sam-tools/node_modules/.bin:$PATH" sam build --template-file template.yaml
```

Do not put the Apple `.p8` key in this directory, in source control, or in a
Lambda environment variable. Store it only in Secrets Manager and pass the
secret ARN as `AppStorePrivateKeySecretArn` at deployment.
