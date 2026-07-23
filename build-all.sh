#!/bin/sh
# Builds both variants: static musl (general-purpose fallback) and
# device-patched gnu (the specific mipsel camera also targeted by
# libsdk-py). See README.md for what each one is for.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

"$ROOT/build-mipsel-musl.sh"
echo
"$ROOT/build-mipsel-gnu.sh"
