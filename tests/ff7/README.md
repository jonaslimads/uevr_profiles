# FF7 Remake subtitle investigation

The user reported that the first FF7 build looks good and a 3D cutscene played successfully. Subtitle text intermittently disagrees between the eyes during 3D dialogue/cutscenes. Other cutscenes and missing-eye recovery are still pending validation.

The reviewed first run logged backend `ddc7bfa1ce19275bfa227249360f2e75324d2b98`, DX11, the original FF7 plugin, 3264x3264 eye extent and engine scene format 90 (BGRA8 TYPELESS). It contained no `[FF7][auto-mono]` transitions. V1 did not accept typeless sources, so that run cannot establish that automatic recovery actually activated. Do not infer a successful mono-video fix solely from a functioning 3D cutscene.

The normal backend UI path uses a single shared OpenXR UI image/layer for BOTH eyes. The original plugin redirects `InGameUIRenderTarget` to UEVR's UI texture. This does not establish that all cinematic subtitles use that texture. Text can be embedded in an eye-specific scene or use another rendering path. Moving the global UI plane or duplicating the entire scene would not be a demonstrated subtitle fix.

FF7Pico4-v2 accepts typeless RGBA/BGRA sources through compatible typed staging resources and adds five-second scene/UI/sampler and requested-layer metadata. Real DX11 WARP tests cover both channel layouts in UNORM, SRGB and TYPELESS formats. These tests verify detector readback and stereo recovery, not the intermittent subtitle bug. The active v1 and profile remain available for comparison.

## Reproduce

1. Complete the current gameplay session before changing injectors. Keep DX11, Windowed, OpenXR/VDXR and the existing profile.
2. Start the separate v2 investigation injector, inject and reproduce the same conversation/cutscene.
3. Note the scene and approximate time. Record whether text changes when turning the head, is duplicated in one eye, has vertical disagreement, or only has horizontal depth separation. If possible, obtain separate eye images showing scene and subtitles.
4. Save the runtime log/config locally immediately after the problem appears. Inspect `[FF7][ui-diagnostics]`, `[FF7][ui-layer]` and `[FF7][auto-mono]` at that time.
5. Verify sampler eligibility and supported format, compare UI/source extents, and determine whether the subtitle lives in the shared UI or the stereo scene before applying a rendering fix.

No subtitle-region copy, global mono override or profile reinstallation is required by the investigation. Raw captures and screenshots stay outside the public repository.
