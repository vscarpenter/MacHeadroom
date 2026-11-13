# GPU and Drives tabs

Status: approved by Vinny on November 13, 2026.

Vinny drew two mockups, `Gpu Headroom.png` and `Drive Headroom.png`, for
two new popover tabs in the Porcelain appearance. This design builds the
parts of those mockups that a Mac can report, and it replaces the parts
that came from PC graphics card telemetry.

## Intent

System Headroom answers one question: what is using my Mac right now,
and how much room is left. CPU and Memory answer it today. A GPU tab
answers it for graphics and local model work. A Drives tab answers it
for storage.

## Summary

Both tabs read IORegistry properties and Foundation volume values. A
sandboxed probe measured every reading before this design depended on
it (`Evidence/gpu-drives-spike/`, and the November 13 addendum in
`SANDBOX_NOTES.md`). Nothing here needs a new entitlement, a network
call, or a dependency.

The GPU tab shows utilization, GPU memory, and a ranking of the apps
using the GPU. The mockup had no ranking. The probe found per-process
GPU time readable under the sandbox, and a ranking is the same answer
the CPU and Memory tabs give.

The Drives tab shows one row per drive with a capacity bar, plus disk
activity. The unsandboxed Direct edition adds SSD health and drive
temperature, because the sandbox denies the SMART read itself.

The tab bar grows from three tabs to five. Ports stays.

## Goals

- GPU headroom as a headline number, from device utilization.
- The top 10 apps by GPU time, grouped like every other tab.
- GPU memory, labeled for what the counter measures.
- Drive headroom as a headline number, from the startup volume.
- Every local physical volume with used and free space.
- Read and write throughput per physical disk.
- SSD wear, SMART warnings, and temperature in the Direct edition.
- Both tabs in both appearances, Classic and Porcelain.

## Non-goals

- Clock speeds and power draw. They need the private IOReport
  framework, and the sandbox denies it.
- GPU temperature. No sensor on the measured chip is labeled GPU.
- Encoder, decoder, and optical-flow utilization. macOS exposes none.
- PCIe throughput. Apple silicon has no PCIe graphics card.
- Largest folder. The sandbox denies the home folder, and a crawl is a
  different product.
- Per-app disk activity. `proc_pid_rusage` is denied under the sandbox.
- GPU alerts and a GPU figure in the menu bar.

## Anti-goals

- A row that shows a guessed or stale number. A missing reading shows
  an unavailable state.
- A popover whose height depends on what a tab holds.
- Drive health UI in the Mac App Store build.

## Approaches

Three decisions shaped the build. Vinny picked the first option each
time.

Scope. Option 1 builds the measured set in both editions and adds drive
health to Direct. Option 2 builds the measured set with identical
editions, which is less code but leaves a public SMART interface
unused. Option 3 adds GPU power to Direct through private IOReport,
which is closer to the mockup and can break on any macOS update.

Tab bar. Option 1 keeps Ports as a fifth tab and gives Porcelain a
full-width tab row. Option 2 keeps five tabs in the current 240 point
control with "Mem" and "Disk" labels, which no longer match the header
titles. Option 3 matches the mockup's four tabs and removes Ports.

Volume display. Option 1 draws one row per volume with a capacity bar.
Option 2 keeps the mockup's side-by-side pie cards, which need two
volumes to look right and do not fit the 340 point Classic appearance.
Option 3 puts a small ring in each row's icon slot.

## Constraints carried from CLAUDE.md

- Popover intrinsic height is independent of content. The header and
  list keep fixed heights, and `PopoverLayoutTests` pins every new tab
  and state.
- Sandbox reads are measured before UI depends on them. Live tests
  re-prove each open read inside the sandboxed test host.
- Capability-gated features follow `TerminationCapability`: the answer
  comes from the app's own sandbox entitlement at runtime. Sparkle
  stays the only compile-time fork.
- New source files need four `project.pbxproj` edits each.
- The standard appearance stays free of character imagery.

## Part 1: five tabs

`PopoverTab` gains `gpu` and `drives`. Order: CPU, Memory, GPU, Drives,
Ports. `metricKind` stays nil for the three non-ranking tabs.

Classic keeps its segmented picker with five segments.

Porcelain moves the tab bar out of the header's right column. The
header becomes: accent capsule, then the headline block with the memory
pressure badge trailing the title row, then the tab bar at the full
content width. The header's fixed height grows from 172 to 222 points.
The list keeps 468 points, so the popover is 50 points taller and each
tab shows as many rows as today.

## Part 2: GPU tab

### Data

`GPUSampler` matches `IOAccelerator` services and reads
`PerformanceStatistics`, `model`, and `gpu-core-count` from the first
one that reports `Device Utilization %`. It then reads
`IOUserClientCreator` and `AppUsage` from each child client.

`GPUStatsParser` is pure. It takes the property dictionaries and returns
a `GPUReading`: utilization percents, the two memory counters, and
accumulated GPU nanoseconds summed per pid. A creator string that does
not parse, or a client with no `AppUsage`, is skipped.

`SamplerService` owns the previous reading and the clock. A process's
GPU percent is its counter delta divided by wall time, times 100. The
first tick has no delta, so percents are absent. A counter that moves
backward (a client closed) yields no percent for that tick. When both
ticks have a process snapshot for the pid, their start identities must
match, which guards against pid reuse.

`GPUUsageBuilder` in `Grouping/` folds per-pid percents onto the app
groups the popover already has, the way `PortGroupBuilder` folds ports.
A pid outside the same-user process table (WindowServer, for one)
becomes a system row named from the registry string. The builder drops
rows under 0.05%, sorts by percent then name, and keeps 10.

### Display

Header: "GPU headroom", then 100 minus device utilization. Detail line:
"27% in use · 5.2 GB GPU memory".

List, top to bottom:

1. GPU Utilization. Value is the device percent. Subtitle is
   "Renderer 27% · Tiler 12%". The bar is the device percent.
2. GPU Memory. Value is `Alloc system memory`. Subtitle is
   "1.9 GB in active use", from `In use system memory`. The bar is
   allocated memory as a share of installed memory. The memory
   experiment in the evidence folder is why allocated leads.
3. A "Top GPU apps" label, then the ranking. Each row has the app icon,
   name, percent, and a bar scaled to the top row. System rows carry a
   "system" tag and a gear icon. App rows offer Quit in the Direct
   edition through the existing affordance.

States. No accelerator or no utilization key: the header shows a dash
and the list shows "GPU statistics unavailable". First tick: the two
stat rows render and the ranking shows the waiting state. No app above
the floor: "No GPU activity".

## Part 3: Drives tab

### Data

`VolumeSampler` lists mounted volumes with `skipHiddenVolumes` and reads
name, total, available, important-usage available, local, and format.
For each volume it finds the `IOMedia` by BSD name and walks parents to
the `IOBlockStorageDriver`. That walk yields the physical disk name,
the interconnect, the location, the medium, and the driver's byte
counters.

`VolumeClassifier` is pure. It keeps a volume when it is local, has a
physical disk, and its interconnect is not `Virtual Interface`. That
drops network mounts and disk images. The startup volume always stays.
Free space is the important-usage figure when it is above zero, else
plain available capacity. The important-usage figure is what Finder
shows, and it reads zero off the startup volume.

`SamplerService` keeps the previous byte counters per physical disk.
Throughput is the delta divided by wall time. The first tick, a new
disk, and a counter that moves backward yield no reading.

`DriveHealthSampler` reads NVMe SMART data through a small C function
in `NVMeSMARTBridge.h`, over every service that reports
`NVMe SMART Capable`. `DriveHealthCapability` mirrors
`TerminationCapability`: unavailable when the app is sandboxed. The
sandboxed app never attempts the read, so it logs no denials.
`SamplerService` refreshes health at most once every 60 seconds.

### Display

Header: "Drive headroom", then free space as a percent of the startup
volume. Detail line: "815.05 GB in use · 994.66 GB internal". Drive
sizes use decimal units to match Finder.

List, top to bottom:

1. One row per kept volume, startup first, then by name. Value is
   "179.61 GB free". Subtitle is the kind line: "Internal SSD · 994.66
   GB · APFS", or "External HDD · 8 TB · USB" off the internal bus. The
   bar is the used share.
2. One Disk Activity row per physical disk. Value is
   "R 0.2 · W 51.0 MB/s". Subtitle names the volumes on that disk.
3. Direct edition only, per SMART device: an SSD Health row ("Healthy"
   or "Check drive", subtitle "No warnings · 3% wear", bar is wear) and
   a Drive Temperature row in the user's temperature unit.

Every bar in both tabs means the same thing: the share that is used.

States. No readable volume: the header shows a dash and the list shows
"Drives unavailable". First tick: activity shows dashes. Sandboxed
build: no health rows, and Help says why.

## Wiring

New files:

- `Sampling/IORegistry.swift`: property and iteration helpers.
- `Sampling/GPUStatsParser.swift`: `GPUReading`, the parser, `GPUDelta`.
- `Sampling/GPUSampler.swift`: the registry reads.
- `Sampling/VolumeSampler.swift`: `VolumeSnapshot`, `VolumeClassifier`,
  the volume and registry reads.
- `Sampling/DiskActivity.swift`: counters, the delta, `DiskActivity`.
- `Sampling/DriveHealthSampler.swift`: `DriveHealth`, the capability,
  the SMART read.
- `Sampling/NVMeSMARTBridge.h` and `Sampling/BridgingHeader.h`. The
  bridging header setting moves from `PortTableABI.h` to
  `BridgingHeader.h`, which includes both. The pcblist layouts do not
  move.
- `Grouping/GPUAppUsage.swift`: the row model and `GPUUsageBuilder`.
- `UI/StatRow.swift`: the row model and the pure builders that turn
  store state into rows and header text.
- `UI/HardwarePaneViews.swift`: the Classic rows and panes.

Changed files: `MonitorTick`, `SamplerService`, `MonitorStore`,
`PopoverTab`, `PopoverView`, `MaxHeadroomPopoverView`,
`ValueFormatting`, `PreviewFixtures`, `HelpView`, `Shared.xcconfig`,
the project file, `README.md`, `CLAUDE.md`.

`MonitorTick` gains `gpu`, `volumes`, `diskActivity`, and
`driveHealth`. `MonitorStore` publishes `gpuSummary`, `topGPUApps`, and
`driveSummary`. Hardware sampling rides every tick, like ports do.

## Tests

- Parser fixtures: a full reading, missing keys, a malformed creator
  string, several clients for one pid.
- Delta fixtures: priming tick, normal delta, backward counter, zero
  wall time, identity mismatch.
- Builder fixtures: folding onto groups, system rows, the floor, tie
  ordering, the limit.
- Classifier fixtures: disk image, network mount, startup volume,
  important-usage fallback, kind lines.
- Disk activity fixtures: priming, delta, backward counter.
- Presentation fixtures: every row's strings and ratios, drive health
  wording, temperature by locale, throughput formatting.
- Live, inside the sandboxed host: the GPU read returns utilization and
  clients, the volume read returns the startup volume with a physical
  disk and counters, a tick carries all of it, and drive health is
  unavailable and empty.
- Layout: both new tabs, both appearances, populated, empty, and
  unavailable, all equal to the CPU tab's height. Health rows present
  and absent change nothing.
- Visual: both tabs render in light and dark.

## Help

The "Start here" step names five tabs. "Read the signal" gains a GPU
fact and a Drives fact. The Drives fact says which edition shows SSD
health and why.

## Branch and version

Branch `feat/gpu-drives-tabs` from `main`. The version stays 1.5.0 (17)
until Vinny names the release.

## Manual check (Vinny)

This Mac allows no screenshots, so the last look is Vinny's.

1. Porcelain: five tabs fit on one row and the header reads cleanly.
2. Classic: five segments fit at 340 points.
3. GPU: run a GPU-heavy app and confirm it tops the ranking.
4. Drives: free space matches Finder's Get Info for the startup volume.
5. Direct build: SSD Health and Drive Temperature appear. App Store
   build: they do not.

## Out of scope

Everything under Non-goals, plus Intel Mac verification. An Intel Mac
may report different keys. The tabs degrade to the unavailable state
there until someone measures one.
