# UEVR profiles

Unpacked profile configurations and supporting source code. Importable ZIP packages, compiled plugins, runtime caches and logs are kept outside this repository.

## Star Wars Galactic Racer

`profiles/SWGR-Win64-Shipping/` contains the current profile snapshot tested on a Pico 4 using Virtual Desktop and OpenXR. The user confirmed satisfactory colors, menus, racing, cinematics and vehicle crash sequences with the automatic mono backend fix enabled.

The profile uses native stereo rendering, native stereo capture fix, OpenXR resolution scale 1.0, default tonemapper gamma, and no texture-array submission. Windows HDR must be disabled on all connected displays, including the TV. Restart the game after changing HDR. Connect Virtual Desktop before starting the game for audio routing.

### Backend dependency

The profile configuration alone does not fix one-eye cinematics. Build the `bivi` branch of [jonaslimads/UEVR](https://github.com/jonaslimads/UEVR/tree/bivi), install its backend, and place `SWGRFix-test.ini` **beside `UEVRBackend.dll` in the injector directory**. That file selects variant 4, the automatic mono fallback. It is included alongside the profile here for reproducibility; it is not a roaming profile setting.

The backend temporarily copies the primary scene to both eyes when its detector observes left-eye scene content and a black right-eye scene, then restores stereo when right-eye content returns. F9 is an optional manual mono force and starts OFF with each fresh game process. Test automatic behavior without pressing F9.

### Install the unpacked profile

Copy `config.txt`, `cameras.txt`, `cvars_data.txt` and `imgui.ini` into `%APPDATA%\UnrealVRMod\SWGR-Win64-Shipping` with the game closed. For ZIP import, package the profile files at the ZIP root and name the package `SWGR-Win64-Shipping.zip`; store generated packages outside this repository.

### Optional diagnostic plugin

The tested local profile also contained `plugins/SWGRCutsceneProbe.dll`, a diagnostic callback counter. Its source is preserved in `tools/cutscene-probe`; the binary is intentionally excluded. This plugin collects logs and does not change rendering or controls. The automatic mono fix is implemented in the backend, independent of this diagnostic plugin.

To reproduce the diagnostic plugin on Windows, configure its standalone CMake project with `UEVR_SOURCE_DIR` pointing to a UEVR source checkout containing `include/uevr/API.h`, build Release, and place the generated DLL in the profile's `plugins` directory.

This is a snapshot of the confirmed local setup, not a compatibility guarantee for other headsets, runtimes or game builds. The source profile files were copied from the active roaming configuration on October 11, 2026.
