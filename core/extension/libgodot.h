/**************************************************************************/
/*  libgodot.h                                                            */
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

#include "core/extension/gdextension_interface.gen.h"

// UGGames fork: the sleep()/wake() exports below exist only in the
// Apple-embedded (iOS) platform build. TargetConditionals.h is a module on
// Apple platforms and may not be imported inside an `extern "C"` block, so the
// probe happens here.
#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#define LIBGODOT_APPLE_EMBEDDED 1
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

// Export macros for DLL visibility
#if defined(_MSC_VER) || defined(__MINGW32__)
#define LIBGODOT_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define LIBGODOT_API __attribute__((visibility("default")))
#else
#define LIBGODOT_API
#endif

/**
 * @name libgodot_create_godot_instance
 * @since 4.6
 *
 * Creates a new Godot instance.
 *
 * @param p_argc The number of command line arguments.
 * @param p_argv The C-style array of command line arguments.
 * @param p_init_func GDExtension initialization function of the host application.
 *
 * @return A pointer to created \ref GodotInstance GDExtension object or nullptr if there was an error.
 */
LIBGODOT_API GDExtensionObjectPtr libgodot_create_godot_instance(int p_argc, char *p_argv[], GDExtensionInitializationFunction p_init_func);

/**
 * @name libgodot_destroy_godot_instance
 * @since 4.6
 *
 * Destroys an existing Godot instance.
 *
 * @param p_godot_instance The reference to the GodotInstance object to destroy.
 *
 */
LIBGODOT_API void libgodot_destroy_godot_instance(GDExtensionObjectPtr p_godot_instance);

#ifdef LIBGODOT_APPLE_EMBEDDED

/**
 * @name libgodot_ios_sleep
 * @since 4.6 (UGGames fork ug/jigsaw-4.6.1)
 *
 * Puts an embedded Godot instance to sleep: stops the GDTView display link,
 * stops the audio driver and delivers WINDOW_EVENT_FOCUS_OUT plus
 * NOTIFICATION_APPLICATION_FOCUS_OUT -- exactly what OS_AppleEmbedded does
 * when a real Godot iOS app resigns active, in one call.
 *
 * Needed because in a libgodot host GDTAppDelegateService is not the
 * UIApplicationDelegate, so none of that ever fires by itself and the display
 * link keeps ticking under an opaque host screen.
 *
 * Idempotent, and a no-op when no instance exists, when the instance has not
 * started, when p_godot_instance is not the live instance, or when the
 * instance is already asleep. Must be called on the main thread.
 *
 * @param p_godot_instance The GodotInstance returned by
 *        \ref libgodot_create_godot_instance.
 */
LIBGODOT_API void libgodot_ios_sleep(GDExtensionObjectPtr p_godot_instance);

/**
 * @name libgodot_ios_wake
 * @since 4.6 (UGGames fork ug/jigsaw-4.6.1)
 *
 * Reverses \ref libgodot_ios_sleep: FOCUS_IN, display link restarted, audio
 * driver restarted -- and then re-seeds the frame clock, so the first frame
 * after waking measures a normal delta rather than the whole covered period.
 * Without that reset every in-flight Tween and every _process(delta) would
 * jump forward by the time the screen was covered.
 *
 * Idempotent, and a no-op when the instance is not asleep. Must be called on
 * the main thread.
 *
 * @param p_godot_instance The GodotInstance returned by
 *        \ref libgodot_create_godot_instance.
 */
LIBGODOT_API void libgodot_ios_wake(GDExtensionObjectPtr p_godot_instance);

/**
 * @name libgodot_ios_is_asleep
 * @since 4.6 (UGGames fork ug/jigsaw-4.6.1)
 *
 * True between \ref libgodot_ios_sleep and \ref libgodot_ios_wake. Lets the
 * host assert the engine really stopped rather than infer it from a frame
 * counter.
 */
LIBGODOT_API GDExtensionBool libgodot_ios_is_asleep(void);

/**
 * @name libgodot_ios_gpu_ns / libgodot_ios_gpu_command_buffers
 * @since 4.7.2 (UGGames fork ug/jigsaw-4.7.2)
 *
 * Running totals of the GPU time the Metal driver's command buffers took (GPUEndTime − GPUStartTime, summed as each
 * completes) and of how many completed. 0 on a build without Metal. The host samples the difference over a window.
 */
LIBGODOT_API uint64_t libgodot_ios_gpu_ns(void);
LIBGODOT_API uint64_t libgodot_ios_gpu_command_buffers(void);

#endif // LIBGODOT_APPLE_EMBEDDED

#ifdef __cplusplus
}
#endif // __cplusplus
