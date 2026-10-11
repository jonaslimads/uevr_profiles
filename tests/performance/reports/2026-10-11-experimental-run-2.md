# Experimental run 2: SWGRServerPerf-v1

## Outcome

External measurements captured part of the user's session despite delayed approval for capture renewal. A hot game-process thread is now visible: thread 18068 averaged 90% of one logical processor during the selected stable interval. This supports investigating a serial CPU critical path, but does not identify the thread's role or attribute its work to the game versus injected UEVR code. GPU load was also substantial.

The intended internal frame profiler was not active. Although activation had verified `VR_FrameTimingDiagnostics=true` on disk before this session, the active profile was later saved with `VR_FrameTimingDiagnostics=false`. No internal timing summary lines were found. The cause of the reset is unresolved; file verification alone was insufficient to validate runtime activation.

## Build and timeline

- Installed DLL: SWGRServerPerf-v1, SHA256 `A9498B4DEA75B1C9F6A5E448099F6E19CA9C032B9780DC513E19DF7209CED199`.
- Startup log identifies branch `swgr-server-performance`.
- Local times: America/Sao_Paulo, UTC-03:00.
- First finite capture started at 14:48:17, including idle/startup, and ended around 14:58:19.
- Injection startup appeared around 14:56:19. Native stereo activation and a scene transition appeared in the following minute.
- At 14:57:43-44, scene-capture generation changed and the probe update rate briefly dropped. This transition is excluded from the stable analysis window below.
- Last gameplay probe lines were at approximately 14:59:37; shutdown-related pointer-resolution errors followed.
- Capture renewal started at 14:59:54, after gameplay ended. External CPU/GPU data for the tail between the first capture's end and game shutdown is missing. The saved UEVR log covers that tail.

## Stable recorded window: 14:57:48-14:58:15

| Metric | Average | Minimum | Maximum | Samples |
| --- | ---: | ---: | ---: | ---: |
| GPU utilization | 84.43% | 78% | 98% | 7 |
| Hottest game thread CPU, TID 18068 | 90% | 86% | 95% | 7 |
| Engine update rate from probe | 27.88/s | 24.61/s | 29.56/s | 28 |

Thread PID was 20872. The next busiest threads across the broader 14:57:40-14:58:15 window averaged approximately 36%, 33%, 31% and 30% of one logical processor. This is not a fully saturated multicore workload, but aggregate core utilization alone obscures the much hotter individual thread.

CPU/thread collection increased the sample interval to approximately four seconds. This short window and sparse sampling limit confidence and may miss brief stalls. The collector's overhead was not benchmarked; future runs should compare collection with and without per-thread WMI queries. Probe update rate is not the same as headset-presented FPS.

## Interpretation

1. The user observation that graphics presets and DLSS did not materially change VR FPS is consistent with a serial CPU limit, but is not enough to prove it.
2. Per-thread CPU data provides stronger evidence than the previous system-wide counters: a particular thread is repeatedly close to one logical processor's capacity. Its thread name and call stacks were not collected, so it cannot yet be called the game thread, render thread, or UEVR submission thread.
3. GPU utilization reaches 98% in this window. GPU workload is relevant and must not be dismissed solely because its average is below 100%.
4. The scene-generation transition coincides with a brief update-rate drop; this does not demonstrate that the transition mechanism causes the sustained 28/s rate after it.
5. No measured internal frame timings exist for this run. Removing locks or moving OpenXR work to another thread remains premature.

## Required follow-up

- Resolve why the diagnostic option was reset; verify actual runtime profiler lines after injection, not just the saved profile value.
- Preserve the existing raw session before starting another test.
- Attribute the hot thread using thread descriptions or sampled call stacks, then determine which portion of its CPU time belongs to engine rendering, scene capture, injected hooks or other work.
- Keep resolution, refresh and rendering correctness unchanged while making one measured optimization at a time.

## Local evidence

Under workspace `uevr_cutscene_dev/performance-captures/20261011-144817-738-vr-racing/`: `gpu.csv`, `cpu.csv`, `threads.csv`, `run.json`, `gpu-info.csv`, `uevr.log`, and `uevr-after-run.log`. The later folder `20261011-145954-280-vr-racing/` contains post-game measurements and must not be presented as a racing benchmark. Both collectors have been stopped/completed.
