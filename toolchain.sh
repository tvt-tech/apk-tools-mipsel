#!/bin/sh
# Fetches the mipsel-linux-musl-cross standalone toolchain from musl.cc.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN_DIR="$ROOT/toolchain"
ARCHIVE="$TOOLCHAIN_DIR/mipsel-linux-musl-cross.tgz"

mkdir -p "$TOOLCHAIN_DIR"

if [ ! -d "$TOOLCHAIN_DIR/mipsel-linux-musl-cross" ]; then
	if [ ! -f "$ARCHIVE" ]; then
		curl -L -o "$ARCHIVE" https://musl.cc/mipsel-linux-musl-cross.tgz
	fi
	tar xzf "$ARCHIVE" -C "$TOOLCHAIN_DIR"
fi

echo "$TOOLCHAIN_DIR/mipsel-linux-musl-cross/bin"
