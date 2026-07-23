#!/bin/sh
# Cross-builds the static dependencies apk-tools needs for mipsel-musl:
# zlib and mbedTLS (crypto_backend=mbedtls), both pinned as git submodules
# under ./deps. Built out-of-tree under ./deps-build-musl (submodules stay
# pristine) and installed under ./deps-musl-prefix.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN_BIN="$ROOT/toolchain/mipsel-linux-musl-cross/bin"
DEPS_PREFIX="$ROOT/deps-musl-prefix"
DEPS_BUILD="$ROOT/deps-build-musl"
CMAKE_TOOLCHAIN_FILE="$ROOT/cmake/mipsel-musl-toolchain.cmake"

[ -d "$TOOLCHAIN_BIN" ] || { echo "Toolchain not found, run toolchain.sh first" >&2; exit 1; }

if [ ! -f "$ROOT/deps/zlib/configure" ] || [ ! -f "$ROOT/deps/mbedtls/CMakeLists.txt" ]; then
	git -C "$ROOT" submodule update --init --recursive deps/zlib deps/mbedtls
fi

PATH="$TOOLCHAIN_BIN:$PATH"
export PATH
export CC=mipsel-linux-musl-gcc
export AR=mipsel-linux-musl-ar
export RANLIB=mipsel-linux-musl-ranlib

mkdir -p "$DEPS_PREFIX" "$DEPS_BUILD"

# --- zlib (its ./configure only supports in-tree builds, so build from a
# throwaway copy instead of touching the deps/zlib submodule checkout) ---
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

# --- mbedTLS (static, no programs/tests; plain CMake out-of-tree build) ---
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
