#!/usr/bin/env bash
# bundle-linux-deps.sh <prefix>
#
# Make a built tree relocatable: copy every non-system shared library it links
# into <prefix>/lib and rewrite each ELF's rpath to $ORIGIN/../lib. Core libc /
# toolchain libraries are left to the target system (we link those dynamically,
# so the binaries need a glibc at least as new as the build host's — see README).
set -euo pipefail

prefix="$1"
mkdir -p "$prefix/lib"
command -v patchelf >/dev/null || { echo "patchelf is required"; exit 1; }

is_system() {
  case "$1" in
    libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*|linux-vdso*|\
    libgcc_s.so*|libstdc++.so*|libresolv.so*|libutil.so*) return 0 ;;
  esac
  return 1
}

collect() {
  local f="$1"
  ldd "$f" 2>/dev/null | awk '/=>/ {print $1" "$3}' | while read -r name path; do
    [ -z "$path" ] || [ "$path" = "not" ] && continue
    is_system "$name" && continue
    if [ ! -e "$prefix/lib/$name" ] && [ -e "$path" ]; then
      cp -L "$path" "$prefix/lib/$name"
      chmod +w "$prefix/lib/$name"
    fi
  done
}

# Every ELF in bin/ and ANYWHERE under lib/ — including the extension modules in
# lib/postgresql/, whose build-time deps (libpq, geos, proj, sibling documentdb
# libs) must be bundled and whose rpath must be relocated too.
elf_files() { find "$prefix/bin" "$prefix/lib" -type f 2>/dev/null; }

# Two passes so transitive deps of freshly bundled libs are also captured.
for pass in 1 2; do
  while IFS= read -r f; do
    file "$f" | grep -q ELF || continue
    collect "$f"
  done < <(elf_files)
done

# rpath_for echoes a depth-aware rpath for an ELF: $ORIGIN (so a sibling
# extension in the same dir resolves) plus the relative hop up to <prefix>/lib.
# A file in bin/ or lib/ is one level under the tree root ($ORIGIN/../lib); an
# extension in lib/postgresql/ is two ($ORIGIN/../../lib) — a flat $ORIGIN/../lib
# would resolve to lib/lib from there and find nothing.
rpath_for() {
  local dir rel ups part
  dir="$(cd "$(dirname "$1")" && pwd)"
  rel="${dir#"$prefix"/}"
  ups=""
  local IFS=/
  for part in $rel; do ups="../$ups"; done
  echo "\$ORIGIN:\$ORIGIN/${ups}lib"
}

while IFS= read -r f; do
  file "$f" | grep -q ELF || continue
  patchelf --set-rpath "$(rpath_for "$f")" "$f" 2>/dev/null || true
done < <(elf_files)

echo "bundled linux deps into $prefix/lib"
