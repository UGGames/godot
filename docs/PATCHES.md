# UGGames/godot — branch `ug/jigsaw-4.7.2` (local)

The engine tree the jigsaw.ug native app builds its board engines from since 2026-10-01: the main app's Metal engine
and the App Clip's GLES3 engine (jigsaw-mobile `scripts/bridge/build-bridge-engine.sh`,
`scripts/app-clip/build-clip-engine.sh`), and the macOS editor that exports and bakes the board pack
(`scripts/bridge/build-bake-editor.sh`) — all from ONE commit of this branch, because a pack's baked shader cache is
keyed by the engine's version number and commit hash (ShaderRD::setup → base_sha256) and a runtime refuses a pack
from a newer minor version.

## Baseline

| | |
|---|---|
| Upstream | `godotengine/godot`, tag `4.7.2-stable` (`ed1daf0bf0`), remote `godotengine` (fetch only) |
| Replaces | `ug/jigsaw-4.6.1` (Miguel de Icaza's LibGodot fork `swiftgodotkit-4.6` @ `1910602aae`, i.e. upstream 4.6 @ `7bfffc846d`, + the UG patches). Kept untouched in `~/code/UGGames-forks/godot` for the retired SwiftGodot app; the exact 4.6.1 bridge source is local branch `ug/jigsaw-4.6.1-bridge`. |

## Patches carried (in commit order)

| Patch | From | Why the ug_bridge host needs it |
|---|---|---|
| `platform/ios/libgodot_ios.mm` + its SCsub line | Miguel's `4940aad534`, `b5fdb02796`, unchanged | Upstream ships LibGodot for linuxbsd/macos/windows only; ug_bridge's `ug_godot_create` calls `libgodot_create_godot_instance` on iOS. |
| Metal SurfaceLayer retains its CAMetalLayer | `465272072a`, REWORKED (jigsaw-mobile scripts/bridge/patches/0004) | 4.7 rewrote the driver in metal-cpp with the same raw, unretained layer pointer; a view re-mount freed the layer under the surface (SIGSEGV). `retain()` / `release()`. |
| handleMotion reads self.window | `1488ebd31b`, clean | A SwiftUI app's delegate has no `window` (SIGABRT on the first drawView). |
| UG_GODOT_INSTR boot instrumentation | `7cb0504090`, clean | Off unless `cppdefines=UG_GODOT_INSTR`. |
| GDTViewRenderer skips Main::setup2 when a main loop exists | `35ac1756ff`, include context reworked | The host starts the engine through libgodot before GDTView's first drawView. |
| libgodot_ios_sleep / wake / is_asleep, Main::reset_frame_clock | `25dbb0bc41`, 3-way clean | BridgeGodotHost.sleep()/wake(): display link + audio driver stop/start, FOCUS events, wake-time clock reset. |
| CAFrameRateRange 80–120 + coalesced/predicted touches | `6e88fffc91`, 3-way clean | ProMotion stays at 120 after a missed frame; the board's drag reads every digitizer sample (gesture_fsm.gd). |
| display_layer_ios.mm builds with opengl3=no | jigsaw-mobile scripts/bridge/patches/0003, clean | The Metal engine has no GLES3 driver. |

## Dropped, and why

| Patch | Why |
|---|---|
| `31d4e2ec99` macOS embedding (rendering_native_surface, display_server_embedded, libgodot_macos changes) | SwiftGodotKit's macOS host only. |
| `bc0385dc12` `3d5050d5c4` `904780505b` `321f31f8db` `1910602aae` | CI workflows of Miguel's fork. |
| jigsaw-mobile app-clip/patches/0002 (`#include <iterator>`) | Fixed upstream in 4.7 (os_apple_embedded.mm includes it). |
