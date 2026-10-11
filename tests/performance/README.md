# SWGR performance investigation

This directory tracks measurements, experimental UEVR builds, and repeatable tests. The confirmed profile in `profiles/SWGR-Win64-Shipping` remains the baseline. Experiments are not validated profiles.

## Constraints

- Keep Virtual Desktop Godlike, OpenXR resolution scale 1.0, and the 90 Hz target.
- Preserve automatic mono during cinematics and vehicle crashes and stereo recovery afterward.
- Change one variable at a time; do not publish experimental settings as confirmed improvements.
- Keep shader compilation, loading, injection, menus, cinematics, racing, and shutdown separate.
- Keep raw logs and compiled binaries outside this repository.

## Reports

- [October 11 baseline and investigation](reports/2026-10-11-swgr-baseline.md)
- [Experimental run 2: hot thread and diagnostic activation failure](reports/2026-10-11-experimental-run-2.md)
- [Diagnostic recovery and thread identification](reports/2026-10-11-diagnostic-recovery.md)
- [v2 Potato test: hot render thread with small measured UEVR waits](reports/2026-10-11-v2-potato.md)

## Next session

Use the finite-duration Windows collector with a raw-data directory outside this repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/performance/Collect-Performance.ps1 -OutputDirectory C:\VRMeasurements -Seconds 120 -Phase vr-racing -IncludeThreads
```

The collector records GPU samples, system-wide CPU counters, game-process aggregate CPU, optional per-thread counters, Windows-visible CPU topology, and a copy of the UEVR log. WMI permissions may require running it outside a managed sandbox or in an elevated terminal. It does not change game settings or install a backend. Save a separate capture for flat-screen comparison (`-Phase flat-screen`). Thread wait reasons are scheduler observations, not proof of a specific OpenXR wait.

When WMI is unavailable, add `-UseProcessCounters`. This uses cumulative process/thread CPU time deltas and records `process-cpu.csv` instead of system-wide `cpu.csv`. The first sample has no CPU percentage; subsequent thread percentages are relative to one logical processor and process percentages can exceed 100. It reports the logical processor count visible to .NET without inferring physical core count. Both modes record Windows thread descriptions and separate description errors; an empty description does not establish a thread's role. Exited threads may produce explicit counter errors. Names and IDs apply only to that process session. Per-thread collection still adds overhead.

The SWGRServerPerf-v2 bundle includes `UEVRServerPerformance.ini` beside its backend, enabling lightweight frame timings independently of profile persistence. Verify `[VR][timing-config] effective=true` and actual profiler summaries after injection. The original reset cause is still unresolved; configuration-load logs are intended to identify it.

1. Finish shader compilation before measuring. Use the same track, camera, weather and graphics preset for each run.
2. Record at least 60 seconds of actual racing and note its start/end times. Capture the Virtual Desktop overlay and GPU/CPU samples at the same time.
3. Record Game, Encoding, Networking, Decoding, FPS, codec, bitrate, SSW state, refresh rate and per-eye render extent.
4. Test the experimental UEVR build with `VR_FrameTimingDiagnostics=true`. Keep `VR_EnableHitchDiagnostics=false` initially. Save `[D3D12][frame-profiler]`, `[OpenXR][frame-profiler]`, `[UE57][engine-render-profiler]` and `[VR][server-performance]` lines.
5. Compare CPU wall times for engine render hooks, D3D12 submission, GPU fence waits, OpenXR frame/swapchain waits and post-present lock contention. These timers overlap; do not sum them as independent frame costs.
6. If the desktop spectator path is significant, repeat with Desktop Spectator View disabled, using the existing UEVR option. The TV mirror may disappear; headset resolution and refresh stay the same.
7. Test an alternative Sync Mode only after collecting the default Very Late timings. Restore Very Late after the test and check eye correctness, menus, cinematics and crash sequences.
8. Investigate worker-thread or queue changes only after identifying a measured blocking call and its resource ownership requirements.

## Run record template

| Item | Value |
| --- | --- |
| Date / time zone / racing interval | |
| UEVR branch / commit / DLL SHA256 | |
| Profile commit / experimental overrides | |
| Game settings / track / camera | |
| GPU driver / CPU topology visible to Windows | |
| Godlike / resolution / Hz / SSW / codec / bitrate | |
| FPS / Game / Encoding / Networking / Decoding | |
| GPU utilization / power / clocks / temperature | |
| CPU total / hottest logical processor / thread timings | |
| Backend timing summaries | |
| Eye correctness / cinematic and crash regression checks | |
| Result / limitations / rollback | |
