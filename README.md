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

## Zig 0.17.0 (the family's current device toolchain)

The family moved to Zig 0.17.0 in October 2026. Stock 0.17.0 has **no Xtensa
support at all**: `std/Target/xtensa.zig` declares only `esp32`, `esp8266`
and `generic`, and the LLVM it links has no Xtensa backend, so
`zig build -target xtensa-freestanding-none` fails with "LLVM failed to
parse xtensa-unknown-unknown-unknown: Unable to find target for this
triple (no targets are registered)".

- `patches/xtensa-target-0.17.0.patch` — the three-file port (191 lines):
  - `lib/std/Target/xtensa.zig` — the CPU models `cnl`, `esp32s2`,
    `esp32s3` and the features `esp32s2ops`, `esp32s3ops`, `expstate`,
    `hifi3`, re-expressed in 0.17 syntax (`@backingInt`, `field_names.len`;
    0.16 used `@intFromEnum` and `fields.len`).
  - `stage1/config.zig.in` — `llvm_has_xtensa = true`, the switch that
    makes zig's codegen register the Xtensa LLVM target
    (`src/codegen/llvm.zig` already carries the 0.17 branch).
  - `cmake/Findllvm.cmake` — `Xtensa` added to the required-target list, so
    a stock LLVM without the backend is refused instead of silently
    producing a compiler that cannot target the chip.
- `bootstrap/build-xtensa-017.sh` — the build recipe: an LLVM host build
  from **Espressif's fork** (the only LLVM 22 with the Xtensa backend, tag
  `esp-22.1.4_20260825`), then zig 0.17.0's cmake build against it.

### The stage3 flag (the second trap)

Zig's cmake build never passes `-Dllvm-has-xtensa`, and the option that
makes the FINAL compiler (stage3 - the one the family uses) call
`LLVMInitializeXtensaTarget*` defaults to FALSE. `stage1/config.zig.in`'s
`llvm_has_xtensa = true` only reaches the stage1/stage2 compilers. Without
the flag every xtensa build dies with:

```
LLVM failed to parse 'xtensa-unknown-unknown-unknown': Unable to find
target for this triple (no targets are registered)
```

The 0.16 fork did not need it because espressif's LLVM 21 still
self-registers the target through the backends' static constructors;
upstream LLVM 22 dropped those, so the explicit call is required now.
Pass it through the cmake hook that exists for this:

```sh
cmake "$ROOTDIR/zig" ... -DZIG_EXTRA_BUILD_ARGS="-Dllvm-has-xtensa"
```

### The LLVM part

Zig 0.17.0 wants `llvm-config-22` and accepts any 22.x
(`cmake/Findllvm.cmake` rejects < 22 and >= 23), so Espressif's
`esp-22.1.4_20260825` qualifies. **Xtensa is an EXPERIMENTAL target in
that fork** (`llvm/CMakeLists.txt`, `LLVM_ALL_EXPERIMENTAL_TARGETS`), not a
default one, so the build needs:

```sh
-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
```

Without it the LLVM builds without the Xtensa backend, `llvm-config
--targets-built` omits Xtensa, and zig's configure refuses the LLVM with
"missing target Xtensa". The 0.16 bootstrap needed the same flag.

### Usage

```sh
# 1. the LLVM with Xtensa
git clone --depth 1 --branch esp-22.1.4_20260825 \
    https://github.com/espressif/llvm-project.git llvm-22-xtensa

# 2. zig 0.17.0
git clone --depth 1 --branch 0.17.0 https://github.com/ziglang/zig.git zig-017-src
git -C zig-017-src apply ../zig-xtensa-patches/patches/xtensa-target-0.17.0.patch

# 3. build (run from the tree root: llvm/ and zig/ beside the script)
sh bootstrap/build-xtensa-017.sh
# -> out/host/bin/zig, out/host/bin/llvm-nm
```

The family keeps the toolchain at `0x_Z1/out/zig-xtensa-017/` (the path
`0x_Z1Gdmm/tools/idf-build.sh` and `tools/linkgate.sh` already expect):
`out/zig-xtensa-017/host/zig` and `out/zig-xtensa-017/host/bin/llvm-nm`.
