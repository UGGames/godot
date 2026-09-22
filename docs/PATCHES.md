# UGGames/godot — branch `ug/jigsaw-4.6.1`

The engine tree the jigsaw.ug native app (`UGGames/jigsaw-mobile`) builds
`libgodot-ios.xcframework` from. It is Miguel de Icaza's LibGodot fork at the
commit Pintap shipped on, plus Pintap's local patches recovered as commits.
Plan of record: `twitchwidget/docs/native-app-plan.md` §2.10.

## Baseline

| | |
|---|---|
| Upstream | `migueldeicaza/godot`, branch `swiftgodotkit-4.6` (remote `upstream`) |
| Baseline commit | `1910602aae3e7c9c38a964f3b1af36897d2ce1b1` — "Build this", authored 2026-02-24 00:08:04 -0500 |
| Upstream tag at that commit | `v4.6.3` (the fork's tag; `version.py` there says `major=4 minor=6 patch=1 status="rc"`, so binaries report 4.6.1.rc — both names refer to this one tree) |
| How the baseline was recovered | `pintap/vendor/godot/core/version_hash.gen.cpp`: `GODOT_VERSION_HASH = "1910602aae…"`, `GODOT_VERSION_TIMESTAMP = 1771909684` = 2026-02-24 05:08:04 UTC, which is the commit's author date |
| Upstream head when forked (2026-09-22) | `d064e255e2ede81b100b1e8f8ad6334bf212b748` = tag `v4.6.4` (2026-05-26). This is exit ramp 1 in the plan. |
| Patch recovery | `diff -ruN` of a clean checkout of `1910602aae` against `/Users/johnlinden/code/pintap/vendor/godot` on 2026-09-22 (Pintap's `vendor/` is gitignored with no nested repo). `diff -rq` listed exactly four modified files and one extra object file; nothing else differed outside the excluded build products. |

## Patches, in commit order

| Commit | File | Kind | Why |
|---|---|---|---|
| `465272072a` | `drivers/metal/rendering_context_driver_metal.mm` | engine | `SurfaceLayer::layer` was `__unsafe_unretained`; when the SwiftUI host re-mounts the view the GDTView (and its `CAMetalLayer`) is freed while the DisplayServer still points at it → `objc_msgSend` on freed memory in `acquire_next_frame_buffer` (SIGSEGV). Strong reference. |
| `1488ebd31b` | `drivers/apple_embedded/godot_view_apple_embedded.mm` | engine | `handleMotion` read the orientation through `[UIApplication.sharedApplication.delegate window]`; a SwiftUI app's generated delegate has no `window` → unrecognized selector → SIGABRT on the first `drawView`. Uses `self.window`, falling back to a connected scene's key window. |
| `7cb0504090` | `platform/ios/libgodot_ios.mm`, new `drivers/apple_embedded/ug_instr.h` | instrumentation | Pintap's `[GODOT-INSTR]` `fprintf` lines through `libgodot_create_godot_instance`, kept verbatim behind `UG_GODOT_INSTR` (see below). The one-instance rule is **baseline** behaviour (`ERR_FAIL_COND_V_MSG(instance != nullptr, nullptr, …)` already returned nullptr on a second create; `libgodot_destroy_godot_instance` already ran `Main::cleanup`); Pintap only re-expressed it as a bare `if` with an instrumentation line. This commit keeps the engine's error message (`ERR_FAIL_V_MSG`) inside that `if`. |
| `35ac1756ff` | `drivers/apple_embedded/godot_view_renderer.mm` | engine (+1 instrumentation line) | When the engine was created through libgodot (`GodotInstance::start` from SwiftGodotKit), `Main::setup2`/`OS::start` have already run by GDTView's first `drawView`; `GDTViewRenderer::setupView` ran its own `setupProjectData`/`Main::setup2` again and crashed. If `OS::get_singleton()->get_main_loop()` exists, mark the three setup stages done and return NO. Its diagnostic line is behind `UG_GODOT_INSTR`. |

Pintap's own record of why each patch exists: Claude memory
`~/.claude/projects/-Users-johnlinden-code-pintap/memory/magic_mode_architecture.md`
(patches 6, 7, 8 and the C-level singleton note), and Linear doc "Magic Mode —
Godot embedding in SwiftUI (iOS) working notes".

### Deviations from Pintap's tree (deliberate)

- The instrumentation is compiled only with `UG_GODOT_INSTR`. Pintap's tree
  printed unconditionally. With the flag off, `libgodot_ios.mm` is the baseline
  plus one unused include and the comment above the singleton check;
  `godot_view_renderer.mm` is the baseline plus the setup2 skip.
- In the second-create branch the engine's `ERR_FAIL_V_MSG` is kept (Pintap's
  bare `return nullptr` dropped the message). Return value is unchanged.
- Pointer arguments to the `%p` lines are cast to `void *` (warning hygiene).

Everything else is byte-identical to Pintap's tree (checked with `diff -ru`
after the last commit; the only remaining hunks are the ones listed here).

### Enabling the instrumentation

```
scons platform=ios arch=arm64 target=template_release vulkan=no metal=yes disable_path_overrides=no cppdefines=UG_GODOT_INSTR
```

`cppdefines` is a declared SCons option (`SConstruct` line 348, appended at
line 628). Lines go to stderr prefixed `[GODOT-INSTR] `. The host twin is
`UG_GODOT_INSTR=1` in the environment when SwiftGodotKit's manifest is
resolved (see `UGGames/SwiftGodotKit` `docs/PATCHES.md`).

## Excluded from the recovery as build products / noise

All under `/Users/johnlinden/code/pintap/vendor/godot`:

- `bin/` (488 MB): `bin/libgodot.ios.template_release.arm64.a` (the ramp-0
  binary, below) and `bin/obj/` (the object tree; `redirect_build_objects`
  puts objects there).
- `drivers/apple_embedded/app.ios.template_release.arm64.o` (55,440 bytes,
  2026-05-22 07:39): the object scons compiles from
  `drivers/apple_embedded/app.swift` (the fork's SwiftUI `@main`, module
  `godot_swift_module`). It is the member Pintap deleted from the archive
  with `ar d` (see Build); `ar t` of the archive lists 2,216 members and no
  `app.ios.*.o`.
- 143 `*.gen.*` files (scons output: `core/version_generated.gen.h`,
  `core/version_hash.gen.cpp`, `core/extension/gdextension_interface.gen.h`,
  the RD/GLES3 shader headers, `scene/theme/*.gen.h`, the platform export
  logos…). None is tracked at the baseline (`git ls-files | grep '\.gen\.'`
  is empty).
- `.scons_env.json`, `.scons_node_count`, `.sconsign5.dblite` (14.5 MB), 75
  `__pycache__/` directories.
- Nothing under `platform/*/` differed except `platform/ios/libgodot_ios.mm`.

Nothing in the diff was left unclassified.

## Build

Pintap's recorded invocation (`vendor/godot/.scons_env.json`: `platform=ios`,
`arch=arm64`, `target=template_release`, `vulkan=False`, `metal=True`,
`disable_path_overrides=False`, `simulator=False`, `optimize=speed`,
`debug_symbols=False`, `production=False`, `lto=none`, `precision=single`,
`library_type=executable`, `module_mono_enabled=False`; SDK
`iPhoneOS26.4.sdk`, `-miphoneos-version-min=14.0`, `-std=gnu++17
-fno-exceptions`, link `-Wl,-S -Wl,-x -Wl,-dead_strip`):

```
cd <this checkout>
scons platform=ios arch=arm64 target=template_release vulkan=no metal=yes disable_path_overrides=no
```

Notes measured from the tree, not assumed:

- `library_type=executable` means `LIBGODOT_ENABLED` is **not** defined in
  this build; on this fork `platform/ios/SCsub` always compiles
  `libgodot_ios.mm` and always emits `bin/libgodot.ios.template_release.arm64.a`
  (`combine_libs_apple_embedded` merges every library into it).
- `drivers/apple_embedded/SCsub` compiles `*.swift` there (`app.swift`) into
  the same archive. Its `_main`/`@main` collides with the host app's `main`
  once the host links with `-ObjC` (needed so `GDTViewController` et al. are
  not dead-stripped), so Pintap's post-build step is:

  ```
  ar d bin/libgodot.ios.template_release.arm64.a app.ios.template_release.arm64.o
  ```

- Packaging: `UGGames/SwiftGodotKit` `scripts/make-libgodot.xcframework
  <SwiftGodot dir> <godot dir> <output dir>` (Pintap's copy:
  `/Users/johnlinden/code/pintap/vendor/SwiftGodotKit/scripts/make-libgodot.xcframework`;
  its `scripts/Makefile` runs `bash -x make-libgodot.xcframework
  ../../SwiftGodot ../../godot ../build`). It copies
  `core/extension/libgodot.h` and `gdextension_interface.gen.h` as the
  headers and produces a device-only `ios-arm64` slice when no simulator
  `.a` exists (there is none: the simulator supports only the Compatibility
  renderer).
- Xcode 26.4.1 (17E202) per the plan; the SDK path above is what the env
  recorded.
- Nothing has been built from this branch yet (Phase 0 S1 does that). The
  `scons` line above is Pintap's, reproduced from the recorded environment.

## Ramp-0 binary (not committed)

| | |
|---|---|
| Path | `/Users/johnlinden/code/pintap/vendor/godot/bin/libgodot.ios.template_release.arm64.a` |
| sha256 | `5d00d76389f053f847df0ca89701a27dfdd1b866e2b6a41c6b6308ec71a97e1e` |
| Size / mtime | 171,345,584 bytes, 2026-05-22 12:17 (local) |
| State | post-`ar d` (no `app.ios.*.o` member) |
| Same bytes as | `/Users/johnlinden/code/pintap/vendor/SwiftGodotKit/build/ios/libgodot.xcframework/ios-arm64/libgodotkit.a` (identical sha256) |

Built from Pintap's tree, i.e. this branch's four patches with the
instrumentation compiled in unconditionally. The plan's exit ramp 0 ships on
this file while reproducibility is fixed.

## TODO — the one new patch: `sleep()` / `wake()` (plan §2.10, not applied)

Add to `platform/ios/libgodot_ios.mm` two C exports (declared in
`core/extension/libgodot.h` so the header the xcframework ships carries them):

```
void libgodot_ios_sleep(GDExtensionObjectPtr p_godot_instance);
void libgodot_ios_wake(GDExtensionObjectPtr p_godot_instance);
```

- `sleep()` wraps `OS_AppleEmbedded::on_focus_out()` — stops the display link,
  stops the audio driver, sends `NOTIFICATION_APPLICATION_FOCUS_OUT` — exactly
  what a real Godot iOS app does when it resigns active, in one call.
- `wake()` wraps `OS_AppleEmbedded::on_focus_in()` (display link + audio driver
  start, `NOTIFICATION_APPLICATION_FOCUS_IN`) **and resets the frame clock**
  before the first `Main::iteration`, so the whole covered period is not
  delivered as one `_process` delta: physics is clamped by
  `max_physics_steps_per_frame`, `_process` and `Tween` are not, and every
  in-flight tween would otherwise finish instantly.
- Host side: `GodotApp.sleep()` / `GodotApp.wake()` in `UGGames/SwiftGodotKit`
  calling these. It replaces the synthesis's `focusOut` + `stopRendering` +
  `low_processor_usage_mode` trio and its `addChild` patch; the board screen
  uses `.defersSystemGestures(on: .bottom)` and
  `.persistentSystemOverlays(.hidden)` instead of a child controller.
- Acceptance (S1): with the board covered by an opaque SwiftUI screen,
  `sleep()` gives 0 fps; `wake()` resumes with scene state intact.
