/**************************************************************************/
/*  godot_view_apple_embedded.mm                                          */
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

#import "godot_view_apple_embedded.h"

#include "core/config/project_settings.h"
#include "core/os/keyboard.h"
#include "core/string/ustring.h"
#import "drivers/apple_embedded/display_layer_apple_embedded.h"
#import "drivers/apple_embedded/display_server_apple_embedded.h"
#import "drivers/apple_embedded/godot_view_renderer.h"

#import <CoreMotion/CoreMotion.h>

static const int max_touches = 32;
static const float earth_gravity = 9.80665;

@interface GDTView () {
	UITouch *godot_touches[max_touches];
	CGFloat last_edr_headroom;
}

@property(assign, nonatomic) BOOL isActive;

// CADisplayLink available on 3.1+ synchronizes the animation timer & drawing with the refresh rate of the display, only supports animation intervals of 1/60 1/30 & 1/15
@property(strong, nonatomic) CADisplayLink *displayLink;

// An animation timer that, when animation is started, will periodically call -drawView at the given rate.
// Only used if CADisplayLink is not
@property(strong, nonatomic) NSTimer *animationTimer;

@property(strong, nonatomic) CALayer<GDTDisplayLayer> *renderingLayer;

@property(strong, nonatomic) CMMotionManager *motionManager;

@property(assign, nonatomic) BOOL delegateDidFinishSetUp;

@end

@implementation GDTView

// Implemented in subclasses
- (CALayer<GDTDisplayLayer> *)initializeRenderingForDriver:(NSString *)driverName {
	return nil;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];

	if (self) {
		[self godot_commonInit];
	}

	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];

	if (self) {
		[self godot_commonInit];
	}

	return self;
}

- (void)dealloc {
	[self stopRendering];

	self.renderer = nil;
	self.delegate = nil;

	if (self.renderingLayer) {
		[self.renderingLayer removeFromSuperlayer];
		self.renderingLayer = nil;
	}

	if (self.motionManager) {
		[self.motionManager stopDeviceMotionUpdates];
		self.motionManager = nil;
	}

	if (self.displayLink) {
		[self.displayLink invalidate];
		self.displayLink = nil;
	}

	if (self.animationTimer) {
		[self.animationTimer invalidate];
		self.animationTimer = nil;
	}
}

- (void)godot_commonInit {
	self.preferredFrameRate = 60;
	self.useCADisplayLink = bool(GLOBAL_DEF("display.AppleEmbedded/use_cadisplaylink", true)) ? YES : NO;
	last_edr_headroom = 0.0;

	// UGGames fork (ug/jigsaw-4.6.1). Both are read live in -touchesMoved:withEvent: through
	// GLOBAL_GET_CACHED, which re-reads whenever ProjectSettings changes -- so a game can flip
	// them at runtime with ProjectSettings.set_setting() and the next touch obeys.
	//
	// `coalesced_touches` defaults ON: it is a pure fidelity win with no behavioural risk.
	// `predicted_touches` defaults OFF and is meant to be turned on only for the span of a
	// gesture that is a pure function of the finger position (dragging one object). A predicted
	// sample is a guess; a game that commits state on one will commit the wrong state.
	GLOBAL_DEF("input_devices/pointing/apple_embedded/coalesced_touches", true);
	GLOBAL_DEF("input_devices/pointing/apple_embedded/predicted_touches", false);

#if !defined(VISIONOS_ENABLED)
	self.contentScaleFactor = [UIScreen mainScreen].scale;
#endif

	if (@available(iOS 17.0, *)) {
		[self registerForTraitChanges:@[ [UITraitUserInterfaceStyle class] ] withTarget:self action:@selector(traitCollectionDidChangeWithView:previousTraitCollection:)];
	}

	[self initTouches];

	self.multipleTouchEnabled = YES;

	// Configure and start accelerometer
	if (!self.motionManager) {
		self.motionManager = [[CMMotionManager alloc] init];
		if (self.motionManager.deviceMotionAvailable) {
			self.motionManager.deviceMotionUpdateInterval = 1.0 / 70.0;
			[self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXMagneticNorthZVertical];
		} else {
			self.motionManager = nil;
		}
	}
}

- (void)system_theme_changed {
	DisplayServerAppleEmbedded *ds = (DisplayServerAppleEmbedded *)DisplayServer::get_singleton();
	if (ds) {
		ds->emit_system_theme_changed();
	}
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	if (@available(iOS 13.0, *)) {
#if !defined(VISIONOS_ENABLED)
		[super traitCollectionDidChange:previousTraitCollection];
#endif
		[self traitCollectionDidChangeWithView:self
					   previousTraitCollection:previousTraitCollection];
	}
}

- (void)traitCollectionDidChangeWithView:(UIView *)view previousTraitCollection:(UITraitCollection *)previousTraitCollection {
	if (@available(iOS 13.0, *)) {
		if ([UITraitCollection currentTraitCollection].userInterfaceStyle != previousTraitCollection.userInterfaceStyle) {
			[self system_theme_changed];
		}
	}
}

- (void)stopRendering {
	if (!self.isActive) {
		return;
	}

	self.isActive = NO;

	print_verbose("Stop animation!");

	if (self.useCADisplayLink) {
		[self.displayLink invalidate];
		self.displayLink = nil;
	} else {
		[self.animationTimer invalidate];
		self.animationTimer = nil;
	}

	[self clearTouches];
}

- (void)startRendering {
	if (self.isActive) {
		return;
	}

	self.isActive = YES;

	print_verbose("Start animation!");

	if (self.useCADisplayLink) {
		self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(drawView)];

		// UGGames fork (ug/jigsaw-4.6.1): ask for a RANGE, not a fixed rate.
		//
		// `preferredFramesPerSecond` is deprecated since iOS 15 and, on a variable-refresh
		// (ProMotion) display, it is also actively harmful: Core Animation can only honour a
		// fixed request at a divisor of the panel rate, so the first frame the app cannot
		// sustain at 120 drops it to 60 -- and it has no mandate to climb back. A drag that
		// oscillates between 120 and 60 feels markedly worse than one pinned anywhere in
		// between. A CAFrameRateRange lets the system settle at 80, 90 or 110 and, crucially,
		// recover to 120 when the load passes.
		//
		// The floor is 2/3 of the preferred rate so the range always spans more than one
		// achievable rate (at 120 that is Apple's own 80...120 ProMotion example); at 60 and
		// below the range collapses to the old fixed request, which is what those panels do
		// anyway. iOS additionally ignores anything above 60 Hz on iPhone unless the host's
		// Info.plist carries CADisableMinimumFrameDurationOnPhone -- that is a host
		// responsibility and the engine cannot check it from here.
		if (@available(iOS 15.0, tvOS 15.0, visionOS 1.0, *)) {
			const float preferred = MAX(1.0f, self.preferredFrameRate);
			const float minimum = preferred > 60.0f ? (preferred * 2.0f / 3.0f) : preferred;
			self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(minimum, preferred, preferred);
		} else {
			GODOT_CLANG_WARNING_PUSH_AND_IGNORE("-Wdeprecated-declarations")
			self.displayLink.preferredFramesPerSecond = self.preferredFrameRate;
			GODOT_CLANG_WARNING_POP
		}

		// Setup DisplayLink in main thread
		[self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	} else {
		self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / self.preferredFrameRate) target:self selector:@selector(drawView) userInfo:nil repeats:YES];
	}
}

- (void)drawView {
	if (!self.isActive) {
		print_verbose("Draw view not active!");
		return;
	}

	if (self.useCADisplayLink) {
		// Pause the CADisplayLink to avoid recursion
		[self.displayLink setPaused:YES];

		// Process all input events
		while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, TRUE) == kCFRunLoopRunHandledSource) {
			// Continue.
		}

		// We are good to go, resume the CADisplayLink
		[self.displayLink setPaused:NO];
	}

	[self.renderingLayer startRenderDisplayLayer];

	if (!self.renderer) {
		return;
	}

	if ([self.renderer setupView:self]) {
		return;
	}

	if (self.delegate && !self.delegateDidFinishSetUp) {
		[self layoutRenderingLayer]; // Trigger DisplayServerVisionOS::resize_window after Main::start()
		self.delegateDidFinishSetUp = [self.delegate godotViewFinishedSetup:self];
		if (!_delegateDidFinishSetUp) {
			return;
		}
	}

	[self handleMotion];

#if !defined(VISIONOS_ENABLED)
	if (@available(iOS 16.0, *)) {
		CGFloat edr_headroom = UIScreen.mainScreen.currentEDRHeadroom;
		if (last_edr_headroom != edr_headroom) {
			last_edr_headroom = edr_headroom;
			if (DisplayServerAppleEmbedded::get_singleton()) {
				DisplayServerAppleEmbedded::get_singleton()->current_edr_headroom_changed();
			}
		}
	}

#endif

	[self.renderer renderOnView:self];

	[self.renderingLayer stopRenderDisplayLayer];
}

- (BOOL)canRender {
	if (self.useCADisplayLink) {
		return self.displayLink != nil;
	} else {
		return self.animationTimer != nil;
	}
}

- (void)setPreferredFrameRate:(float)preferredFrameRate {
	_preferredFrameRate = preferredFrameRate;

	if (self.canRender) {
		[self stopRendering];
		[self startRendering];
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self layoutRenderingLayer];
}

- (void)layoutRenderingLayer {
	if (self.renderingLayer) {
		self.renderingLayer.frame = self.bounds;
		[self.renderingLayer layoutDisplayLayer];

		if (DisplayServerAppleEmbedded::get_singleton()) {
			DisplayServerAppleEmbedded::get_singleton()->resize_window(self.bounds.size);
		}
	}
}

// MARK: - Input

// MARK: Touches

- (void)initTouches {
	for (int i = 0; i < max_touches; i++) {
		godot_touches[i] = nullptr;
	}
}

- (int)getTouchIDForTouch:(UITouch *)p_touch {
	int first = -1;
	for (int i = 0; i < max_touches; i++) {
		if (first == -1 && godot_touches[i] == nullptr) {
			first = i;
			continue;
		}
		if (godot_touches[i] == p_touch) {
			return i;
		}
	}

	if (first != -1) {
		godot_touches[first] = p_touch;
		return first;
	}

	return -1;
}

- (int)removeTouch:(UITouch *)p_touch {
	int remaining = 0;
	for (int i = 0; i < max_touches; i++) {
		if (godot_touches[i] == nullptr) {
			continue;
		}
		if (godot_touches[i] == p_touch) {
			godot_touches[i] = nullptr;
		} else {
			++remaining;
		}
	}
	return remaining;
}

- (void)clearTouches {
	for (int i = 0; i < max_touches; i++) {
		godot_touches[i] = nullptr;
	}
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	for (UITouch *touch in touches) {
		int tid = [self getTouchIDForTouch:touch];
		ERR_FAIL_COND(tid == -1);
		CGPoint touchPoint = [touch locationInView:self];
		DisplayServerAppleEmbedded::get_singleton()->touch_press(tid, touchPoint.x * self.contentScaleFactor, touchPoint.y * self.contentScaleFactor, true, touch.tapCount > 1);
	}
}

// UGGames fork (ug/jigsaw-4.6.1): one delivery, every sample. See docs/PATCHES.md,
// "Coalesced and predicted touches", and jigsaw-mobile docs/touch-latency.md.
//
// Stock Godot took `locationInView:` off the delivered UITouch and ignored `event` entirely.
// The digitizer samples at up to 240 Hz while UIKit delivers at the display rate, so that threw
// away roughly half of a 120 Hz drag and rather more of a 60 Hz one -- not a latency cost (the
// newest sample is still the newest) but a FIDELITY cost: any decision taken on the shape of the
// path, rather than on its endpoint, was taken on a chord.
//
// So: emit every coalesced sample, in order, then optionally emit UIKit's prediction of where
// the finger is going. Apple is explicit that the two sets must not be mixed
// (coalescedTouchesForTouch: already ends with the delivered touch, so the delivered touch is
// never sent twice) and that predictions are temporary data to be discarded on the next real
// event -- which is what `InputEventScreenDrag::predicted` lets the scene do.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	const bool use_coalesced = GLOBAL_GET_CACHED(bool, "input_devices/pointing/apple_embedded/coalesced_touches");
	const bool use_predicted = GLOBAL_GET_CACHED(bool, "input_devices/pointing/apple_embedded/predicted_touches");
	// Predict exactly one frame ahead: that is the delay this is meant to cancel, and a longer
	// lead is a bigger lie to correct when the finger decelerates. UIKit hands out more than one
	// frame of prediction; the rest is deliberately dropped.
	const NSTimeInterval prediction_lead = 1.0 / MAX(1.0f, self.preferredFrameRate);

	for (UITouch *touch in touches) {
		int tid = [self getTouchIDForTouch:touch];
		ERR_FAIL_COND(tid == -1);

		NSArray<UITouch *> *samples = nil;
		if (use_coalesced && event != nil) {
			samples = [event coalescedTouchesForTouch:touch];
		}
		if (samples.count == 0) {
			// No coalescing available (older OS, a synthetic event, or the feature turned off):
			// the delivered touch IS the whole batch, and this is byte-for-byte the old path.
			samples = @[ touch ];
		}

		// `previousLocationInView:` on the DELIVERED touch is where the finger was at the last
		// delivery, so chaining prev_point through the batch makes every `relative` a real
		// segment of the path whose sum is exactly the chord the unpatched engine reported.
		CGPoint prev_point = [touch previousLocationInView:self];
		const NSUInteger last = samples.count - 1;
		for (NSUInteger i = 0; i <= last; i++) {
			UITouch *sample = samples[i];
			CGPoint touchPoint = [sample locationInView:self];
			CGFloat alt = [sample altitudeAngle];
			CGVector azim = [sample azimuthUnitVectorInView:self];
			// Only the final sample is the current position; the earlier ones are marked
			// `coalesced` so Input's accumulator cannot fold the path back into a chord.
			DisplayServerAppleEmbedded::get_singleton()->touch_drag(tid, prev_point.x * self.contentScaleFactor, prev_point.y * self.contentScaleFactor, touchPoint.x * self.contentScaleFactor, touchPoint.y * self.contentScaleFactor, [sample force] / [sample maximumPossibleForce], Vector2(azim.dx, azim.dy) * Math::cos(alt), i != last, false);
			prev_point = touchPoint;
		}

		if (!use_predicted || event == nil) {
			continue;
		}

		NSArray<UITouch *> *predicted = [event predictedTouchesForTouch:touch];
		const NSTimeInterval horizon = touch.timestamp + prediction_lead;
		for (UITouch *sample in predicted) {
			if (sample.timestamp > horizon) {
				break;
			}
			CGPoint touchPoint = [sample locationInView:self];
			CGFloat alt = [sample altitudeAngle];
			CGVector azim = [sample azimuthUnitVectorInView:self];
			DisplayServerAppleEmbedded::get_singleton()->touch_drag(tid, prev_point.x * self.contentScaleFactor, prev_point.y * self.contentScaleFactor, touchPoint.x * self.contentScaleFactor, touchPoint.y * self.contentScaleFactor, [sample force] / [sample maximumPossibleForce], Vector2(azim.dx, azim.dy) * Math::cos(alt), false, true);
			prev_point = touchPoint;
		}
	}
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	for (UITouch *touch in touches) {
		int tid = [self getTouchIDForTouch:touch];
		ERR_FAIL_COND(tid == -1);
		[self removeTouch:touch];
		CGPoint touchPoint = [touch locationInView:self];
		DisplayServerAppleEmbedded::get_singleton()->touch_press(tid, touchPoint.x * self.contentScaleFactor, touchPoint.y * self.contentScaleFactor, false, false);
	}
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	for (UITouch *touch in touches) {
		int tid = [self getTouchIDForTouch:touch];
		ERR_FAIL_COND(tid == -1);
		DisplayServerAppleEmbedded::get_singleton()->touches_canceled(tid);
	}
	[self clearTouches];
}

// MARK: Motion

- (void)handleMotion {
	if (!self.motionManager) {
		return;
	}

	// Just using polling approach for now, we can set this up so it sends
	// data to us in intervals, might be better. See Apple reference pages
	// for more details:
	// https://developer.apple.com/reference/coremotion/cmmotionmanager?language=objc

	// Apple splits our accelerometer date into a gravity and user movement
	// component. We add them back together.
	CMAcceleration gravity = self.motionManager.deviceMotion.gravity;
	CMAcceleration acceleration = self.motionManager.deviceMotion.userAcceleration;

	// To be consistent with Android we convert the unit of measurement from g (Earth's gravity)
	// to m/s^2.
	gravity.x *= earth_gravity;
	gravity.y *= earth_gravity;
	gravity.z *= earth_gravity;
	acceleration.x *= earth_gravity;
	acceleration.y *= earth_gravity;
	acceleration.z *= earth_gravity;

	///@TODO We don't seem to be getting data here, is my device broken or
	/// is this code incorrect?
	CMMagneticField magnetic = self.motionManager.deviceMotion.magneticField.field;

	///@TODO we can access rotationRate as a CMRotationRate variable
	///(processed date) or CMGyroData (raw data), have to see what works
	/// best
	CMRotationRate rotation = self.motionManager.deviceMotion.rotationRate;

	// Adjust for screen orientation.
	// [[UIDevice currentDevice] orientation] changes even if we've fixed
	// our orientation which is not a good thing when you're trying to get
	// your user to move the screen in all directions and want consistent
	// output
	// PATCH (SwiftGodotKit embedding): when Godot is embedded inside a
	// SwiftUI host, [UIApplication.sharedApplication.delegate window] is
	// "unrecognized selector" — SwiftUI doesn't put a `window` on the
	// delegate. Use this view's own window instead.
	UIWindow *_gdtWindow = self.window;
	if (!_gdtWindow) {
		_gdtWindow = [[[[UIApplication sharedApplication] connectedScenes] anyObject] valueForKey:@"keyWindow"];
	}
#if defined(VISIONOS_ENABLED)
	UIInterfaceOrientation interfaceOrientation = _gdtWindow.windowScene.effectiveGeometry.interfaceOrientation;
#else
	UIInterfaceOrientation interfaceOrientation = _gdtWindow.windowScene.interfaceOrientation;
#endif

	switch (interfaceOrientation) {
		case UIInterfaceOrientationLandscapeLeft: {
			DisplayServerAppleEmbedded::get_singleton()->update_gravity(Vector3(gravity.x, gravity.y, gravity.z).rotated(Vector3(0, 0, 1), -Math::PI * 0.5));
			DisplayServerAppleEmbedded::get_singleton()->update_accelerometer(Vector3(acceleration.x + gravity.x, acceleration.y + gravity.y, acceleration.z + gravity.z).rotated(Vector3(0, 0, 1), -Math::PI * 0.5));
			DisplayServerAppleEmbedded::get_singleton()->update_magnetometer(Vector3(magnetic.x, magnetic.y, magnetic.z).rotated(Vector3(0, 0, 1), -Math::PI * 0.5));
			DisplayServerAppleEmbedded::get_singleton()->update_gyroscope(Vector3(rotation.x, rotation.y, rotation.z).rotated(Vector3(0, 0, 1), -Math::PI * 0.5));
		} break;
		case UIInterfaceOrientationLandscapeRight: {
			DisplayServerAppleEmbedded::get_singleton()->update_gravity(Vector3(gravity.x, gravity.y, gravity.z).rotated(Vector3(0, 0, 1), Math::PI * 0.5));
			DisplayServerAppleEmbedded::get_singleton()->update_accelerometer(Vector3(acceleration.x + gravity.x, acceleration.y + gravity.y, acceleration.z + gravity.z).rotated(Vector3(0, 0, 1), Math::PI * 0.5));
			DisplayServerAppleEmbedded::get_singleton()->update_magnetometer(Vector3(magnetic.x, magnetic.y, magnetic.z).rotated(Vector3(0, 0, 1), Math::PI * 0.5));
			DisplayServerAppleEmbedded::get_singleton()->update_gyroscope(Vector3(rotation.x, rotation.y, rotation.z).rotated(Vector3(0, 0, 1), Math::PI * 0.5));
		} break;
		case UIInterfaceOrientationPortraitUpsideDown: {
			DisplayServerAppleEmbedded::get_singleton()->update_gravity(Vector3(gravity.x, gravity.y, gravity.z).rotated(Vector3(0, 0, 1), Math::PI));
			DisplayServerAppleEmbedded::get_singleton()->update_accelerometer(Vector3(acceleration.x + gravity.x, acceleration.y + gravity.y, acceleration.z + gravity.z).rotated(Vector3(0, 0, 1), Math::PI));
			DisplayServerAppleEmbedded::get_singleton()->update_magnetometer(Vector3(magnetic.x, magnetic.y, magnetic.z).rotated(Vector3(0, 0, 1), Math::PI));
			DisplayServerAppleEmbedded::get_singleton()->update_gyroscope(Vector3(rotation.x, rotation.y, rotation.z).rotated(Vector3(0, 0, 1), Math::PI));
		} break;
		default: { // assume portrait
			DisplayServerAppleEmbedded::get_singleton()->update_gravity(Vector3(gravity.x, gravity.y, gravity.z));
			DisplayServerAppleEmbedded::get_singleton()->update_accelerometer(Vector3(acceleration.x + gravity.x, acceleration.y + gravity.y, acceleration.z + gravity.z));
			DisplayServerAppleEmbedded::get_singleton()->update_magnetometer(Vector3(magnetic.x, magnetic.y, magnetic.z));
			DisplayServerAppleEmbedded::get_singleton()->update_gyroscope(Vector3(rotation.x, rotation.y, rotation.z));
		} break;
	}
}

@end
