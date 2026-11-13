# GPU and drive readings sandbox spike: raw results

Date: November 13, 2026. macOS 27.2.1 (26B131), Apple M4 Pro, 48 GB.
Probe: `probe.m` in this directory, compiled once with
`clang -fobjc-arc -framework Foundation -framework IOKit -framework Metal -framework CoreGraphics`
and wrapped in three app bundles:

- Control: Developer ID Application, hardened runtime, no entitlements.
  Transcript: `out-control.txt`.
- Sandboxed, Developer ID Application, `com.apple.security.app-sandbox`
  only (`sandbox.entitlements`). Transcript: `out-sandbox-devid.txt`.
- Sandboxed, Apple Development, same entitlement.
  Transcript: `out-sandbox-appledev.txt`.

Each bundle ran by direct execution of its executable. Two volume names
in the transcripts are redacted (`EXTERNAL-BACKUP`, `MountedImage`).

Sandbox-active proof in both sandboxed runs: `APP_SANDBOX_CONTAINER_ID`
was set, `NSHomeDirectory()` pointed into `~/Library/Containers/`, and
the real home folder listing failed. The two sandboxed runs agreed on
every line, so the September 16 signing-context difference seen with
the socket tables does not appear here.

## Matrix

| Reading | Source | Control | Sandboxed |
| --- | --- | --- | --- |
| GPU utilization (device, renderer, tiler) | `IOAccelerator` property `PerformanceStatistics` | readable | **readable** |
| GPU memory (`Alloc system memory`, `In use system memory`) | same property | readable | **readable** |
| GPU model and core count | `IOAccelerator` properties `model`, `gpu-core-count` | readable | **readable** |
| Per-process GPU time | child `AGXDeviceUserClient` properties `IOUserClientCreator` and `AppUsage` | 118 of 118 clients | **118 of 118 clients** |
| Metal memory budget | `MTLDevice.recommendedMaxWorkingSetSize` | 40,200,896,512 | same |
| Volume capacity, flags, format | `FileManager.mountedVolumeURLs` resource values | 4 volumes | **4 volumes, same values** |
| Volume to physical disk, interconnect, medium | `IOBSDNameMatching`, then parents to `IOBlockStorageDriver` | found for 3 local volumes | **same** |
| Disk byte counters | `IOBlockStorageDriver` property `Statistics` | 12 of 12 drivers | **12 of 12 drivers** |
| Disk activity delta | two samples around a 48 MB write | 52,953,088 bytes written | **51,314,688 bytes written** |
| NVMe SMART (wear, spare, temperature) | `IONVMeSMARTInterface` from `NVMeSMARTLibExternal.h` | 3% used, spare 100%, 311 K | **denied**, `kr=0xe00002be` |
| Home folder listing | `contentsOfDirectory` on the real home and `~/Movies` | 321 and 4 items | **denied** |
| GPU energy | private `libIOReport.dylib` | 2,186,720 nJ over 1 s | **denied**, subscription NULL |
| Temperature sensors | private `IOHIDEventSystemClient` calls | 70 sensors | 70 sensors |

The kernel logged the three denials for the sandboxed process:

```text
deny(1) iokit-open-user-client AppleNVMeSMARTUserClient
deny(1) iokit-open-user-client IOReportUserClient
deny(1) file-read-data /Users/<user>/Movies
```

## What the readings mean

`accumulatedGPUTime` is a monotonic nanosecond counter per client. Two
probe runs 13.65 seconds apart saw WindowServer's largest entry advance
by 187,564,500 ns, which is 1.4% of that wall time. The device reported
2% utilization in both runs. A per-process GPU percent is the counter
delta divided by wall time, the same shape as the CPU delta.

`IOUserClientCreator` reads `pid 653, WindowServer`. The registry is not
filtered by user, so root and other-user GPU clients are visible. The
process table is same-user only, so those rows need the name from this
string.

`gpumem.swift` (transcript `out-gpumem.txt`) allocated eight 256 MB
shared Metal buffers, wrote them, ran a GPU blit over them, added four
256 MB private buffers, and released everything.

| Step | In use system memory | Alloc system memory |
| --- | --- | --- |
| Allocate 2,048 MB shared | +267 MB | +1,992 MB |
| Write every page | +122 MB | +1,984 MB |
| GPU blit over every buffer | +2,049 MB | +1,938 MB |
| Add 1,024 MB private | +1 MB | +2,937 MB |

`Alloc system memory` tracks what GPU clients hold. `In use system
memory` tracks what in-flight GPU work references, and it falls back
when the work ends. The app shows allocated as GPU memory and treats in
use as a secondary detail.

`volumeAvailableCapacityForImportantUsage` returned 179.6 GB on the
startup volume, where plain available capacity was 140.1 GB. It returned
0 on the external volume, the disk image, and the NFS mount. Finder's
"available" figure is the important-usage value.

The volume list held a mounted disk image (interconnect
`Virtual Interface`) and an NFS mount (`volumeIsLocal` false, no
`IOMedia`). The roughly 30 Time Machine snapshot mounts that `df` lists
did not appear with `skipHiddenVolumes`.

The probe printed only sensors named GPU, NAND, SSD, or `PMU tdie`. It
found `PMU tdie` die sensors and one `NAND CH0 temp`. No sensor on this
chip carries "GPU" in its name.

## Conclusion

On macOS 27.2.1, an App Sandbox app with System Headroom's entitlement
set can read GPU utilization, GPU memory, per-process GPU time, volume
capacity, the physical disk behind each volume, and disk byte counters.
All of it comes from IORegistry properties and Foundation volume values,
with no user client and no new entitlement.

The same app cannot open a user client. That closes NVMe SMART and
IOReport, and the sandbox also closes the home folder. Drive health and
temperature are therefore capability-gated to the unsandboxed Direct
edition, the same rule as process termination.

Not measured: Intel Macs, and macOS 14 through 26. The property names
are undocumented, so every reading must degrade to an unavailable state.
