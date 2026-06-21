#!/usr/bin/env bash
# bundle-macos-deps.sh <install_dir> <brew_prefix>
#
# Make a macOS build relocatable: copy every Homebrew dylib the binaries link
# into <install_dir>/lib, rewrite install names to @loader_path/../lib, and
# ad-hoc codesign. Adapted from theseus-rs/postgresql-binaries (MIT).
#
# No pipefail: the `otool | grep <brew> | …` pipelines below legitimately match
# nothing for binaries with no Homebrew dependencies, and that must not abort.
set -eu

INSTALL_DIR="$1"
BREW_PREFIX="$2"
[ -n "$INSTALL_DIR" ] && [ -n "$BREW_PREFIX" ] || { echo "usage: $0 <install_dir> <brew_prefix>"; exit 1; }
mkdir -p "$INSTALL_DIR/lib"

realpath_of() { python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }

bundle_lib() {
  local lib_path="$1" lib_name
  lib_name="$(basename "$lib_path")"
  [ -f "$INSTALL_DIR/lib/$lib_name" ] && return
  echo "  bundling $lib_name"
  cp "$lib_path" "$INSTALL_DIR/lib/"
  chmod +w "$INSTALL_DIR/lib/$lib_name"
  install_name_tool -id "@loader_path/../lib/$lib_name" "$INSTALL_DIR/lib/$lib_name"
  otool -L "$INSTALL_DIR/lib/$lib_name" | grep "$BREW_PREFIX" | awk '{print $1}' | while read -r dep; do
    local dep_real dep_name
    dep_real="$(realpath_of "$dep")"; dep_name="$(basename "$dep")"
    bundle_lib "$dep_real"
    install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$INSTALL_DIR/lib/$lib_name"
  done
}

fix_macho() {
  local bin="$1"
  file "$bin" | grep -q "Mach-O" || return 0
  otool -L "$bin" | grep "$BREW_PREFIX" | awk '{print $1}' | while read -r dep; do
    local dep_real dep_name
    dep_real="$(realpath_of "$dep")"; dep_name="$(basename "$dep")"
    bundle_lib "$dep_real"
    install_name_tool -change "$dep" "@loader_path/../lib/$dep_name" "$bin"
  done
  otool -L "$bin" | grep "$INSTALL_DIR" | awk '{print $1}' | while read -r dep; do
    install_name_tool -change "$dep" "@loader_path/../lib/$(basename "$dep")" "$bin"
  done
}

find "$INSTALL_DIR/bin" -type f 2>/dev/null | while read -r b; do fix_macho "$b"; done
find "$INSTALL_DIR/lib" -maxdepth 1 -name "*.dylib" 2>/dev/null | while read -r l; do
  [ -L "$l" ] || fix_macho "$l"
done

# Ad-hoc sign everything we touched (required on Apple Silicon).
find "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
  if file "$f" | grep -q "Mach-O"; then
    chmod +w "$f"; codesign --force --sign - "$f" 2>/dev/null || true
  fi
done

echo "bundled macOS deps into $INSTALL_DIR/lib"
