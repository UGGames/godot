/**************************************************************************/
/*  ug_instr.h                                                            */
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

#pragma once

// UGGames fork (ug/jigsaw-4.6.1): compile-time boot instrumentation for the
// embedded (libgodot) iOS host path. Off by default; enable with
//
//     scons ... cppdefines=UG_GODOT_INSTR
//
// Every line is written to stderr with the "[GODOT-INSTR] " prefix so it can
// be grepped out of the Xcode console or a device log. The strings are the
// ones Pintap used while bringing the embedding up (2026-05-22); they are
// kept verbatim behind this flag rather than dropped. See docs/PATCHES.md.

#ifdef UG_GODOT_INSTR
#include <stdio.h>
#define UG_INSTR(...)                                  \
	do {                                               \
		fprintf(stderr, "[GODOT-INSTR] " __VA_ARGS__); \
		fflush(stderr);                                \
	} while (0)
#else
#define UG_INSTR(...) ((void)0)
#endif
