# Phase 0 evidence provenance

The two JSON reports in this directory were generated on July 24, 2026 from
probe source commit `44ab12713a5f4a3fc1303cc82452176e5d80e953`.
There were no tracked source or configuration changes between that commit,
the build, and the two runs.

## Signed sandbox build

The local Apple Development team was resolved from the signing certificate
rather than stored in the project:

```sh
TASK_TEAM_ID=$(
  security find-certificate -c 'Apple Development: Vinny Carpenter' -p |
    openssl x509 -noout -subject -nameopt RFC2253 |
    sed -n 's/.*OU=\([^,]*\).*/\1/p'
)

xcodebuild \
  -project MacHeadroom.xcodeproj \
  -scheme MacHeadroom \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData \
  DEVELOPMENT_TEAM="$TASK_TEAM_ID" \
  CODE_SIGN_IDENTITY='Apple Development' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  clean build
```

The build completed successfully. Its unfiltered log contained no `warning:`
or `error:` lines.

Built product:

```text
DerivedData/Build/Products/Release/Mac Headroom.app
```

Sandboxed executable and signature:

```text
SHA-256: 51cabd87439b548b77e0d65495fd7bb68c027d738f2ce67ed411a61929d27684
CDHash: b46a891151afe01a04e87b011226453b0f3560dc
Identifier: com.vinnycarpenter.MacHeadroom
Signing class: Apple Development
CodeDirectory flags: 0x10000(runtime)
Runtime version: 26.5.0
Entitlements: {"com.apple.security.app-sandbox":true}
```

The sandbox report was captured by executing:

```sh
'DerivedData/Build/Products/Release/Mac Headroom.app/Contents/MacOS/Mac Headroom' \
  --phase-zero-probe
```

## Unsandboxed control

A temporary byte-for-byte copy of the signed Release app was made with
`ditto`. Before re-signing, its executable SHA-256 matched the sandboxed
executable:

```text
51cabd87439b548b77e0d65495fd7bb68c027d738f2ce67ed411a61929d27684
```

The copy was re-signed with the same Apple Development signing class, hardened
runtime, no timestamp, and no entitlements file:

```sh
codesign \
  --force \
  --sign 'Apple Development' \
  --options runtime \
  --timestamp=none \
  '/tmp/<control-directory>/Mac Headroom.app'
```

Control executable and signature at the evidence run:

```text
SHA-256: e2eff1fb06d678cd92b1a87d96b937c9896e17df0d5186a46d43dd8983a1e11c
Identifier: com.vinnycarpenter.MacHeadroom
Signing class: Apple Development
CodeDirectory flags: 0x10000(runtime)
Runtime version: 26.5.0
Entitlement payload bytes: 0
```

The control report was captured with the same `--phase-zero-probe` argument.
The temporary control app was moved to Trash after its report and signature
state were recorded.

## Report integrity

```text
ef6994e275807f7009f23916bcf57746a3fa59aa2357e7dd29cbc23ef3bdbe24  phase-zero-sandbox-report.json
040aa6d5fa1bab5add74abbb9a42361249d79e8f9d7d7def2970905f28a091a3  phase-zero-unsandboxed-report.json
```

The JSON files are the unchanged stdout payloads from their respective runs.

## Verification gates

All gates used the same probe source commit:

```text
Release arm64 clean build: passed, no warning or error diagnostics
Debug arm64 clean build: passed, no warning or error diagnostics
Release x86_64 clean build: passed, no warning or error diagnostics
Release arm64 static analysis: passed, no warning or error diagnostics
Swift format lint: passed
Signed app verification: passed
JSON parse and accounting invariants: passed
```
