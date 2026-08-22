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
