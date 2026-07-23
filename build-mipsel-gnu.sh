#!/bin/sh
# Builds apk-tools for the specific mipsel camera device also targeted by
# libsdk-py: glibc (bootlin mips32el--glibc--stable-2018.11-1) dynamically
# linked against the device's own libc, with zlib + mbedTLS statically
# embedded, then patched to match that device's non-standard dynamic
# linker (same treatment as libsdk-py's `mips-gnu` Makefile target):
#   - EF_MIPS_NAN2008 / .MIPS.abiflags patch (FPU ABI)
#   - RPATH -> /lib:/tmp/libsdk
#   - interpreter -> /lib/ld-linux-mipsn8.so.1
#   - NEEDED ld.so.1 -> ld-linux-mipsn8.so.1
set -e

RPATH="/lib:/tmp/libsdk"
INTERPRETER="/lib/ld-linux-mipsn8.so.1"

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN_BIN="$ROOT/toolchain-gnu/mips32el--glibc--stable-2018.11-1/bin"
DEPS_PREFIX="$ROOT/deps-gnu-prefix"
CROSS_FILE="$ROOT/meson/mipsel-gnu.cross"
BUILD_DIR="$ROOT/build-gnu"

"$ROOT/toolchain-gnu.sh"
"$ROOT/deps-gnu.sh"

sed "s|@DEPS_PREFIX@|$DEPS_PREFIX|g" "$ROOT/meson/mipsel-gnu.cross.in" > "$CROSS_FILE"

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
	"$BUILD_DIR" "$ROOT/deps/apk-tools"

ninja -C "$BUILD_DIR" src/apk

BIN="$BUILD_DIR/src/apk"
SYSROOT="$TOOLCHAIN_BIN/../mipsel-buildroot-linux-gnu/sysroot"

echo "==> Smoke-testing the unpatched binary against the toolchain's own sysroot..."
echo "    (its ld.so.1/libc.so.6 differ from the real device, but this still"
echo "    proves the cross-build itself links and runs correctly)"
VERSION=$(qemu-mipsel -L "$SYSROOT" "$BIN" --version | awk '{print $2}' | tr -d ',')
ARCH=$(qemu-mipsel -L "$SYSROOT" "$BIN" --print-arch)
echo "apk-tools $VERSION, compiled for $ARCH."
{
	echo "apk_version=$VERSION"
	echo "apk_arch=$ARCH"
} > "$BUILD_DIR/version.env"

echo "==> Patching nan2008..."
python3 "$ROOT/scripts/patch_nan2008.py" "$BIN"

# Strip *before* patchelf: patchelf rewrites program headers (e.g. to grow
# the dynamic string table for the new RPATH) and running strip afterwards
# corrupts that layout (".dynstr outside segment" -> "Invalid argument" at
# exec() on the device).
echo "==> Stripping..."
mipsel-linux-strip --strip-all "$BIN"

echo "==> Patching rpath + linker..."
patchelf --set-rpath "$RPATH" "$BIN"
patchelf --set-interpreter "$INTERPRETER" "$BIN"
patchelf --replace-needed ld.so.1 ld-linux-mipsn8.so.1 "$BIN"

echo "Built: $BIN ($(wc -c < "$BIN") bytes)"
file "$BIN"
