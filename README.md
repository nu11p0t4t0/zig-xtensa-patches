# zig-xtensa-patches

Patches to add Xtensa (ESP32-S2/S3, ESP8266) CPU support to Zig 0.14.0.

## What's included

- `patches/xtensa-target.patch` — Extends `lib/std/Target/xtensa.zig` with:
  - 31 CPU features (atomctl, bool, clamps, coprocessor, debug, dfpaccel, div32, esp32s2, esp32s3, exception, extendedl32r, fp, hifi3, highpriinterrupts, interrupt, loop, mac16, memctl, minmax, miscsr, mul16, mul32, mul32high, nsa, prid, regprotect, rvector, s32c1i, sext, threadptr, timerint, windowed)
  - 5 CPU models: `generic`, `cnl`, `esp32`, `esp32s2`, `esp32s3`, `esp8266`

Stock Zig 0.14.0 only has `generic` with the `density` feature.

## Usage

```bash
# Clone stock Zig 0.14.0
git clone --depth 1 --branch 0.14.0 https://github.com/ziglang/zig.git zig-0.14.0
cd zig-0.14.0

# Apply patches
git apply ../zig-xtensa-patches/patches/xtensa-target.patch

# Build (requires LLVM 19 with Xtensa backend enabled)
cmake -B build -DCMAKE_BUILD_TYPE=Release -DZIG_TARGETS="Xtensa" .
cmake --build build --target install
```

## Prebuilt toolchain

A prebuilt `zig-relsafe-x86_64-linux-musl-baseline` (Zig 0.14.0-xtensa) is available at `<toolchain-root>/` on the build machine. Not distributed here due to size (~300MB).

## Target triples

```bash
# ESP32-S3 (Cardputer)
zig build-exe -target xtensa-freestanding -mcpu=esp32s3 ...

# ESP32-S2
zig build-exe -target xtensa-freestanding -mcpu=esp32s2 ...

# ESP8266
zig build-exe -target xtensa-freestanding -mcpu=esp8266 ...
```

## macOS local toolchain recipe

`bootstrap/macos-toolchain.patch` records the edits used on this machine to build a
Zig 0.14.0 Xtensa compiler against a reduced LLVM. It is a **local build recipe, not
an upstream-ready patch**, and it deliberately does *not* live in `patches/` because
`build.sh` / `build_macos.sh` apply every `patches/*.patch` to a stock Zig checkout.

Contents:
- `zig/stage1/config.zig.in` — `llvm_has_xtensa = true` (the actual port enablement)
- `zig/lib/libcxx/include/__random/clamp_to_integral.h` — make `INFINITY` visible
  when the C library headers do not define it
- `zig/src/codegen/llvm.zig` — omit Hexagon registration (that backend is not in
  this LLVM build)
- `zig/cmake/Findllvm.cmake` — restrict `ZIG_LLVM_REQUIRED_TARGETS` to the targets
  this LLVM actually builds (**breaks normal builds; local only**)
- `llvm_target_stubs.c` — no-op `LLVMInitialize<T>Target*` symbols so the link
  succeeds with the reduced LLVM

Apply inside a `recamshak/zig-espressif` checkout:

```bash
git apply /path/to/bootstrap/macos-toolchain.patch
```
