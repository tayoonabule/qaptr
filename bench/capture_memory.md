# U4 capture-cost prototype gate

## Decision

**Proceed with in-process, one-shot, pre-scaled ScreenCaptureKit capture.** The helper remains a native Swift `LSUIElement` process. It captures selected displays one at a time with `SCStreamConfiguration.queueDepth = 1` and requests the downscaled output size before ScreenCaptureKit returns an image.

This is a first-signal decision, not the final 12-hour release assertion. The measured margin is large, but the available machine has one built-in 3420 x 2214 ScreenCaptureKit source rather than the plan's 16 GB plus 5K reference configuration, and no second display was available.

## Prototype

- Target: `apps/helper`, Swift Package executable wrapped as an ad-hoc-signed `LSUIElement` app.
- Capture API: `SCScreenshotManager.captureImage(contentFilter:configuration:completionHandler:)`.
- Capture geometry: ScreenCaptureKit source geometry multiplied by `pointPixelScale`, fit within a 1920-pixel longest edge before capture.
- Capture order: first one selected display, then every initially selected display in ascending display-id order. Every display capture is awaited before the next starts.
- Buffering: `queueDepth = 1`.
- Selection behavior: display IDs are snapshotted at process start and intersected with currently available displays at each tick. A newly attached display is therefore not selected automatically; a detached selected display is omitted without invalidating the remaining selection.
- Failure bound: completion-handler operations time out after five seconds instead of leaving the helper suspended indefinitely.

## Measurement protocol

Command:

```sh
caffeinate -dimsu bash bench/scripts/capture_soak.sh \
  --hours 0.2 \
  --capture-interval-seconds 10 \
  --max-dimension 1920
```

The primary run used an accelerated 10-second interval to create more capture events than sparse production cadence. It ran for 600 seconds, with 554 `phys_footprint` samples spanning 599 seconds. `capture_soak.sh` enumerated the helper process tree once per second, ran `footprint --noCategories -f bytes` over that tree, summed each process's `phys_footprint`, and computed the median and peak across samples. It did not use RSS or `footprint`'s lifetime peak field.

The command was initially requested for 0.2 hours, but the execution host stopped it at its 600-second command ceiling. That still satisfies the requested 10-minute first-signal window. Because the host stopped the wrapper before its final print step, the same median and peak calculations were applied directly to the complete `footprint.csv` and `helper.log` artifacts.

## Reference machine for this run

- Model: MacBook Air (`Mac17,4`, `MDVU4B/A`)
- Chip: Apple M5, 10 cores
- Memory: 24 GB
- macOS: 27.0, build `26A5388g`
- Xcode: 26.6 (`17F113`)
- Swift: 6.3.3
- Displays: one built-in Liquid Retina display; ScreenCaptureKit source 3420 x 2214, requested output 1920 x 1243

This is not the plan's release reference configuration of 16 GB with one attached 5K display. No 5K/6K external or multi-display hardware was available.

## Results

| Metric | Result | U4 budget |
|---|---:|---:|
| Soak duration | 600 s process runtime; 599 s sampled window | First signal requested: 10 to 15 minutes |
| Footprint samples | 554 | Once per second, best effort |
| Median process-tree `phys_footprint` | **5.860 MiB** | < 50 MiB |
| Peak process-tree `phys_footprint` | **5.922 MiB** | < 50 MiB |
| Capture events | 118 across 59 ticks | Informational |
| Median per-capture latency | **57.712 ms** | < 400 ms capture tick |
| Peak per-capture latency | **137.781 ms** | Informational |
| Median single-display capture latency | **63.985 ms** | Informational |
| Median sequential selected-display capture latency | **43.709 ms** | Informational |
| Median complete tick latency | **177.390 ms** | < 400 ms |
| Peak complete tick latency | **299.904 ms** | Informational |
| Skipped ticks | **0** | 0 during ordinary soak |

The `multiple` case exercised the same sequential path used for several selected displays, but the machine had only one display, so it contained one display per round. Its median complete selected-display-set latency was 44.359 ms; the single-display set median was 64.287 ms.

A supplemental 60-second peak-stress run used a one-second capture interval. Across 56 footprint samples and 51 completed ticks, median footprint was 5.876 MiB, peak footprint was 5.969 MiB, median tick latency was 162.063 ms, peak tick latency was 253.967 ms, and no tick was skipped. This higher-duty-cycle pass did not reveal a hidden capture-time memory spike.

## Environment-change observations

| Scenario | Observation |
|---|---|
| Display attach/detach | Not physically exercised because no external display was available. The helper snapshots selected display IDs once and re-intersects them with the live `SCShareableContent` list each tick, so attachment cannot auto-select a new display and detachment leaves no stale `SCDisplay` object. Requires hardware verification on the release reference setup. |
| Sleep/wake | Physical system sleep was not exercised because it would interrupt the live development session. A non-disruptive `SIGSTOP`/`SIGCONT` proxy suspended the helper for eight seconds during a three-second cadence. It produced exactly one tick in the first second after resume, then returned to the normal cadence: one tick before suspension, two one second after resume, and four total. No catch-up burst occurred. |
| Lock | Not physically exercised because locking the live development machine would disrupt the session. At each tick the helper reads `CGSSessionScreenIsLocked` from the current CoreGraphics session and logs a skipped tick before any ScreenCaptureKit call. Requires real lock-state verification before U7. |
| Resolution change | Not exercised because changing the only built-in display would disrupt the active session and no non-disruptive secondary display was available. The helper rebuilds source and output geometry from a fresh content filter on every capture. Requires hardware verification before U7. |

## Rejected alternatives and risks

- **Short-lived capture child process:** rejected for U4 because the resident in-process helper measured far below the 50 MiB ceiling, and a child would add launch, TCC identity, signing, coordination, and failure-reporting cost at every tick. Reconsider if the required 12-hour 5K/6K run breaches either memory limit or reveals unrecoverable ScreenCaptureKit growth.
- **Persistent `SCStream`:** rejected because it keeps capture machinery resident between sparse ticks and does not test KTD1's one-shot premise.
- **Full-resolution capture followed by application-side scaling:** rejected because it gives up KTD2's bounded-peak property on 5K/6K frames.
- **Imported Swift async screenshot convenience:** an overlapping-process stress check on macOS 27 beta caused ScreenCaptureKit to leak its internal checked continuation. The spike therefore uses the completion-handler API with a five-second wait bound. Two simultaneous helpers fail closed with a timeout instead of hanging. Production U7 should enforce single-instance helper ownership.

**Confidence: medium.** The measured margin supports the in-process strategy, but release confidence remains gated on the full 12-hour run on 16 GB hardware with a real 5K/6K source and at least two displays, including physical attach/detach, sleep/wake, lock, and resolution-change exercises.
