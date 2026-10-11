# SWGR baseline: October 11, 2026

## Finding

The observed VR run delivered approximately 27 engine ticks per second. Neither overall CPU utilization nor average GPU utilization demonstrates a continuously saturated device. A CPU main/render-thread limit, GPU work, and waits in the UEVR/OpenXR pipeline remain possible contributors. No performance improvement has been demonstrated yet.

The user reports essentially the same VR FPS from Low through Epic, with and without antialiasing and DLSS. Flat-screen 4K reaches approximately 70 FPS. These are user observations, not synchronized benchmark runs. They justify investigating CPU and frame pacing before reducing VR resolution.

## Setup

- GPU: NVIDIA RTX PRO 6000 Blackwell Max-Q Workstation Edition, 96 GB; reported power limit 300 W.
- CPU identification: AMD EPYC 7452 32-Core Processor. The user reports assigning half of the server CPU resources to gaming. The Windows performance provider exposed 16 logical processor counters (0-15) during capture; a subsequent `Win32_Processor` query reported 16 cores and 16 logical processors. The host/guest topology and allocation need verification; do not assume all 32 cores/64 threads are available to this Windows environment.
- Pico 4, Virtual Desktop, VDXR/OpenXR; Godlike, scale 1.0, target 90 Hz.
- Runtime recommended render size: 3264 x 3264 per eye, 21,307,392 pixels across both eyes. This differs from physical panel resolution.
- OpenXR predicted display period: 11,111,111 ns, consistent with 90 Hz.
- Native stereo, NativeStereoFix enabled, secondary pass preserved, texture-array submission disabled, Very Late synchronization.
- Installed confirmed backend: SWGRAutoMono-v3 / variant D. Its recorded SHA256 is `4CBE14AC227A1F49252994A66016D8C9D154C315D81309F52EAEABCD604473BD`.
- Baseline source: `bivi`, local commit `2033e17eb0e15bc8e3914e7f59b7bce1f23c2a4d`. Baseline profile commit: `84e319f20c78b28b7ad4ef6eaeac04e3636674f3`.

## Changes before capture

Only game settings were changed by the assistant, with full INI backups: `bIsVSyncEnabled=False`, then `bEnableHwrt=False`. The latest read also confirmed `bUseVSync=False`, `ResolutionScaling=100`, `FrameRateLimit=90`, and `Current3PAAUMode=Off`.

The user subsequently explored graphics options. The exact in-game graphics preset throughout the capture was not recorded. The installed backend and confirmed UEVR profile were not modified for this measurement.

## User-reported overlay before this capture

| Metric | Reading |
| --- | --- |
| Framerate / target | 29 FPS / 90 |
| Total latency | 65 ms |
| Game | 35 ms |
| Encoding / Networking / Decoding | 6 / 6 / 10 ms |
| Bitrate / maximum | 93 / 93 Mbps |
| Video buffering / automatic bitrate / Ethernet | Enabled / enabled / yes |
| SSW | Disabled, as reported before the test |

The Game field includes application-side timing; it is not a GPU-only measurement. Stage times are not independent contributions that can simply be added to reproduce total latency.

## Captured interval

Times are local, America/Sao_Paulo (UTC-03:00). Injection was observed around 13:30:10. The analysis window is **13:31:20-13:33:10**, chosen after injection/startup and before shutdown errors. Actual track entry/exit was not timestamped by the user; this is a post-injection observation window, not a certified uninterrupted racing benchmark.

| Metric | Average | Minimum | Maximum | Samples |
| --- | ---: | ---: | ---: | ---: |
| GPU utilization | 74.9% | 59% | 96% | 109 |
| GPU power | 243.4 W | 213.18 W | 279.73 W | 109 |
| Graphics clock | 2145.8 MHz | 2077 MHz | 2197 MHz | 109 |
| GPU temperature | 81.1 C | 76 C | 84 C | 109 |
| Windows total CPU utilization | 35.1% | Not calculated | 51% | 65 |
| Engine tick rate from diagnostic callbacks | 26.99/s | 25/s | 30/s | 109 |

The busiest logical processor by average was counter 12: 64.5% average, 93% peak, one of 65 samples at or above 90%. Counter 13 averaged 56.3%; counter 11 averaged 48.9%. These are system-wide per-processor counters, not per-thread timings. Thread migration and one-second sampling can hide a serial critical path.

GPU utilization varied enough to include near-full-load samples. Average headroom is not proof that GPU work is irrelevant. Rising temperature and decreasing clocks justify recording throttle reasons in the next run; no thermal throttling has been established from these readings.

The probe's tick rate is independent corroboration of a low application update rate, not an exact measurement of headset-presented FPS. The automatic mono detector switched during a cinematic and returned to stereo later in the capture.

## Source inspection and open hypotheses

1. `VR::on_post_present` holds `m_openvr_mtx` across post-present work and, with Very Late synchronization, a call to `synchronize_frame`. That call reaches `xrWaitFrame`. Measure both contention and wait time before moving it to a worker.
2. D3D12/OpenXR paths acquire and wait for swapchain images and retire GPU command contexts. Some waits protect resource reuse. Removing them without preserving fence and swapchain ownership can corrupt frames or crash.
3. NativeStereoFix renders a separate secondary-eye scene capture. CPU/render-thread work for the additional view can explain why flat-screen performance differs. Existing engine-render timers can help distinguish this cost from submission waits.
4. Desktop spectator copying/compositing is an optional extra path. The existing Desktop Spectator View option provides a controlled A/B test without lowering headset resolution.
5. The automatic mono detector polls completed fences and uses non-blocking `try_wait` in its normal sampling path, with a minimum 40 ms sample interval. The source does not show a normal-path CPU fence wait in the detector, but its GPU-copy cost still requires measurement.

The log contains frame-lifecycle recovery warnings during startup/transitions and pointer-resolution errors during shutdown. Their presence alone does not explain the sustained low racing FPS. Full backend frame timing was disabled, so this capture cannot attribute a specific number of milliseconds to any of the hypotheses above.

## Experimental direction

Backend branch: `swgr-server-performance`, based on the confirmed `bivi` commit. Profile/report branch: `swgr-performance-notes`, based on the initial published profile commit.

The first customization separates frame-timing diagnostics from heavyweight hitch snapshots and measures post-present lock contention. It changes observability, not OpenXR call ordering or the mono correction. A separate experimental build must pass compilation and existing mono regression tests before any installation. In-game correctness and performance validation remain pending because the user cannot test now.

### Prepared experiment: SWGRServerPerf-v1

- Source commit: `64b5ff06ff202418304d559496542354eaec2fb5` on `swgr-server-performance`.
- Release build completed successfully with Visual Studio BuildTools 2022, MSVC v143 and Windows SDK 10.0.26100.0. Existing dependency/generated-code warnings were emitted.
- All six existing automatic-mono/INI policy regression tests passed. These tests do not validate in-game frame timing or performance.
- Experimental DLL SHA256: `A9498B4DEA75B1C9F6A5E448099F6E19CA9C032B9780DC513E19DF7209CED199`.
- Local bundle: `uevr_cutscene_dev/builds/SWGRServerPerf-v1/`, including DLL/PDB, build/test logs, commit patch and metadata. Its `injector/` folder contains the existing injector/runtime dependencies plus the experimental backend, so the installed injector directory need not be overwritten.
- UI: Advanced mode, Debug page, **Server Performance Investigation**. Frame Timing Diagnostics defaults to off. The panel exposes existing mirror and synchronization controls; it does not change their defaults.
- The confirmed installed DLL hash was rechecked and remained unchanged.
- `tools/performance/Collect-Performance.ps1` passed PowerShell parsing and a five-second idle capture. Optional per-thread capture was separately exercised against PowerShell processes while the game was closed. This validates collection mechanics, not racing performance.

For the next test, close the normal injector and game, launch `UEVRInjector.exe` from the experimental bundle's `injector/` folder, then start/inject normally and enable Frame Timing Diagnostics in the UEVR menu. Do not change mirror or synchronization during the first run. The roaming profile is shared by both injector folders; any settings saved in the experimental menu also affect that profile. Back up `config.txt` before the test and restore it with the game closed afterward if reverting. Run the collector during a fixed racing interval.

The versioned confirmed profile and its ZIP have not been changed by preparing this experiment. The new build has not been injected or installed over the confirmed backend.

## Evidence and rollback

Raw local evidence is outside the profile repository, under workspace `uevr_cutscene_dev/performance-captures/`:

- `gpu-20261011-131804.csv`: GPU samples; earlier sections include shader compilation and idle periods and must be excluded from racing analysis.
- `cpu-injected-20261011-132924.csv`: system-wide CPU and aggregate game process counters after injection.
- `uevr-injected-20261011-1330.log`: saved UEVR log through game shutdown.
- `cpu-20261011-1318.csv`: earlier compilation capture; its aggregate game CPU field was serialized incorrectly as `System.Object[]`. Do not use that field for quantitative analysis.

Game INI backups are under `uevr_cutscene_dev/performance-backups/20261011-125355-874/` (before VSync change) and `20261011-130644-183/` (before HWRT change). Restore only with the game closed. The working installed backend remains the rollback reference; experimental builds are kept separately.
