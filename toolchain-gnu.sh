#!/bin/sh
# Fetches the bootlin mips32el--glibc cross toolchain (same one used by
# libsdk-py for the mipsel-gnu target on the actual device).
set -e

GNU_TOOLCHAIN=mips32el--glibc--stable-2018.11-1
GNU_TOOLCHAIN_URL="https://toolchains.bootlin.com/downloads/releases/toolchains/mips32el/tarballs/${GNU_TOOLCHAIN}.tar.bz2"

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN_DIR="$ROOT/toolchain-gnu"
ARCHIVE="$TOOLCHAIN_DIR/${GNU_TOOLCHAIN}.tar.bz2"

mkdir -p "$TOOLCHAIN_DIR"

if [ ! -d "$TOOLCHAIN_DIR/$GNU_TOOLCHAIN" ]; then
	if [ ! -f "$ARCHIVE" ]; then
		curl -L -o "$ARCHIVE" "$GNU_TOOLCHAIN_URL"
	fi
	tar xjf "$ARCHIVE" -C "$TOOLCHAIN_DIR"
fi

echo "$TOOLCHAIN_DIR/$GNU_TOOLCHAIN/bin"
