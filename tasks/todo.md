# Resuming From Here (2026-08-01, evening)

## Done
- Fixed tab row cross-contamination: namespaced `PortGroup.id` ("port:" +
  groupKey) so it can't collide with `AppGroup.id` inside the shared
  LazyVStack row cache. Commit `33a0c46`, regression test in
  PortGroupBuilderTests. Suite green (85 tests / 21 suites).
- Confirmed Porcelain Native is already the default appearance (code path,
  "Porcelain Native defaults on" test, and Vinny's container prefs).
- Prepared and uploaded 1.0 (build 9) to App Store Connect for TestFlight:
  bumped Shared.xcconfig + AppIdentityTests together (commit `bf098a0`),
  full suite green, archived Release, exportArchive upload succeeded
  ("Uploaded SystemHeadroom"). Build 8 was never uploaded; 9 skips it.

## Next
- DONE: TestFlight build enabled, installed, and verified working by Vinny
  (Aug 1 late). The July 26 Apple-side install 500s are resolved.
- RESOLVED: the tested TestFlight build is 1.0 (10) = tonight's scripted
  upload, auto-renumbered from 9 by Xcode's manageAppVersionAndBuildNumber
  on collision with the 2:34 PM Organizer upload. Repo synced to 10
  (commit `227fc0d`, suite green, not yet pushed). Before the next
  release prep, check ASC for the real latest build number first.
- Refined App Store description (adds SEE WHAT'S LISTENING section) is in
  this session's scratchpad; paste into ASC alongside the build swap on
  the 1.0 version page.
- Pushed: `main` is in sync with origin (`6b1921d..bf098a0` — the tab-bleed
  fix `33a0c46` and the build 9 bump `bf098a0`).

## Blockers
- None.

## Assumptions
- Incrementing to build 9 (not re-using 8) was safe and matches "increment
  the build number"; duplicate numbers are rejected by ASC anyway.
