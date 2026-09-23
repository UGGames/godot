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
| _(this commit)_ | `drivers/apple_embedded/godot_view_apple_embedded.mm` | engine (new) | **CADisplayLink asks for a `CAFrameRateRange`, not the deprecated fixed `preferredFramesPerSecond`.** A fixed request can only be honoured at a divisor of the panel rate, so one missed frame drops a ProMotion phone from 120 to 60 with no mandate to climb back. The range is `[preferred × 2/3 … preferred]` above 60 Hz (80…120 at 120, Apple's own worked example) and collapses to the old fixed request at 60 and below and on pre-iOS-15. |
| _(this commit)_ | `drivers/apple_embedded/godot_view_apple_embedded.mm`, `drivers/apple_embedded/display_server_apple_embedded.{h,mm}`, `core/input/input_event.{h,cpp}` | engine (new) | **Coalesced and predicted touches.** See § "Coalesced and predicted touches" below. |
| `25dbb0bc41` | `platform/ios/libgodot_ios.mm`, `core/extension/libgodot.h`, `drivers/apple_embedded/os_apple_embedded.h`, `main/main.h`, `main/main.cpp` | engine (new) | The plan's ONE new patch: `libgodot_ios_sleep()` / `libgodot_ios_wake()` / `libgodot_ios_is_asleep()`, plus `Main::reset_frame_clock()` and a focus-latch accessor pair on `OS_AppleEmbedded`. Full semantics in § "The sleep()/wake() export" below. |

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

## The `sleep()` / `wake()` export (applied)

The plan's "ONE new patch" (§2.10). Commit `25dbb0bc41`.

### What the host calls

```c
void          libgodot_ios_sleep(GDExtensionObjectPtr p_godot_instance);
void          libgodot_ios_wake(GDExtensionObjectPtr p_godot_instance);
GDExtensionBool libgodot_ios_is_asleep(void);
```

Declared in `core/extension/libgodot.h` under `LIBGODOT_APPLE_EMBEDDED`
(`TARGET_OS_IPHONE`), so the header `make-libgodot.xcframework` ships carries
them. The `TargetConditionals.h` probe sits ABOVE the `extern "C" {` block:
importing a system module inside `extern "C"` is an error under the
`-fmodules -fcxx-modules` that `platform/ios/SCsub` adds.

Host twin: `GodotApp.sleep()` / `GodotApp.wake()` in `UGGames/SwiftGodotKit`
(not written yet). It REPLACES `instance.focusOut()` + `stopRendering` +
`low_processor_usage_mode`; do not call both, or FOCUS_OUT is posted twice.

### Why a wrapper was needed at all

`OS_AppleEmbedded::on_focus_out()` / `on_focus_in()`
(`drivers/apple_embedded/os_apple_embedded.mm:742-776`) already do exactly the
right four things. The problem is that in this host nothing ever calls them,
and one of them would not work if it did:

- `GDTAppDelegateService` is **not** the `UIApplicationDelegate` — the SwiftUI
  app is. So `applicationWillResignActive:`, `applicationDidBecomeActive:` and
  the `AVAudioSessionInterruptionNotification` observer that
  `application:didFinishLaunchingWithOptions:` registers
  (`app_delegate_service.mm:70-76`, `:163-176`) never run.
- The engine's own SwiftUI `@main` (`drivers/apple_embedded/app.swift:66-72`)
  does drive `startRendering`/`stopRendering` off `scenePhase`, but that object
  file is deleted from the archive (`ar d`, see Build), so it never runs either.
- `GodotInstance::focus_out()` / `pause()`, which SwiftGodotKit's
  `GodotApp` does call, are **notification-only**
  (`core/extension/godot_instance.cpp:92-117`): no display link, no audio.
- Consequently `OS_AppleEmbedded::is_focused` is **never latched to true** in
  this host. It starts `false` (`os_apple_embedded.h:76`), and
  `on_focus_out()`'s `if (is_focused)` guard would make a bare call a **silent
  no-op** — the display link would keep ticking and S1's "covered = 0 fps"
  criterion would fail for a reason that looks like nothing happened.

So `sleep()` states the focus the host owns (`set_focused(true)`, a plain
setter with no side effects of its own) and then runs the engine's own path.
The observable behaviour is identical to a real Godot iOS app resigning active:

| | `sleep()` | `wake()` |
|---|---|---|
| DisplayServer | `WINDOW_EVENT_FOCUS_OUT` | `WINDOW_EVENT_FOCUS_IN` |
| MainLoop | `NOTIFICATION_APPLICATION_FOCUS_OUT` | `NOTIFICATION_APPLICATION_FOCUS_IN` |
| GDTView | `stopRendering` (CADisplayLink invalidated, touches cleared) | `startRendering` |
| Audio | `audio_driver.stop()` | `audio_driver.start()` |
| Frame clock | — | `Main::reset_frame_clock()` |

Nothing else. No `low_processor_usage_mode` (§2.4: it is a sleep inside
`Main::iteration`, which here runs on the iOS main thread), no `addChild`, no
second render-control path.

### The wake-time clock reset

`Main::iteration()` (`main/main.cpp:4789-4821`) takes its delta from
`main_timer_sync.advance()`, i.e.
`current_cpu_ticks_usec - last_cpu_ticks_usec`
(`main/main_timer_sync.cpp:490-497`). That value is smoothed
(`DeltaSmoother`, which disables itself for outliers) and clamped only
*relative to itself* (`advance_checked`, `:414-444`) — there is no upper bound.
`Main::last_ticks` feeds the FPS counter the same way.

Wall time keeps running while the display link is stopped, so the first frame
after `startRendering` would report the entire covered period as one
`process_step`. Physics survives it (`max_physics_steps_per_frame` clamps
`advance.physics_steps`, `main.cpp:4823-4827`); `_process(delta)` and `Tween`
do **not**, so every in-flight tween would complete in that single frame.

`Main::reset_frame_clock()` (new, `main/main.h`, `main/main.cpp` next to
`force_redraw`) re-seeds both clocks from `OS::get_ticks_usec()`:

```cpp
void Main::reset_frame_clock() {
    const uint64_t ticks = OS::get_singleton()->get_ticks_usec();
    last_ticks = ticks;
    main_timer_sync.init(ticks);
}
```

It has to live in `main.cpp`: `main_timer_sync` is a file-static there
(`main.cpp:3876`) and `Main::last_ticks` is private. It deliberately does not
touch `time_accum` or `time_deficit` (frozen while no iteration runs, and both
bounded by a physics step) or `Engine`'s time scale, which is the project's
own setting and not ours to reset.

`wake()` calls it **after** `on_focus_in()`, so the reset is as close as
possible to the CADisplayLink's first `drawView`.

### Guards

Both calls are main-thread only (they reach UIKit through
`start`/`stopRendering`) and are no-ops unless every one of these holds:
a live `instance` and `os` exist in this translation unit; the caller's
`p_godot_instance` **is** that instance; `instance->is_started()`. On top of
that `sleep()` returns if already asleep and `wake()` returns if not asleep,
so redundant `scenePhase` transitions are free. `asleep` is reset by
`libgodot_destroy_godot_instance`. `libgodot_ios_is_asleep()` lets the host
assert the state instead of inferring it from a frame counter.

### Verified

`-fsyntax-only`, zero diagnostics, in both configurations, over
`platform/ios/libgodot_ios.mm`, `main/main.cpp` and
`drivers/apple_embedded/os_apple_embedded.mm`:

```
docs/ug-syntax-check.sh <gen-header-overlay>
docs/ug-syntax-check.sh <gen-header-overlay> -DUG_GODOT_INSTR
```

The script applies the flags `platform/ios/detect.py` and
`platform/ios/SCsub` produce for this build line (`-arch arm64
-miphoneos-version-min=14.0 -fobjc-arc -std=gnu++17 -fno-exceptions -fmodules
-fcxx-modules`, `IOS_ENABLED APPLE_EMBEDDED_ENABLED UNIX_ENABLED
COREAUDIO_ENABLED METAL_ENABLED RD_ENABLED THREADS_ENABLED NDEBUG`). The
`<gen-header-overlay>` argument is a directory mirroring the `*.gen.h` /
`*.gen.inc` build products, which are not in the checkout; on 2026-09-22 it was
made from Pintap's tree:

```
find /Users/johnlinden/code/pintap/vendor/godot \
     \( -name '*.gen.h' -o -name '*.gen.inc' \) -not -path '*/bin/*' | while read -r f; do
  rel="${f#/Users/johnlinden/code/pintap/vendor/godot/}"
  mkdir -p "$OVERLAY/$(dirname "$rel")"; cp "$f" "$OVERLAY/$rel"
done
```

**Not** link-tested. No `scons` build of this branch existed when the patch
landed.

## Ramp-0 caveat, restated

The ramp-0 archive above (`sha256 5d00d763…`) was built from Pintap's tree on
2026-05-22 and therefore **predates this patch**: `nm -g` finds no
`_libgodot_ios_sleep`. Packaged as an xcframework it answers every other S1
sub-criterion — boot time, RSS, 120 Hz, touch under the SwiftUI HUD, audio
after an interruption — but it cannot answer

> with the board covered by an opaque SwiftUI screen, `sleep()` gives 0 fps and
> `wake()` resumes with scene state intact

because the symbol the host would call does not exist in it, and a host that
calls it will not link. That criterion needs an archive rebuilt from this
branch. `UGGames/jigsaw-mobile` `scripts/build-libgodot.sh` produces one and
`scripts/fetch-libgodot.sh --verify` says plainly which archive is in play.


## Coalesced and predicted touches

`-touchesMoved:withEvent:` accepted the `UIEvent` and never used it: Godot read
`locationInView:` off the delivered `UITouch` and discarded the rest. The digitizer samples at up
to 240 Hz while UIKit delivers at the display rate, so roughly half of every 120 Hz drag was thrown
away — not a latency cost (the newest sample was still the newest) but a **fidelity** cost for any
decision taken on the shape of the path rather than its endpoint.

`InputEventScreenDrag` gains two bools, both bound and both carried through `xformed_by`:

- **`coalesced`** — an intermediate sample of a `coalescedTouchesForTouch:` batch. Every sample of
  a batch is emitted, in order, with `prev_point` chained so each `relative` is a real segment
  whose sum equals the chord the old code reported. Only the final sample is the current position.
- **`predicted`** — a `predictedTouchesForTouch:` extrapolation, i.e. not a measurement. Only the
  samples within ONE frame (`1.0 / preferredFrameRate`) of the real touch's timestamp are emitted;
  UIKit offers more and the rest is dropped deliberately.

`InputEventScreenDrag::accumulate` refuses to fold when either side is `coalesced`, or when
`predicted` differs. **Without that refusal both features are no-ops**: Godot's accumulator exists
to keep the newest position and drop the rest, which would fold a batch straight back into the
chord it was read to avoid, and would silently promote a predicted position into a real event. Two
ordinary deliveries in one tick still accumulate exactly as before.

`DisplayServerAppleEmbedded::touch_drag` gained two defaulted trailing bools, so every existing
call site keeps its exact previous meaning.

Both are project settings, `GLOBAL_DEF`'d in `godot_commonInit` and read in `-touchesMoved:`
through `GLOBAL_GET_CACHED` (which re-reads on any `ProjectSettings` change, so a game can flip
them at runtime with `ProjectSettings.set_setting()` and the next touch obeys):

| setting | default | why |
|---|---|---|
| `input_devices/pointing/apple_embedded/coalesced_touches` | **true** | pure fidelity win, no behavioural risk; the setting is a kill switch |
| `input_devices/pointing/apple_embedded/predicted_touches` | **false** | a prediction is a guess. Turn it on only for the span of a gesture that is a pure function of the finger position (dragging one object); a game that commits state on a predicted sample commits the wrong state |

Consumer side, for reference: jigsaw-mobile's `gesture_fsm.gd` turns `predicted_touches` on for
exactly `State.DRAG`, moves the held piece on a predicted sample and touches **nothing** else — no
tracker update, no state transition, no commit — so a wrong guess is overwritten by the next real
sample and the drop always commits from the real touch-up position. See that repo's
`docs/touch-latency.md`.
