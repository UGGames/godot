/**************************************************************************/
/*  libgodot_ios.mm                                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include <atomic>
#include "core/extension/libgodot.h"

#include "core/extension/godot_instance.h"
#include "main/main.h"

#include "os_ios.h"

#include "drivers/apple_embedded/ug_instr.h"

static OS_IOS *os = nullptr;
static GodotInstance *instance = nullptr;

// UGGames fork: true between libgodot_ios_sleep() and libgodot_ios_wake().
// This host is the only thing in the process that drives engine focus, so this
// is the single source of truth for the pair. See the block at the end of this
// file and docs/PATCHES.md.
static bool asleep = false;

GDExtensionObjectPtr libgodot_create_godot_instance(int p_argc, char *p_argv[], GDExtensionInitializationFunction p_init_func) {
	UG_INSTR("libgodot_create_godot_instance enter argc=%d\n", p_argc);
#ifdef UG_GODOT_INSTR
	for (int i = 0; i < p_argc; i++) {
		UG_INSTR("  argv[%d]=%s\n", i, p_argv[i]);
	}
#endif

	// One GodotInstance per process (baseline semantics, kept): a second
	// create returns nullptr. Pintap's build reported it through the
	// instrumentation line; the engine's own error path is kept as well.
	if (instance != nullptr) {
		UG_INSTR("FAIL: instance already exists (singleton violation)\n");
		ERR_FAIL_V_MSG(nullptr, "Only one Godot Instance may be created.");
	}

	UG_INSTR("creating OS_IOS...\n");
	os = new OS_IOS();
	UG_INSTR("OS_IOS created at %p\n", (void *)os);

	UG_INSTR("calling Main::setup with argc=%d\n", p_argc - 1);
	Error err = Main::setup(p_argv[0], p_argc - 1, &p_argv[1], false);
	UG_INSTR("Main::setup returned err=%d (OK=%d)\n", (int)err, (int)OK);
	if (err != OK) {
		UG_INSTR("FAIL: Main::setup err != OK\n");
		memdelete(os);
		os = nullptr;
		return nullptr;
	}

	UG_INSTR("creating GodotInstance...\n");
	instance = memnew(GodotInstance);
	UG_INSTR("calling instance->initialize(p_init_func)...\n");
	if (!instance->initialize(p_init_func)) {
		UG_INSTR("FAIL: instance->initialize returned false\n");
		memdelete(instance);
		instance = nullptr;
		Main::cleanup();
		memdelete(os);
		os = nullptr;
		return nullptr;
	}

	UG_INSTR("SUCCESS: returning instance %p\n", (void *)instance);
	return (GDExtensionObjectPtr)instance;
}

void libgodot_destroy_godot_instance(GDExtensionObjectPtr p_godot_instance) {
	GodotInstance *godot_instance = (GodotInstance *)p_godot_instance;
	if (instance == godot_instance) {
		asleep = false;
		godot_instance->stop();
		memdelete(godot_instance);
		instance = nullptr;
		Main::cleanup();
		if (os != nullptr) {
			memdelete(os);
			os = nullptr;
		}
	}
}

// MARK: - UGGames fork (ug/jigsaw-4.6.1): host-driven sleep / wake
//
// Why this exists. In a libgodot host the SwiftUI application owns the process
// and its own UIApplicationDelegate; the engine's GDTAppDelegateService is
// never installed as the delegate, so none of applicationWillResignActive:,
// applicationDidBecomeActive: or the AVAudioSession interruption observer it
// registers ever fires. Two consequences:
//
//   1. GDTView's CADisplayLink keeps ticking at full rate while an opaque host
//      screen covers the board, burning frames and battery for nothing.
//      GodotInstance::focus_out()/pause() do NOT help: they only post a
//      MainLoop notification (core/extension/godot_instance.cpp:92-117).
//   2. OS_AppleEmbedded::is_focused is therefore never latched to true, so a
//      bare call to on_focus_out() would take its `if (is_focused)` branch and
//      do nothing at all (drivers/apple_embedded/os_apple_embedded.mm:742).
//
// So the host states the focus it owns (set_focused) and then runs the engine's
// own path, which is the whole point: sleep()/wake() do exactly what a real
// Godot iOS app does on resign/become-active, no more --
//   FOCUS_OUT window event -> NOTIFICATION_APPLICATION_FOCUS_OUT ->
//   [godotView stopRendering] -> audio_driver.stop()
// and the reverse on wake, plus one thing a real app does not need:
// Main::reset_frame_clock(). Wall time runs while the display link is stopped
// and nothing bounds the resulting process_step, so without the reset the
// first frame after waking would deliver the entire covered period as one
// _process delta and finish every in-flight Tween instantly.
//
// Both calls are main-thread only (they touch UIKit through stopRendering /
// startRendering) and idempotent. `asleep` is this host's single source of
// truth for the pair; nothing else in the process drives focus.

// Returns the live OS_IOS only when p_godot_instance is the instance this
// translation unit created and that instance has actually started. Anything
// else -- no instance, a stale pointer, a pre-start call -- is a no-op.
static OS_IOS *ug_live_os(GDExtensionObjectPtr p_godot_instance) {
	if (instance == nullptr || os == nullptr) {
		return nullptr;
	}
	if ((GodotInstance *)p_godot_instance != instance) {
		return nullptr;
	}
	if (!instance->is_started()) {
		return nullptr;
	}
	return os;
}

void libgodot_ios_sleep(GDExtensionObjectPtr p_godot_instance) {
	OS_IOS *live_os = ug_live_os(p_godot_instance);
	if (live_os == nullptr) {
		UG_INSTR("libgodot_ios_sleep: no live instance, ignored\n");
		return;
	}
	if (asleep) {
		UG_INSTR("libgodot_ios_sleep: already asleep, ignored\n");
		return;
	}

	asleep = true;

	// The engine's app delegate never latched this in an embedded host; the
	// host owns focus here. Without it on_focus_out() is a silent no-op.
	live_os->set_focused(true);
	live_os->on_focus_out();

	UG_INSTR("libgodot_ios_sleep: display link and audio driver stopped\n");
}

void libgodot_ios_wake(GDExtensionObjectPtr p_godot_instance) {
	OS_IOS *live_os = ug_live_os(p_godot_instance);
	if (live_os == nullptr) {
		UG_INSTR("libgodot_ios_wake: no live instance, ignored\n");
		return;
	}
	if (!asleep) {
		UG_INSTR("libgodot_ios_wake: not asleep, ignored\n");
		return;
	}

	asleep = false;

	// FOCUS_IN window event, NOTIFICATION_APPLICATION_FOCUS_IN,
	// [godotView startRendering], audio_driver.start().
	live_os->on_focus_in();

	// After startRendering, and as late as possible before the CADisplayLink's
	// first drawView, so the next Main::iteration measures a real frame delta
	// instead of the whole covered period.
	Main::reset_frame_clock();

	UG_INSTR("libgodot_ios_wake: rendering resumed, frame clock reset\n");
}

GDExtensionBool libgodot_ios_is_asleep(void) {
	return asleep ? 1 : 0;
}

#if defined(METAL_ENABLED)
extern std::atomic<uint64_t> ug_gpu_busy_ns;
extern std::atomic<uint64_t> ug_gpu_command_buffers;
#endif

uint64_t libgodot_ios_gpu_ns(void) {
#if defined(METAL_ENABLED)
	return ug_gpu_busy_ns.load(std::memory_order_relaxed);
#else
	return 0;
#endif
}

uint64_t libgodot_ios_gpu_command_buffers(void) {
#if defined(METAL_ENABLED)
	return ug_gpu_command_buffers.load(std::memory_order_relaxed);
#else
	return 0;
#endif
}
