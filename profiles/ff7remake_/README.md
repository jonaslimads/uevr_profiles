# FINAL FANTASY VII REMAKE INTERGRADE — Pico 4

Experimental third-person profile for the `ff7-pico4-cutscene-fix` backend branch. Not yet validated in the headset. Preserve the original game camera and temporal antialiasing, use full UEVR resolution, remove motion blur and depth of field, and apply mild sharpening without changing gamma. This is a clarity baseline, not a claim of matching another game's rendering or reaching 90 FPS.

## Required setup

Use **DX11**, game launch option `-d3d11`, and **Windowed** mode. The [original plugin](https://github.com/praydog/FF7R-UEVR/tree/d5815b0d9491ba2f1c2f9596fd02fbb89755ec21) explicitly requires these because DX12 has issues and crashes. The last local DX12 attempt crashed; its cause has not been established.

Use OpenXR with Virtual Desktop's VDXR runtime. Start with the preferred Godlike quality and 100% UEVR resolution. Keep native stereo enabled (`VR_RenderingMethod=0`) and Native Stereo Fix, texture-array submission, AFR and 2D screen mode disabled. The original plugin owns the FF7 UI and lighting fixes; retain it. Do not substitute the Star Wars profile.

For the first comparison, select High textures and High shadows in the game, and keep the same scene and Virtual Desktop preset. This profile does not rewrite game settings or install FFVIIHook. An in-game internal scaler may still override screen percentage; confirm sharpness and GPU load in the actual scene.

## Automatic cutscene fallback

The paired backend samples 36 interior scene pixels per eye asynchronously, before UI composition, at most every 40 ms. Two samples with a lit left eye and black right eye duplicate the left scene into both halves of the OpenXR color image and suppress scene depth for those frames. Two lit right-eye samples restore native stereo; prolonged darkness or expired evidence also releases fallback. It does not make a mono video stereoscopic or repair arbitrary cutscene rendering failures.

Only `ff7remake_.exe`, DX11, OpenXR and a validated double-wide 8-bit scene target are supported. GPU readback never waits or flushes. Unsupported formats and layouts retain normal rendering. A dark scene can resemble missing-eye rendering; test fades and dark gameplay. Logs contain `[FF7][auto-mono][D3D11]` on transitions.

## Pico 4 controls

Use the normal OpenXR controller bindings. A/B on the right and X/Y on the left retain their gamepad labels. Left stick moves, right stick controls the game's camera; triggers send LT/RT and grips send LB/RB. These emulate the game's controller, including its own combat and shortcut settings.

**Hold left stick click, then move the right stick** for D-pad directions (party selection and menus). Release left stick click to restore the camera stick. This avoids relying on thumbrest touch detection; it consumes L3 while shifting. Click both sticks together to open the UEVR menu, which has priority over shifting. Camera-relative aim is retained; this does not implement sword motion attacks or first-person hand tracking.

## Package and provenance

`upstream/config.txt` and `upstream/revision.txt` preserve the text from the downloaded ZIP. `upstream-manifest.json` records its revision and hashes. The original plugin binary and PDB are kept in the local extracted archive, not committed to this repository. Build a runtime ZIP using `tools/ff7/Build-Profile.ps1`, supplying the original archive; it verifies the archive and plugin before packaging. The ZIP includes the original DLL and revised settings, excludes the large original PDB, and can be imported through UEVR with the game closed.

## Headset validation still required

1. Verify DX11 and plugin initialization in the startup log.
2. Check menus, subtitles, lights/shadows and HUD placement in both eyes.
3. Play a previously broken cutscene; confirm both eyes show the scene and capture the fallback transition log.
4. Return to gameplay; verify depth/stereo returns, including fades and dark areas.
5. Test all face buttons, grips, triggers, party D-pad, lock-on and combat shortcuts. Compare the same scene before and after the clarity settings.

Initial user feedback: visuals and one 3D cutscene were satisfactory, but some dialogue subtitles disagree between the eyes. This does not yet validate missing-eye fallback. See [subtitle investigation](../../tests/ff7/README.md). The separate v2 backend adds support for the observed typeless scene format and routing diagnostics; the subtitle cause remains unconfirmed.
