# apk-tools-mipsel

Cross-builds of [apk-tools](https://gitlab.alpinelinux.org/alpine/apk-tools)
for mipsel, following the approach used in
[o-murphy/micropython-mipsel](https://github.com/o-murphy/micropython-mipsel):
a pinned upstream submodule, a scripted cross toolchain + dependency build,
and a GitHub Actions workflow that publishes the resulting binaries as
release artifacts.

Two variants, for two different needs:

- **musl / static** (`build-mipsel-musl.sh`) — fully static, no dynamic
  dependencies at all. Runs on basically any mipsel Linux kernel regardless
  of the userland's libc or dynamic linker. This is the general-purpose
  fallback.
- **gnu / device-patched** (`build-mipsel-gnu.sh`) — targets the specific
  mipsel camera device also used by `libsdk-py`: dynamically linked against
  the device's own glibc (bootlin `mips32el--glibc--stable-2018.11-1`, the
  same toolchain used there), with zlib + mbedTLS statically embedded, then
  patched with the exact same treatment as libsdk-py's `mips-gnu` Makefile
  target (NaN2008 ABI fixup, RPATH, interpreter, `NEEDED` rewrite) so it
  runs under that device's non-standard dynamic linker.

Nothing is vendored: the toolchains and dependency sources are
fetched/built by the scripts below and live under gitignored directories
(`toolchain/`, `toolchain-gnu/`, `deps-build-musl/`, `deps-musl-prefix/`,
`deps-build-gnu/`, `deps-gnu-prefix/`, `build-musl/`, `build-gnu/`).

## Layout

- `deps/apk-tools` — apk-tools upstream, pinned as a git submodule
- `deps/zlib`, `deps/mbedtls` — build dependencies, also pinned submodules
- `toolchain.sh` — fetches the `mipsel-linux-musl-cross` standalone
  toolchain (musl.cc) into `./toolchain`, used by the musl variant
- `toolchain-gnu.sh` — fetches the bootlin `mips32el--glibc` toolchain into
  `./toolchain-gnu`, used by the gnu variant
- `deps.sh` / `deps-gnu.sh` — cross-build static `zlib` and `mbedTLS` from
  the submodules for each toolchain (out-of-tree, under `./deps-build-musl`
  / `./deps-build-gnu`, so the submodule checkouts stay pristine) and
  install them into `./deps-musl-prefix` / `./deps-gnu-prefix`
- `cmake/mipsel-musl-toolchain.cmake` / `cmake/mips32el-gnu-toolchain.cmake`
  — CMake toolchain files used to cross-build mbedTLS for each target
- `meson/mipsel-musl.cross.in` / `meson/mipsel-gnu.cross.in` — meson
  cross-file templates; the build scripts fill in `@DEPS_PREFIX@`
- `scripts/patch_nan2008.py` — patches a MIPS ELF's `EF_MIPS_NAN2008` flag
  and `.MIPS.abiflags` section for FPU ABI compatibility with the target
  device (vendored from `libsdk-py`, unchanged)
- `build-mipsel-musl.sh` — toolchain + deps + `meson`/`ninja`, produces a
  fully static `build-musl/src/apk`
- `build-mipsel-gnu.sh` — toolchain + deps + `meson`/`ninja`, smoke-tests
  the unpatched binary under `qemu-user` against the toolchain's own
  sysroot, then applies the nan2008/rpath/interpreter patches and strips,
  producing `build-gnu/src/apk`
- `ci.sh` — helper functions used by the GitHub Actions workflow: install
  build deps, verify static linkage / smoke-test under `qemu-user` (musl),
  verify the device patches structurally (gnu), extract the apk-tools
  version and rename each artifact
- `.github/workflows/build-ci.yml` — builds both variants on
  `workflow_dispatch`, push/PR, and published releases; uploads
  `apk-mipsel-<version>` and `apk-mipsel-gnu-<version>` as artifacts

## Building locally

```
git clone --recurse-submodules <this repo>
./build-mipsel-musl.sh   # -> build-musl/src/apk
./build-mipsel-gnu.sh    # -> build-gnu/src/apk
```

### musl variant

Produces a static-PIE MIPS (little-endian) ELF binary with no dynamic
dependencies (`ldd` reports "not a dynamic executable"):

```
qemu-mipsel build-musl/src/apk --version
qemu-mipsel build-musl/src/apk --print-arch   # -> mipsel
```

### gnu variant

Produces a dynamically-linked ELF whose `PT_INTERP` is
`/lib/ld-linux-mipsn8.so.1` and whose `RUNPATH` is `/lib:/tmp/libsdk` —
it will only actually run on that specific device (or something with the
same libc/linker layout). `build-mipsel-gnu.sh` smoke-tests the binary
*before* applying those device-specific patches, using the toolchain's own
sysroot:

```
qemu-mipsel -L toolchain-gnu/mips32el--glibc--stable-2018.11-1/mipsel-buildroot-linux-gnu/sysroot \
  build-gnu/src/apk --version
```

Deploying to the device follows the same convention as `libsdk-py`'s
`push-device`/`deploy` targets (push to `/tmp/libsdk`, `adb push`, etc.) —
this repo only builds the binary, it doesn't push it.

The one thing NaN2008 patching is actually protecting here: apk-tools uses
floating point in exactly one place
([src/print.c:129](deps/apk-tools/src/print.c#L129), formatting package
sizes as e.g. "10.5 MiB"), so the risk it addresses is small but not zero.

## Build configuration decisions

- **crypto backend: mbedTLS**, not OpenSSL. mbedTLS cross-builds cleanly
  with a plain CMake toolchain file; OpenSSL's `Configure` needs a lot more
  manual cross-compilation wrangling. See `deps.sh` / `deps-gnu.sh`.
- **`url_backend=wget`**, not the default `libfetch`. Upstream's
  `libfetch/meson.build` calls `crypto_dep.partial_dependency(...)`, but
  with `crypto_backend=mbedtls` that dependency is a *list* (`[mbedtls,
  mbedcrypto]`), and `partial_dependency()` isn't defined on a list —
  meson fails with `Unknown method "partial_dependency"`. This combination
  (mbedTLS + libfetch) appears untested upstream. Since the target use case
  here is installing already-downloaded local `.apk` files (no network
  fetch needed), `wget` sidesteps the bug entirely; package signature
  verification still goes through mbedTLS regardless of `url_backend`.
- **`zstd=disabled`**. zstd in apk-tools is only used for the newer binary
  v3/ADB package/index format when it is itself zstd-compressed — it is
  unrelated to reading plain `.apk` (tar.gz) files. Since packages for this
  mipsel target are built/controlled locally and not pulled from an
  upstream zstd-compressed repo, it's left out to keep the build minimal.
  **To re-enable:** cross-build `libzstd` statically with CMake against the
  relevant toolchain file (analogous to the mbedTLS step in `deps.sh` /
  `deps-gnu.sh`), install it into the matching deps prefix, and drop
  `-Dzstd=disabled` from the build script.
- **`lua`, `python`, `docs`, `tests` all disabled** — lua/python bindings
  and man pages aren't needed for the `apk` CLI binary itself, and the test
  suite isn't set up to run under `qemu-user`.
- **gnu variant links glibc dynamically but zlib/mbedTLS statically** —
  only `.a` files exist in `deps-gnu-prefix`, so the linker embeds those
  directly; glibc itself (`libc.so.6`) is left dynamic since that's what
  needs the device-specific RPATH/interpreter patching in the first place.
- **`patchelf --replace-needed ld.so.1 ld-linux-mipsn8.so.1` is a no-op
  here** — unlike libsdk-py's Rust cdylib, this toolchain's linker didn't
  emit a literal `ld.so.1` `NEEDED` entry for the apk binary (only
  `libc.so.6`), so that step currently does nothing but is kept for
  parity/safety in case a future rebuild changes that.
- **musl variant links `-static -no-pie`, not just `-static`** — the
  musl.cc toolchain defaults to PIE, producing a `static-pie` executable.
  On-device testing showed that hangs on this camera's kernel; a classic
  `ET_EXEC` static binary (`-no-pie`) runs correctly. Passed via
  `-Dc_link_args="['-static','-no-pie']"` on the `meson setup` command
  line specifically — setting it as an array in the `.cross` ini file
  silently dropped the second element (a meson cross-file parsing quirk),
  so don't move it back there without re-checking.
- **gnu variant strips *before* patchelf, not after** — patchelf rewrites
  program headers (e.g. growing the dynamic string table for the new
  RPATH), and running `strip` afterwards corrupted that layout (silently,
  with only a `.dynstr` "outside segment" warning from `strip`) in a way
  that made the device's kernel refuse to exec the binary
  (`Invalid argument`). Verified on real hardware.
