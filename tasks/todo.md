# Direct-edition purchaser download + Help enhancement (2026-08-22)

Design APPROVED by Vinny (single gate passed). Continuous pass: spec -> plan -> implement.

- [x] Explore existing Direct infrastructure (workflow: map-direct-edition-state)
- [x] Clarifying questions (6 decisions locked, see spec "Decisions")
- [x] Present design; approved verbatim ("approved - lets build")
- [~] Write + commit design doc docs/superpowers/specs/2026-08-22-direct-download-design.md
- [ ] Spec self-review (inline fixes)
- [ ] writing-plans skill -> implementation plan
- [ ] Implement: ClaimService reissue + handoff + template.yaml (TDD, node --test)
- [ ] Implement: claim web page + site wiring (token/state logic tested)
- [ ] Implement: Sparkle vendoring, Direct.xcconfig, updater seam, script assertions
- [ ] Implement: publish-direct.sh; Help screen enhancements + tests
- [ ] Deploy dark to AWS (confirm each mutating step); smoke test
- [ ] Full suite green; runbook delivered; Vinny eyeballs Help UI

## AWS inventory (2026-08-22, read-only)
- Account 710603110067 (user codestar), region us-east-1
- Stack system-headroom-direct-claims: CREATE_COMPLETE Aug 13, dark
  (ClaimFlowEnabled=false, ClaimHandoffBaseUrl blank); API f3835sp1s0
- Site: s3://macheadroom.com (landing page live, uploaded Aug 21) behind
  CloudFront E1CMGVHA0HQHJK (OAC EP4K8MIMS24OK, root index.html,
  403/404 -> /404.html, no extra behaviors, no functions)
