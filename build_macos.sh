#!/usr/bin/env bash
# Build Zig 0.14.0 with Xtensa support on macOS (Apple Silicon)
# Requires: xcode-select --install, brew install cmake ninja llvm

set -euo pipefail

ZIG_VERSION="0.14.0"
ZIG_REPO="https://github.com/ziglang/zig.git"
WORKDIR="$(pwd)/zig-${ZIG_VERSION}-macos"
PATCH_DIR="$(pwd)/patches"

echo "=== Zig ${ZIG_VERSION} Xtensa Build (macOS Apple Silicon) ==="
echo "Workdir: ${WORKDIR}"

# Check for LLVM
if ! command -v llvm-config &> /dev/null; then
    echo "LLVM not found. Install with: brew install llvm"
    echo "Then: export PATH=\"$(brew --prefix llvm)/bin:\$PATH\""
    exit 1
fi

# 1. Fetch stock Zig source
if [[ ! -d "${WORKDIR}/.git" ]]; then
    echo "Cloning Zig ${ZIG_VERSION}..."
    git clone --depth 1 --branch "${ZIG_VERSION}" "${ZIG_REPO}" "${WORKDIR}"
else
    echo "Zig source already present"
fi

cd "${WORKDIR}"

# 2. Apply patches
echo "Applying Xtensa patches..."
for patch in "${PATCH_DIR}"/*.patch; do
    [[ -f "$patch" ]] || continue
    echo "  Applying $(basename "$patch")..."
    git apply "$patch"
done

# 3. Build
echo "Configuring with CMake (targets: Xtensa)..."
cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DZIG_TARGETS="Xtensa" \
    -DCMAKE_INSTALL_PREFIX="$(pwd)/install" \
    -GNinja

echo "Building (this takes a while)..."
cmake --build build --target install

echo ""
echo "=== Build complete ==="
echo "Zig binary: ${WORKDIR}/install/bin/zig"
echo "Version: $("${WORKDIR}/install/bin/zig" version)"
echo ""
echo "Test Xtensa target:"
"${WORKDIR}/install/bin/zig" targets | grep -i xtensa
