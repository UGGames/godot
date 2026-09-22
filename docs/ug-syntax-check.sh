#!/bin/bash
# Syntax-only check of the files this fork's patches touch, with the flags
# platform/ios/detect.py + platform/ios/SCsub apply to a
#   scons platform=ios arch=arm64 target=template_release vulkan=no metal=yes
# build. Generated headers come from an overlay (they are build products and
# are not in the checkout; docs/PATCHES.md says how to make the overlay).
#
#   docs/ug-syntax-check.sh <gen-header-overlay> [extra clang flags]
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$1"; shift
EXTRA=(); if [ $# -gt 0 ]; then EXTRA=("$@"); fi

COMMON=(
  -fsyntax-only -arch arm64 -miphoneos-version-min=14.0
  -fobjc-arc -fmessage-length=0
  -std=gnu++17 -fno-exceptions
  -fmodules -fcxx-modules -Wno-ambiguous-macro
  -DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED
  -DMETAL_ENABLED -DRD_ENABLED -DTHREADS_ENABLED -DNDEBUG
  -I"$GEN" -I"$REPO" -I"$REPO/platform/ios" -I"$REPO/thirdparty/misc"
  $(find "$GEN" -type d | sed 's/^/-I/' | tr '\n' ' ')
  -I"$REPO/thirdparty/zlib" -I"$REPO/thirdparty/zstd"
)

rc=0
for f in "$REPO/platform/ios/libgodot_ios.mm" "$REPO/main/main.cpp" "$REPO/drivers/apple_embedded/os_apple_embedded.mm"; do
  echo "### $f ${EXTRA[*]:-}"
  xcrun --sdk iphoneos clang++ "${COMMON[@]}" "${EXTRA[@]+"${EXTRA[@]}"}" "$f" || rc=1
done
exit $rc
