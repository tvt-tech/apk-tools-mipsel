#!/bin/bash
# Helper functions used by .github/workflows/build-ci.yml. Meant to be
# sourced, then call the ci_* functions individually.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_MUSL="$ROOT/build-musl/src/apk"
BIN_GNU="$ROOT/build-gnu/src/apk"

ci_setup() {
	sudo apt-get update
	sudo apt-get install -y ninja-build cmake qemu-user patchelf
	python3 -m pip install --user meson
	echo "$HOME/.local/bin" >> "$GITHUB_PATH"
}

# --- musl variant: fully static, verifiable end-to-end with qemu-user ---

ci_verify_static_musl() {
	echo "file:"
	file "$BIN_MUSL"
	echo "ldd:"
	if ldd "$BIN_MUSL" 2>&1 | grep -qi "not a dynamic executable\|не є динамічним"; then
		echo "OK: statically linked"
	else
		ldd "$BIN_MUSL" || true
		echo "ERROR: musl binary is not statically linked" >&2
		exit 1
	fi
}

ci_run_smoke_test_musl() {
	qemu-mipsel "$BIN_MUSL" --version
	qemu-mipsel "$BIN_MUSL" --print-arch
}

# Extracts "apk-tools X.Y.Z, compiled for mipsel." -> X.Y.Z, renames the
# binary to build-musl/apk-mipsel-X.Y.Z and exports apk_version/apk_arch.
ci_extract_version_musl() {
	local version arch renamed
	version=$(qemu-mipsel "$BIN_MUSL" --version | awk '{print $2}' | tr -d ',')
	arch=$(qemu-mipsel "$BIN_MUSL" --print-arch)
	renamed="$ROOT/build-musl/apk-${arch}-${version}"
	cp "$BIN_MUSL" "$renamed"
	echo "apk_version=$version"
	echo "apk_arch=$arch"
	echo "apk_path=$renamed"
	if [ -n "$GITHUB_OUTPUT" ]; then
		{
			echo "apk_version=$version"
			echo "apk_arch=$arch"
			echo "apk_path=$renamed"
		} >> "$GITHUB_OUTPUT"
	fi
}

# --- gnu variant: dynamically linked + device-patched, can only be
# structurally verified here (it needs the real camera's own libc/ld.so
# to actually run; build-mipsel-gnu.sh already smoke-tests the unpatched
# binary against the toolchain's own sysroot before patching it) ---

ci_verify_patched_gnu() {
	echo "file:"
	file "$BIN_GNU"
	echo "interpreter:"
	patchelf --print-interpreter "$BIN_GNU"
	[ "$(patchelf --print-interpreter "$BIN_GNU")" = "/lib/ld-linux-mipsn8.so.1" ] \
		|| { echo "ERROR: unexpected interpreter" >&2; exit 1; }
	echo "rpath:"
	patchelf --print-rpath "$BIN_GNU"
	[ "$(patchelf --print-rpath "$BIN_GNU")" = "/lib:/tmp/libsdk" ] \
		|| { echo "ERROR: unexpected rpath" >&2; exit 1; }
	echo "OK: interpreter and rpath match the target device"
}

# Reads apk_version/apk_arch captured by build-mipsel-gnu.sh's pre-patch
# smoke test (the final patched binary's interpreter no longer matches
# this host, so it can't be re-run here), renames the artifact to
# build-gnu/apk-mipsel-gnu-X.Y.Z and exports apk_version/apk_arch.
ci_extract_version_gnu() {
	local version arch renamed
	# shellcheck disable=SC1091
	source "$ROOT/build-gnu/version.env"
	version="$apk_version"
	arch="${apk_arch}-gnu"
	renamed="$ROOT/build-gnu/apk-${arch}-${version}"
	cp "$BIN_GNU" "$renamed"
	echo "apk_version=$version"
	echo "apk_arch=$arch"
	echo "apk_path=$renamed"
	if [ -n "$GITHUB_OUTPUT" ]; then
		{
			echo "apk_version=$version"
			echo "apk_arch=$arch"
			echo "apk_path=$renamed"
		} >> "$GITHUB_OUTPUT"
	fi
}
