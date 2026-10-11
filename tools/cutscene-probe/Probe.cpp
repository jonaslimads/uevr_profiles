#include <windows.h>
#include <d3d12.h>
#include <atomic>
#include <cstdint>
#include "uevr/API.h"

namespace {
const UEVR_PluginInitializeParam* api{};
std::atomic<unsigned> ticks{}, slate{}, viewport{}, dx12{}, views0{}, views1{}, otherViews{};
std::atomic<unsigned long long> width{};
std::atomic<unsigned> height{}, format{};
ULONGLONG lastReport{};
bool markerDown{};
unsigned marker{};
void tick(UEVR_UGameEngineHandle, float) { ++ticks; }
void drawSlate(UEVR_FSlateRHIRendererHandle, UEVR_FViewportInfoHandle) { ++slate; }
void drawViewport(UEVR_UGameViewportClientHandle, UEVR_FViewportHandle, UEVR_FCanvasHandle) { ++viewport; }
void view(UEVR_StereoRenderingDeviceHandle, int index, float, UEVR_Vector3f*, UEVR_Rotatorf*, bool) {
    if (index == 0) ++views0;
    else if (index == 1) ++views1;
    else ++otherViews;
}
void render(void*, void* resource, void*) {
    ++dx12;
    if (resource) {
        const auto desc = static_cast<ID3D12Resource*>(resource)->GetDesc();
        width.store(desc.Width); height.store(desc.Height); format.store(static_cast<unsigned>(desc.Format));
    }
}
void present() {
    const bool down = (GetAsyncKeyState(VK_F8) & 0x8000) != 0;
    if (down && !markerDown) api->functions->log_info("[SWGRProbe] MARKER %u (F8)", ++marker);
    markerDown = down;
    const auto now = GetTickCount64();
    if (now - lastReport < 1000) return;
    const auto elapsed = now - lastReport;
    lastReport = now;
    api->functions->log_info(
        "[SWGRProbe] interval_ms=%llu ticks=%u slate=%u viewport=%u view_index0=%u view_index1=%u view_other=%u dx12_callbacks=%u target=%llux%u format=%u hmd_active=%d",
        elapsed, ticks.exchange(0), slate.exchange(0), viewport.exchange(0), views0.exchange(0), views1.exchange(0), otherViews.exchange(0), dx12.exchange(0), width.load(), height.load(), format.load(),
        api->vr && api->vr->is_hmd_active ? static_cast<int>(api->vr->is_hmd_active()) : -1);
}
}

extern "C" __declspec(dllexport) void uevr_plugin_required_version(UEVR_PluginVersion* version) {
    version->major = UEVR_PLUGIN_VERSION_MAJOR;
    version->minor = UEVR_PLUGIN_VERSION_MINOR;
    version->patch = UEVR_PLUGIN_VERSION_PATCH;
}
extern "C" __declspec(dllexport) bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* param) {
    if (!param || !param->functions || !param->functions->log_info || !param->callbacks || !param->sdk || !param->sdk->callbacks) return false;
    // Protect against installation into a different backend: this probe uses its matching public API.
    if (!param->version || param->version->major != UEVR_PLUGIN_VERSION_MAJOR || param->version->minor < UEVR_PLUGIN_VERSION_MINOR) return false;
    api = param;
    lastReport = GetTickCount64();
    const auto callbacks = param->sdk->callbacks;
    bool ok = param->callbacks->on_present(present);
    ok = callbacks->on_pre_engine_tick(tick) && ok;
    ok = callbacks->on_pre_slate_draw_window_render_thread(drawSlate) && ok;
    ok = callbacks->on_pre_viewport_client_draw(drawViewport) && ok;
    ok = callbacks->on_pre_calculate_stereo_view_offset(view) && ok;
    ok = param->callbacks->on_post_render_vr_framework_dx12(render) && ok;
    param->functions->log_info("[SWGRProbe] diagnostic v1 registration_ok=%d. F8 marks transitions. No rendering/config changes; counters do not measure eye pixels or detect Bink.", static_cast<int>(ok));
    // Keep the DLL loaded even if one callback was unavailable, because others are registered.
    return true;
}
