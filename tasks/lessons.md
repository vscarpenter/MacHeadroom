# Lessons from the 1.5.0 release work (October 26, 2026)

- `View` is `@MainActor` in the macOS 14+ SDK, so a `static func` on a
  SwiftUI view inherits main-actor isolation. A Swift Testing test that
  calls one from the cooperative pool trips `dispatch_assert_queue` and
  kills the whole test host, which shows up as every in-flight suite
  failing at once. Mark pure helpers on a view `nonisolated`.
- Adding fields to a struct that is built with the memberwise init: a
  `let` with a default drops out of the initializer, a `var` with a
  default becomes an optional parameter. `SystemSummary` used the second
  form so no call site changed.
- Measured inside the sandboxed test host on macOS 27: the App Sandbox
  allows `kern.memorystatus_vm_pressure_level` and `vm.swapusage`.
  `HostPressureLiveTests` re-proves it on every run.
- A store test that flips a preference which starts background sampling
  must stay synchronous on the main actor. Any `await` in the test lets
  the timer task take a real sample, and with a zero sustain that can
  deliver a real alert. Pass fixture inputs (groups, core count, clock)
  straight into the evaluation instead of waiting for a tick.
- Four `project.pbxproj` edits per new file still hold. Next free IDs
  after this release: UI `H…12`, Sampling `D…0C`, Grouping `F…07`,
  App `G…05`, tests `E…18`.
- A Direct smoke build from `Scripts/build-direct.sh` is Apple Development
  signed, and on this Mac that signing context gets header-only socket
  tables (SANDBOX_NOTES.md, Sept 16), so the Ports pane reads "No
  listening ports". It is not a regression. To test ports locally, copy
  the app and re-sign it with the Developer ID identity, then relaunch.
- The alert cooldown reused the list's group key, which is the pid for
  a bundle-less process. Fixture tests keyed by literal strings passed
  while a restarted `yes` alerted twice in 2 minutes 40 seconds. When a
  key is reused for a new purpose, test it through the real key builder
  with the real inputs (no bundle id, two pids, one name), not literals.
- A live check with the real tool is cheap and finds what fixtures skip.
  Notification Center's unified log counts deliveries without anyone
  watching for banners: `log show --predicate 'process == "usernoted"'`
  and grep `scheduled for delivery`; the request id carries our key
  (`cpu-alert-<key>`).
- `date` in this shell is GNU coreutils (`gdate`), so BSD flags such as
  `-v-4M` fail. Use `/bin/date` or `log show --last 5m`.
- A Developer ID re-signed copy of the sandboxed Debug app keeps its
  sandbox only with `--preserve-metadata=entitlements`. The termination
  gate reads the sandbox status at runtime, so a copy signed without it
  would offer Quit and prove nothing.
