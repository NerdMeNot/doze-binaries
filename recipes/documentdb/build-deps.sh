#!/usr/bin/env bash
# build-deps.sh <deps_prefix>
#
# Build the two DocumentDB build-dependencies that aren't reliable system/brew
# packages, into <deps_prefix>, and emit pkg-config files for them:
#   - Intel Decimal Floating-Point Math Library (static libbid)  — Ubuntu's
#     arch-patched source (handles Darwin + aarch64; the upstream Intel makefile
#     aborts on arm64). Provides pkg-config `intelmathlib`.
#   - libbson 1.28.0 (static)  — DocumentDB needs the 1.x BSON API; Homebrew only
#     ships libbson 2.x. Provides pkg-config `libbson-static-1.0`.
#
# Both are linked statically into pg_documentdb_core, so they leave no runtime
# dependency to bundle. Verified building cleanly on macOS arm64 and Linux.
set -euo pipefail

DEPS="$(cd "$1" && pwd)"
INTEL_VER="applied/2.0u3-1"
LIBBSON_VER="1.28.0"
work="$(mktemp -d)"
ncpu="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
mkdir -p "$DEPS/lib/pkgconfig"

echo "── Intel decimal math lib (static) ──"
intel="$work/intelmath"
mkdir -p "$intel" && cd "$intel"
git init -q
git remote add origin https://git.launchpad.net/ubuntu/+source/intelrdfpmath
git fetch -q --depth 1 origin "$INTEL_VER"
git checkout -q FETCH_HEAD
# Ubuntu's makefile recognizes Darwin + aarch64; the only Linux-ism is /proc.
make -C LIBRARY -sj"$ncpu" _CFLAGS_OPT=-fPIC CC=cc \
  CALL_BY_REF=0 GLOBAL_RND=0 GLOBAL_FLAGS=0 UNCHANGED_BINARY_FLAGS=0
mkdir -p "$DEPS/intelmath"
cp -R "$intel/LIBRARY" "$DEPS/intelmath/LIBRARY"
cat > "$DEPS/lib/pkgconfig/intelmathlib.pc" <<EOF
prefix=$DEPS/intelmath
libdir=\${prefix}/LIBRARY
includedir=\${prefix}/LIBRARY/src
Name: intelmathlib
Description: Intel Decimal Floating point math library
Version: 2.0u3
Cflags: -I\${includedir}
Libs: -L\${libdir} -lbid
EOF

echo "── libbson $LIBBSON_VER (static) ──"
cd "$work"
curl -fsSL "https://github.com/mongodb/mongo-c-driver/releases/download/${LIBBSON_VER}/mongo-c-driver-${LIBBSON_VER}.tar.gz" -o mcd.tgz
tar xzf mcd.tgz
cd "mongo-c-driver-${LIBBSON_VER}"
# Its CMake files predate CMake 4 (which dropped CMP0042 OLD). Static build
# doesn't need that Apple install-name policy; neutralize it and allow old
# policy versions. Use a build dir name that doesn't collide with src/build/.
grep -rl "CMP0042 OLD" --include=CMakeLists.txt . 2>/dev/null | while read -r f; do
  sed -i.bak 's/cmake_policy *(SET CMP0042 OLD)/cmake_policy(SET CMP0042 NEW)/' "$f" && rm -f "$f.bak"
done
cmake -S . -B _bld \
  -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DENABLE_MONGOC=OFF -DENABLE_STATIC=ON -DENABLE_SHARED=OFF \
  -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DCMAKE_C_FLAGS=-fPIC
cmake --build _bld --target install -j"$ncpu"

test -f "$DEPS/lib/libbid.a" -o -f "$DEPS/intelmath/LIBRARY/libbid.a"
test -f "$DEPS/lib/pkgconfig/libbson-static-1.0.pc"
rm -rf "$work"
echo "deps built into $DEPS"
