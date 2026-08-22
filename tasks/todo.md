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
