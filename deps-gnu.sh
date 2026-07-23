#!/bin/sh
# Cross-builds static zlib + mbedTLS for the mipsel-gnu (glibc, bootlin
# toolchain) target. glibc itself stays dynamic (provided by the device);
# only these two libraries get statically embedded into the apk binary.
# Built out-of-tree under ./deps-build-gnu, installed under ./deps-gnu-prefix.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN_BIN="$ROOT/toolchain-gnu/mips32el--glibc--stable-2018.11-1/bin"
DEPS_PREFIX="$ROOT/deps-gnu-prefix"
DEPS_BUILD="$ROOT/deps-build-gnu"
CMAKE_TOOLCHAIN_FILE="$ROOT/cmake/mips32el-gnu-toolchain.cmake"

[ -d "$TOOLCHAIN_BIN" ] || { echo "GNU toolchain not found, run toolchain-gnu.sh first" >&2; exit 1; }

if [ ! -f "$ROOT/deps/zlib/configure" ] || [ ! -f "$ROOT/deps/mbedtls/CMakeLists.txt" ]; then
	git -C "$ROOT" submodule update --init --recursive deps/zlib deps/mbedtls
fi

PATH="$TOOLCHAIN_BIN:$PATH"
export PATH
export CC=mipsel-linux-gcc
export AR=mipsel-linux-ar
export RANLIB=mipsel-linux-ranlib

mkdir -p "$DEPS_PREFIX" "$DEPS_BUILD"

# --- zlib (throwaway copy, its ./configure only supports in-tree builds) ---
if [ ! -f "$DEPS_PREFIX/lib/libz.a" ]; then
	rm -rf "$DEPS_BUILD/zlib"
	rsync -a --exclude='.git' "$ROOT/deps/zlib/" "$DEPS_BUILD/zlib/"
	(
		cd "$DEPS_BUILD/zlib"
		./configure --prefix="$DEPS_PREFIX" --static
		make -j"$(nproc)"
		make install
	)
fi

# --- mbedTLS (static, no programs/tests) ---
if [ ! -f "$DEPS_PREFIX/lib/libmbedcrypto.a" ]; then
	rm -rf "$DEPS_BUILD/mbedtls"
	mkdir -p "$DEPS_BUILD/mbedtls"
	cmake -S "$ROOT/deps/mbedtls" -B "$DEPS_BUILD/mbedtls" \
		-DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
		-DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
		-DCMAKE_BUILD_TYPE=Release \
		-DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
		-DUSE_STATIC_MBEDTLS_LIBRARY=ON \
		-DENABLE_PROGRAMS=OFF \
		-DENABLE_TESTING=OFF \
		-DMBEDTLS_FATAL_WARNINGS=OFF
	cmake --build "$DEPS_BUILD/mbedtls" -j"$(nproc)"
	cmake --install "$DEPS_BUILD/mbedtls"
fi

echo "$DEPS_PREFIX"
