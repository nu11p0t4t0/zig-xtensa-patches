#!/bin/sh
# build-xtensa-017.sh — build a Zig 0.17.0 toolchain that carries the Xtensa
# backend, for the ESP32-S3 device lane.
#
# Ingredients (all measured, 2026-10-27):
#   zig   0.17.0 (upstream)      - wants llvm-config-22 (cmake/Findllvm.cmake:20)
#   llvm  22.1.4 (espressif)     - the ONLY 22.x with llvm/lib/Target/Xtensa
#                                   (tag esp-22.1.4_20260825); zig 0.17 accepts
#                                   any 22.x (Findllvm.cmake:43 rejects <22 and
#                                   >=23)
#   zig-side patch               - lib/std/Target/xtensa.zig (esp32s2/esp32s3/
#                                   cnl models + 4 features), stage1/config.zig.in
#                                   (llvm_has_xtensa = true), cmake/Findllvm.cmake
#                                   (Xtensa in the required-target list)
#
# Recipe mirrors the 0.16 bootstrap (zig-xtensa-bootstrap/build), minus the
# self-hosted cross stages the family does not need: the family links the
# device archive with ESP-IDF's xtensa-esp-elf toolchain, so zig never needs
# a bundled musl/zlib for xtensa, and nothing runs a compiler on the ESP32.
#
# Usage: run from the tree root (the script uses $PWD).
set -eu

ROOTDIR=$(pwd)
ZIG_VERSION="0.17.0"
JOBS=${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}

echo "== 1/3: LLVM $ZIG_VERSION host build (Xtensa included) =="
mkdir -p "$ROOTDIR/out/build-llvm-host"
cd "$ROOTDIR/out/build-llvm-host"
# espressif/llvm-project is the MONOREPO layout (llvm/, clang/, lld/ as
# siblings), so the cmake source dir is <repo>/llvm, not <repo>.
cmake "$ROOTDIR/llvm/llvm" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_PLUGINS=OFF \
  -DLLVM_ENABLE_PROJECTS="lld;clang" \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
  -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
  -DLLVM_TOOL_LTO_BUILD=OFF \
  -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
  -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
  -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
  -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
# Xtensa is an EXPERIMENTAL target in espressif's LLVM 22
# (llvm/CMakeLists.txt:541-547, LLVM_ALL_EXPERIMENTAL_TARGETS), so it is NOT
# built by default and llvm-config --targets-built omits it. Zig's
# cmake/Findllvm.cmake then refuses the LLVM ("missing target Xtensa"), which
# is exactly the gate this flag opens. The 0.16 bootstrap used the same flag.
cmake --build . --target install -j "$JOBS"

echo "== 2/3: Zig $ZIG_VERSION host build (stage1, Xtensa enabled) =="
mkdir -p "$ROOTDIR/out/build-zig-host"
cd "$ROOTDIR/out/build-zig-host"
# ZIG_EXTRA_BUILD_ARGS reaches the FINAL compiler (stage3), which is the one
# the family uses. Without -Dllvm-has-xtensa the stage3 build leaves
# build_options.llvm_has_xtensa false, so zig's codegen never calls
# LLVMInitializeXtensaTarget* and every xtensa build dies with "LLVM failed
# to parse 'xtensa-unknown-unknown-unknown': Unable to find target for this
# triple (no targets are registered)". The 0.16 fork got away without this
# because its LLVM (espressif's, LLVM 21) still self-registers the target;
# upstream LLVM 22 dropped the static constructors, so the explicit call is
# required now.
cmake "$ROOTDIR/zig" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VERSION="$ZIG_VERSION" \
  -DZIG_EXTRA_BUILD_ARGS="-Dllvm-has-xtensa"
cmake --build . --target install -j "$JOBS"

echo "== 3/3: verify =="
ZIG="$ROOTDIR/out/host/bin/zig"
"$ZIG" version
echo "-- xtensa targets known to this compiler:"
"$ZIG" targets 2>/dev/null | grep -i xtensa || echo "(no 'targets' subcommand; listing the CPU models instead)"
ls -la "$ROOTDIR/out/host/bin/" | head -12
echo "build-xtensa-017: DONE ($ZIG)"
