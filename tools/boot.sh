#!/bin/bash
# usage: tools/boot.sh nura-boot.img rootfs.tar.gz [iface]
# Needs: adb with root on the phone (Magisk/KernelSU), fastboot, an unlocked bootloader.
# Boots the image with `fastboot boot` (nothing is flashed) and then sends the rootfs over USB.
# Android stays untouched: a normal reboot brings it back.
set -e
IMG=$1; ROOTFS=$2; IFACE=${3:-en5}
adb wait-for-device
# Turn off download/ramdump mode first: with it on, any unexpected reboot leaves the phone hung
# until you hold the power button.
adb shell 'su -c "for p in /sys/module/*/parameters/*download_mode*; do echo 0 > \$p 2>/dev/null || echo N > \$p 2>/dev/null; done"'
adb reboot bootloader
until fastboot devices | grep -q fastboot; do sleep 1; done
fastboot boot "$IMG"
python3 "$(dirname "$0")/send-rootfs.py" "$ROOTFS" "$IFACE"
