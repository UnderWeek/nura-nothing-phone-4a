#!/usr/bin/env bash
# Builds nura-boot.img: Nothing's downstream 6.1 kernel (stage 1) with an initramfs that kexec's into the
# mainline Milos kernel built by build-kernel.sh (stage 2).
#
#   fastboot boot nura-boot.img   ->  stage1 kernel (has working UFS/USB) -> kexec -> mainline kernel + stage2 initramfs
#   stage2 opens a USB ethernet gadget, receives the rootfs into RAM and switch_root's into it.
#
# Needs: docker (for the aarch64 Alpine userland), git, clang + lld, make, python3, curl.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HERE/build}; KOUT=${KOUT:-$WORK/out-kernel}; JOBS=${JOBS:-$(nproc)}
NOTHING_COMMIT=3d5142984   # "Merge codes for Nothing Phone(4a) Nothing OS 4.1 (Frogger-B4.1-260911-0959)"
mkdir -p "$WORK"

for f in Image-milos milos-nothing-frogger.dtb; do [ -f "$KOUT/$f" ] || { echo "run scripts/build-kernel.sh first ($f missing)"; exit 1; }; done

# ---- stage2 initramfs (Alpine userland: busybox + socat, our init) -----------------------------
S2=$WORK/stage2; rm -rf "$S2"; mkdir -p "$S2"
docker run --rm --platform linux/arm64 -v "$S2":/r alpine:3.24 sh -c '
  apk add --root /r --initdb --keys-dir /etc/apk/keys --repositories-file /etc/apk/repositories --no-cache \
      alpine-baselayout busybox busybox-extras musl socat >/dev/null'
install -m 755 "$HERE/stage2/nura-init" "$S2/nura-init"
mkdir -p "$S2"/{proc,sys,dev,run,tmp,root}
(cd "$S2" && find . | cpio -o -H newc 2>/dev/null | gzip -9) > "$WORK/stage2.gz"

# ---- stage1 initramfs (compiled into the downstream kernel) ------------------------------------
S1=$WORK/stage1; rm -rf "$S1"; mkdir -p "$S1"/{bin,sbin,usr/sbin,lib,boot,proc,sys,dev,tmp,root,etc}
docker run --rm --platform linux/arm64 -v "$S1":/r alpine:3.24 sh -c '
  apk add --no-cache busybox busybox-extras kexec-tools >/dev/null
  cp /bin/busybox /r/bin/busybox; cp /usr/bin/busybox-extras /r/bin/busybox-extras 2>/dev/null || true
  cp /usr/sbin/kexec /r/usr/sbin/kexec; cp /lib/ld-musl-aarch64.so.1 /r/lib/
  ln -sf ld-musl-aarch64.so.1 /r/lib/libc.musl-aarch64.so.1
  for a in sh cat dmesg echo grep head ip ifconfig insmod ls lsmod mkdir mknod modprobe mount rmmod sleep sync tail tr udhcpc; do ln -sf busybox /r/bin/$a; done'
install -m 755 "$HERE/stage1/nura-init" "$S1/nura-init"
cp "$KOUT/Image-milos" "$S1/boot/Image-milos"
cp "$KOUT/milos-nothing-frogger.dtb" "$S1/boot/milos.dtb"
cp "$WORK/stage2.gz" "$S1/boot/stage2.gz"

# ---- stage1 kernel ------------------------------------------------------------------------------
NSRC=$WORK/nothing-kernel
[ -d "$NSRC/.git" ] || git clone https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635.git "$NSRC"
git -C "$NSRC" checkout -f "$NOTHING_COMMIT"
O=$WORK/out-stage1; mkdir -p "$O"
cp "$HERE/stage1/config-stage1.aarch64" "$O/.config"
sed -i "s#^CONFIG_INITRAMFS_SOURCE=.*#CONFIG_INITRAMFS_SOURCE=\"$S1\"#" "$O/.config"
MK="make -C $NSRC O=$O ARCH=arm64 LLVM=1 KCFLAGS=-Wno-error -j$JOBS"
$MK olddefconfig
$MK Image

# ---- boot image (header v4, kernel only) --------------------------------------------------------
[ -d "$WORK/mkbootimg" ] || git clone https://android.googlesource.com/platform/system/tools/mkbootimg "$WORK/mkbootimg"
python3 "$WORK/mkbootimg/mkbootimg.py" --header_version 4 --kernel "$O/arch/arm64/boot/Image" --output "$WORK/nura-boot.img"
echo "done: $WORK/nura-boot.img"
