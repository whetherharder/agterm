#!/usr/bin/env bash
# Build libghostty (GhosttyKit.xcframework) and ghostty resources from upstream ghostty source.
#
# We build from source rather than downloading a prebuilt artifact so the toolchain is fully
# self-owned: the only inputs are upstream ghostty-org/ghostty at a pinned SHA, zig, and Xcode's
# Metal Toolchain. No third-party fork, no daily-build release that can be pruned.
#
# GHOSTTY_REV is a plain pin for reproducibility, not a workaround. It was held at a 2026-04-30
# pre-regression commit while later builds blanked the scrollback on a font-size increase; that is
# fixed upstream and re-verified by hand before this bump. Re-test the font-increase case when moving
# it, and check `minimum_zig_version` in build.zig.zon against ZIG_FORMULA.
#
# One-time cost: the build (a few minutes, plus a Metal Toolchain download on first run) is skipped
# whenever the staged artifacts match the current rev. Presence alone is not enough — an xcframework
# built from a different rev is indistinguishable from a current one, so the stamp, not the directory,
# is what says a rebuild can be skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

GHOSTTY_REPO="https://github.com/ghostty-org/ghostty"
GHOSTTY_REV="683d8db643b95cf229bfb5fe9fab9ae677920343"  # 2026-08-25
# ghostty pins minimum_zig_version 0.16.0. Name the MINOR LINE, not `zig`: that one rolls, so a fresh
# build once 0.17 is current would compile a fixed GHOSTTY_REV with a compiler it never supported. Today
# `zig@0.16` is still an alias for `zig`, so this buys nothing yet — it claims the name Homebrew uses when
# it cuts the real versioned formula, as it already has for zig@0.15 and zig@0.14.
ZIG_FORMULA="zig@0.16"  # resolved by prefix, so an unlinked keg works
XCFRAMEWORK_DIR="GhosttyKit.xcframework"
# `native` builds the one slice the app then links, on Apple Silicon and Intel alike. AGTERM_UNIVERSAL=1
# builds both, which roughly doubles this one-time cost and is only worth it to ship a single bundle.
if [[ "${AGTERM_UNIVERSAL:-0}" == "1" ]]; then
  XCFRAMEWORK_TARGET=universal
  WANT_ARCHS=(arm64 x86_64)
else
  XCFRAMEWORK_TARGET=native
  WANT_ARCHS=("$(uname -m)")
fi
# terminfo/ is the marker: it must extract as a SIBLING of ghostty/ so libghostty's
# TERMINFO=dirname(GHOSTTY_RESOURCES_DIR)/terminfo derivation resolves xterm-ghostty.
RESOURCES_MARKER="agterm/Resources/terminfo"
STAMP_FILE=".ghostty-build-stamp"

# stage agterm's own bundled theme(s) from the committed source into the (gitignored,
# setup-regenerated) ghostty themes dir. idempotent and called on both the cached and the
# fresh-build path so the theme survives a themes-dir wipe and shows in the Appearance picker.
stage_custom_themes() {
  local dst="agterm/Resources/ghostty/themes"
  [[ -d "$dst" ]] || return 0
  cp agterm/Resources/custom-themes/* "$dst/"
}

need_xc=true
need_res=true
[[ -d "$XCFRAMEWORK_DIR" ]] && need_xc=false
[[ -d "$RESOURCES_MARKER" ]] && need_res=false

# a stale stamp restages BOTH: they come out of one build, and an artifact built from another revision
# cannot be told apart from a current one.
if [[ ! -f "$STAMP_FILE" || "$(cat "$STAMP_FILE")" != "$GHOSTTY_REV" ]]; then
  need_xc=true
  need_res=true
fi

# the stamp records the revision, not the slices, so a current-rev xcframework can still be the wrong
# shape: a checkout carried between Macs, or one switching to a universal build, has artifacts that
# simply lack the arch the app must link. The resources are arch-free and stay as staged.
if ! $need_xc; then
  staged="$(for lib in "$XCFRAMEWORK_DIR"/macos-*/*.a; do lipo -archs "$lib" 2>/dev/null; done | tr ' ' '\n' | sort -u)"
  # an unreadable staging leaves the stamp in charge: unconditionally rebuilding on a result this
  # check cannot interpret would rebuild libghostty on every single invocation.
  if [[ -n "$staged" ]]; then
    for arch in "${WANT_ARCHS[@]}"; do
      grep -qx "$arch" <<<"$staged" || need_xc=true
    done
  fi
fi

if ! $need_xc && ! $need_res; then
  echo "GhosttyKit and resources already present"
  stage_custom_themes
  exit 0
fi

# resolved through the keg prefix rather than PATH, so a machine still linking an older zig for another
# project builds with the right one and keeps its own `zig` untouched.
ZIG="$(brew --prefix "$ZIG_FORMULA" 2>/dev/null || true)/bin/zig"
if [[ ! -x "$ZIG" ]]; then
  echo "installing $ZIG_FORMULA..."
  brew install "$ZIG_FORMULA"
  ZIG="$(brew --prefix "$ZIG_FORMULA")/bin/zig"
fi

# Metal Toolchain — the xcframework build compiles ghostty's Metal shaders
if ! xcrun metal --version >/dev/null 2>&1; then
  echo "downloading Xcode Metal Toolchain (one-time)..."
  xcodebuild -downloadComponent MetalToolchain
fi

# fetch ghostty at the pinned commit (shallow, single commit, no submodules — not needed here)
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
echo "fetching ghostty $GHOSTTY_REV..."
git init -q "$BUILD_DIR"
git -C "$BUILD_DIR" remote add origin "$GHOSTTY_REPO"
git -C "$BUILD_DIR" fetch -q --depth 1 origin "$GHOSTTY_REV"
git -C "$BUILD_DIR" -c advice.detachedHead=false checkout -q FETCH_HEAD

echo "building GhosttyKit.xcframework ($XCFRAMEWORK_TARGET) with zig (a few minutes)..."
( cd "$BUILD_DIR" && "$ZIG" build -Doptimize=ReleaseFast -Demit-xcframework=true -Dxcframework-target="$XCFRAMEWORK_TARGET" -Demit-macos-app=false )

if $need_xc; then
  echo "staging GhosttyKit.xcframework..."
  rm -rf "$XCFRAMEWORK_DIR"
  cp -R "$BUILD_DIR/macos/GhosttyKit.xcframework" "$XCFRAMEWORK_DIR"
fi

if $need_res; then
  echo "staging ghostty resources..."
  rm -rf agterm/Resources/ghostty agterm/Resources/terminfo
  mkdir -p agterm/Resources/ghostty
  cp -R "$BUILD_DIR/zig-out/share/ghostty/shell-integration" agterm/Resources/ghostty/
  cp -R "$BUILD_DIR/zig-out/share/ghostty/themes" agterm/Resources/ghostty/
  cp -R "$BUILD_DIR/zig-out/share/terminfo" agterm/Resources/terminfo
fi

stage_custom_themes
printf '%s\n' "$GHOSTTY_REV" > "$STAMP_FILE"
echo "setup complete"
