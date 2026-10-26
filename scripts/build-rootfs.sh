#!/usr/bin/env bash
# Builds rootfs.tar.gz (postmarketOS/Alpine aarch64 + Plasma Mobile + the Nura Frogger overlay).
# Run as root on an aarch64 Linux machine, or in a privileged `docker run --platform linux/arm64 alpine:3.24`
# container with `apk add apk-tools tar gzip` (needs `apk`, `chroot`).
#
#   FW_DIR   directory with firmware extracted from YOUR phone (see README, "Firmware"); copied to /lib/firmware
#   KOUT     output of scripts/build-kernel.sh (kernel modules, nura-ovl.ko, nura-display.dtbo)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HERE/build}; KOUT=${KOUT:-$WORK/out-kernel}; FW_DIR=${FW_DIR:?set FW_DIR to the extracted firmware directory}
R=$WORK/rootfs
rm -rf "$R"; mkdir -p "$R/etc/apk"
cat > "$R/etc/apk/repositories" <<REPOS
https://mirror.nura.eco/postmarketos/v26.06
https://dl-cdn.alpinelinux.org/alpine/v3.24/main
https://dl-cdn.alpinelinux.org/alpine/v3.24/community
REPOS
# the postmarketOS/Nura repo signing key must be in /etc/apk/keys on the build host (see README)
cp -a /etc/apk/keys "$R/etc/apk/"
apk --root "$R" --initdb --arch aarch64 --no-cache add $(tr '\n' ' ' < "$HERE/rootfs-overlay/apk-world.txt")

# overlay: init scripts, display bring-up, SIM helpers, DSDS proxy, greetd -> Plasma Mobile, UCM profile
cp -a "$HERE/rootfs-overlay/." "$R/"
rm -f "$R/apk-world.txt"
chmod +x "$R"/etc/local.d/*.start "$R"/etc/init.d/nura-display "$R"/usr/local/bin/*

# kernel modules for the mainline kernel + display overlay
cp -a "$KOUT/modroot/lib/modules" "$R/lib/"
install -D "$KOUT/nura-display.dtbo" "$R/lib/firmware/nura-display.dtbo"
KREL=$(ls "$R/lib/modules" | head -1)
install -D "$KOUT/nura-ovl.ko" "$R/lib/modules/$KREL/extra/nura-ovl.ko"
# aw88261 amplifier firmware and the rest of the vendor firmware
cp -a "$FW_DIR/." "$R/lib/firmware/"
# audio topology
(cd "$HERE/audio" && command -v alsatplg >/dev/null) && echo "NOTE: compile audio/Nothing-Phone-4a.m4 with audioreach-topology (see README) into /lib/firmware/qcom/milos/"

# system setup (the default password for both users is "nura": change it)
echo nura > "$R/etc/hostname"
: > "$R/etc/fstab"      # root is tmpfs, everything lives in RAM
chroot "$R" /bin/sh -c '
  echo "root:nura" | chpasswd
  adduser -D -s /bin/sh nura 2>/dev/null || true; echo "nura:nura" | chpasswd
  for g in wheel video input audio render seat netdev plugdev dialout; do addgroup nura $g 2>/dev/null || true; done
  rc-update add local default; rc-update add nura-display default; rc-update add greetd default
  rc-update add sshd default; rc-update add networkmanager default; rc-update add modemmanager default
  depmod -a $(ls /lib/modules | head -1)'
mkdir -p "$R/etc/ssh/sshd_config.d"
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > "$R/etc/ssh/sshd_config.d/nura.conf"
mkdir -p "$R/etc/NetworkManager/conf.d"
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' > "$R/etc/NetworkManager/conf.d/10-usb0.conf"

tar -C "$R" -czf "$WORK/rootfs.tar.gz" .
echo "done: $WORK/rootfs.tar.gz ($(du -h "$WORK/rootfs.tar.gz" | cut -f1))"
