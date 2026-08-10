# Headroom Monitor App Review rename plan

1. Change the identity test to expect `Headroom Monitor` and confirm it fails
   against the current bundle metadata.
2. Update the shared display-name setting, Xcode product references/test host,
   scheme product references, Direct-build path, fallback identity, and the
   two hard-coded Quit labels.
3. Run the targeted identity test, full test suite, Release build, and bundle
   metadata/signing checks.
4. Commit only rename-related files, leaving unrelated preview and screenshot
   work untouched.
5. Build/archive from a clean worktree, upload build 11, and verify App Store
   Connect processing.
6. Change the App Store name and review notes, reply to the reviewer, and
   resubmit the corrected version.
