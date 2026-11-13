# Lessons from the GPU and Drives tabs (November 13, 2026)

- Under the App Sandbox, reading an IORegistry property works and
  opening a user client does not. That one rule sorted every reading:
  GPU counters and disk byte counters are properties, SMART and IOReport
  are user clients. Check which kind a reading is before designing on it.
- Measure a sweep's cost before putting it on the tick. One innocent
  resource key, `volumeAvailableCapacityForImportantUsage`, took 11 ms a
  call while the other six took under 1 ms together. Time each read
  alone to find the slow one.
- Two counters with similar names can mean different things. `Alloc
  system memory` tracks what the GPU holds; `In use system memory` only
  rises while GPU work runs. A five-minute experiment (allocate, touch,
  blit, release) settled which one to show.
- The test host is not the shipping sandbox for file reads. The test
  action adds a temporary exception for read-only access to `/`. The
  October `/etc/hosts` live test passed under that exception. A probe
  signed with only the app-sandbox entitlement confirmed the read is
  allowed anyway (38 lines), so 1.5.0 is fine, but only the probe proved
  it.
- This shell cannot read the sandboxed test host's container, so the
  rendered PNGs there are out of reach. An unsandboxed test host writes
  them to the normal temp folder. CLAUDE.md has the command.
- `SingleInstanceGuard` uses one notice name for both editions and the
  test host. Every test run quits a copy of the app that was running.
- A new `PopoverTab` case breaks exhaustive switches in both skins, so
  Classic and Porcelain have to change in one commit.
- Swift 6 rejects a static stored `[String: Any]` fixture. Use a static
  function that builds it.
- `Mutex` needs macOS 15. On the macOS 14 target, a counting test
  closure uses `OSAllocatedUnfairLock`.
- A scratch script that inserts after the last same-prefix line made the
  four `project.pbxproj` edits safe to repeat. Next free IDs: Sampling
  `D…15`, Grouping `F…08`, UI `H…14`, tests `E…22`. Headers take a file
  reference and a group entry only.
- A delta needs a window with a floor and a ceiling. The first sample
  after the popover reopened divided by the whole closed period, and a
  refresh 3 ms after a tick gave one process 18.6% of an idle GPU. Both
  came from reusing the CPU's timestamp. The hardware deltas now keep
  their own baseline. CPU on `main` still averages across a pause.
- "Empty" and "not reported" are different states. A driver that
  publishes no per-app GPU time produced an empty ranking, and the pane
  called the GPU idle. Ask of every empty list what else could empty it.
- Mojibake in terminal output can be real. `HelpView.swift` held
  double-encoded bytes for three characters since `fa86c1a`, and Help
  showed "Ã" for "×". Check the bytes before blaming the terminal.
- An independent reviewer that builds its own harness finds what a
  self-review explains away. I had noted the pause averaging and called
  it inherited behavior.
- Mockups can carry another platform's vocabulary. The GPU mockup's
  rows came from NVIDIA telemetry, and five of seven had no source on a
  Mac. Check each drawn value for a source before estimating the build.

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
