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

#include "core/extension/libgodot.h"

#include "core/extension/godot_instance.h"
#include "main/main.h"

#include "os_ios.h"

#include "drivers/apple_embedded/ug_instr.h"

static OS_IOS *os = nullptr;
static GodotInstance *instance = nullptr;

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
