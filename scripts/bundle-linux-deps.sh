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

elf_files() { find "$prefix/bin" "$prefix/lib" -maxdepth 1 -type f 2>/dev/null; }

# Two passes so transitive deps of freshly bundled libs are also captured.
for pass in 1 2; do
  while IFS= read -r f; do
    file "$f" | grep -q ELF || continue
    collect "$f"
  done < <(elf_files)
done

while IFS= read -r f; do
  file "$f" | grep -q ELF || continue
  patchelf --set-rpath '$ORIGIN/../lib' "$f" 2>/dev/null || true
done < <(elf_files)

echo "bundled linux deps into $prefix/lib"
