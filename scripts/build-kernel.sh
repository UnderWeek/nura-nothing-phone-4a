#!/usr/bin/env bash
# Builds the mainline-based Milos kernel (stage 2 kernel) with the Nura Frogger patches.
# Output (in $OUT): Image-milos, milos-nothing-frogger.dtb, nura-display.dtbo, nura-ovl.ko, modroot/ (modules)
# Needs: git, clang + lld (LLVM=1), make, dtc, flex, bison, libssl-dev, bc. Run on aarch64 or x86-64 Linux
# (or inside a Linux container). Not tested on macOS.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HERE/build}; OUT=${OUT:-$WORK/out-kernel}; JOBS=${JOBS:-$(nproc)}
SRC=$WORK/linux-milos
mkdir -p "$WORK" "$OUT"

[ -d "$SRC/.git" ] || git clone https://github.com/milos-mainline/linux "$SRC"
git -C "$SRC" checkout -f "$(cat "$HERE/kernel/BASE_COMMIT")"
git -C "$SRC" apply "$HERE/kernel/nura-frogger-milos-7.2.patch"
cp "$HERE/kernel/config-milos.aarch64" "$SRC/.config"

MK="make -C $SRC ARCH=arm64 LLVM=1 KCFLAGS=-Wno-error -j$JOBS"
$MK olddefconfig
$MK Image dtbs modules
rm -rf "$OUT/modroot"
$MK modules_install INSTALL_MOD_PATH="$OUT/modroot" INSTALL_MOD_STRIP=1

cp "$SRC/arch/arm64/boot/Image" "$OUT/Image-milos"
cp "$SRC/arch/arm64/boot/dts/qcom/milos-nothing-frogger.dtb" "$OUT/"

# Display bring-up overlay: nura-ovl.ko applies nura-display.dtbo at runtime
# (mdss/dispcc are disabled in the base DTB; enabling them from the start breaks the simple framebuffer)
cp -r "$HERE/kernel/nura-ovl" "$WORK/nura-ovl"
make -C "$SRC" ARCH=arm64 LLVM=1 M="$WORK/nura-ovl" modules
cp "$WORK/nura-ovl/nura-ovl.ko" "$OUT/"
"$SRC/scripts/dtc/dtc" -@ -I dts -O dtb -o "$OUT/nura-display.dtbo" "$HERE/kernel/nura-ovl/nura-display.dts"

echo "kernel release: $(cat "$SRC/include/config/kernel.release")"
echo "done: $OUT"
