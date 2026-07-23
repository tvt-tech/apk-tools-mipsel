#!/bin/sh
# Orchestrates a fully static apk-tools build for mipsel (musl libc):
#   1. fetch the mipsel-linux-musl-cross toolchain (toolchain.sh)
#   2. cross-build zlib + mbedTLS statically (deps.sh)
#   3. generate a meson cross-file pointing at both
#   4. meson setup + ninja build of apk-tools, statically linked
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN_BIN="$ROOT/toolchain/mipsel-linux-musl-cross/bin"
DEPS_PREFIX="$ROOT/deps-musl-prefix"
CROSS_FILE="$ROOT/meson/mipsel-musl.cross"
BUILD_DIR="$ROOT/build-musl"

"$ROOT/toolchain.sh"
"$ROOT/deps.sh"

sed "s|@DEPS_PREFIX@|$DEPS_PREFIX|g" "$ROOT/meson/mipsel-musl.cross.in" > "$CROSS_FILE"

PATH="$TOOLCHAIN_BIN:$PATH"
export PATH

meson setup --wipe \
	--cross-file "$CROSS_FILE" \
	-Dprefix=/ \
	-Dcrypto_backend=mbedtls \
	-Durl_backend=wget \
	-Dzstd=disabled \
	-Dlua=disabled \
	-Dpython=disabled \
	-Ddocs=disabled \
	-Dtests=disabled \
	-Dc_link_args=-static \
	-Dprefer_static=true \
	-Ddefault_library=static \
	"$BUILD_DIR" "$ROOT/deps/apk-tools"

ninja -C "$BUILD_DIR" src/apk

echo "Built: $BUILD_DIR/src/apk"
file "$BUILD_DIR/src/apk"
