#!/usr/bin/env bash
# xcodebuild settings naming what to build for, sourced by the Release build scripts.
#
# The default is the Mac doing the building — Apple Silicon or Intel — which is the only slice
# scripts/setup.sh stages into GhosttyKit.xcframework. AGTERM_UNIVERSAL=1 asks setup.sh for both
# slices and this for the matching ARCHS, producing one bundle that runs on either.
ARCH_SETTINGS=(ONLY_ACTIVE_ARCH=YES)
if [[ "${AGTERM_UNIVERSAL:-0}" == "1" ]]; then
  ARCH_SETTINGS=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi
