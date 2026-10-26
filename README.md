# Nura on the Nothing Phone (4a) — "Frogger" (SM7635 / Milos)

Work-in-progress port of **Nura** (postmarketOS-based, Alpine) with **Plasma Mobile** to the
Nothing Phone (4a), booted from RAM with `fastboot boot`. Nothing is flashed: a normal reboot brings Android back.

> Русское резюме: это порт Nura (postmarketOS) на Nothing Phone (4a) с Plasma Mobile. Образ грузится через
> `fastboot boot`, ничего не прошивается, rootfs каждый раз отправляется с компьютера в RAM. Работают экран, тач,
> GPU, Wi-Fi/Bluetooth, модем и звонки (две SIM одновременно), динамики. Не работают микрофон и голос в звонках.
> Инструкция по сборке ниже.

**Status: experimental, one developer, one device.** Read the warnings before you try it.

## What works

| Works | Notes |
|---|---|
| Display (DSI panel NT37706A, DPU, DSC), 60/90/120 Hz | brought up by a DT overlay (`nura-ovl`), see below |
| Touch (FocalTech FT3681/FT3683G, SPI) | new driver in the kernel patch |
| GPU (Adreno 810, freedreno/Mesa) | needs firmware from your phone |
| Wi-Fi, Bluetooth (WCN6750) | |
| Modem, calls, SMS | **no voice audio in calls** |
| Two SIMs at once (DSDS) | patched ModemManager + plasma-dialer + a QMI proxy, see `patches/` |
| Mobile data | on the primary SIM only (via NetworkManager); the second SIM has no data path yet |
| Speakers (2x AW88261 amplifiers, AudioReach on the ADSP) | PulseAudio sink via the UCM profile in `rootfs-overlay/` |
| Plasma Mobile session | Phosh and GNOME apps are not used |

**Not working / not done:** microphones (WCD9378 has no mainline driver), voice audio during calls, data on the second SIM,
persistent installation (the rootfs lives in RAM; userdata is encrypted, installing would wipe Android), camera, sensors,
fingerprint, NFC, haptics and everything else not listed above has not been tested.

## How it boots

```
fastboot boot nura-boot.img
  └─ stage 1: Nothing's downstream 6.1 kernel with a built-in initramfs (stage1/nura-init)
       └─ kexec  →  stage 2: mainline-based Milos 7.2 kernel + milos-nothing-frogger.dtb + stage2.gz (stage2/nura-init)
            └─ stage 2 opens a USB ethernet gadget (fe80::ff:fe00:1) and waits on [::]:4444
                 └─ the host sends rootfs.tar.gz (tools/send-rootfs.py) → unpacked into tmpfs → switch_root → OpenRC → greetd → Plasma Mobile
```

The downstream kernel is only used because it already brings up UFS/USB correctly in the bootloader environment;
everything else runs on the mainline-based kernel from [milos-mainline/linux](https://github.com/milos-mainline/linux).

## Requirements

* A Nothing Phone (4a) (Frogger) with an **unlocked bootloader** and root in Android (Magisk/KernelSU) — root is only used to turn off
  download/ramdump mode before the test boot (see `tools/boot.sh`).
* A computer with `adb`, `fastboot`, Python 3 (tested from macOS).
* To build: Docker (aarch64 userland), `git`, `clang`/`lld`, `make`, `dtc`, `bison`, `flex`, `libssl-dev`, `bc`, `python3`. Roughly 40 GB of disk space.
* Firmware extracted from **your own** phone (not included, see below).

## Repository layout

| Path | What |
|---|---|
| `kernel/nura-frogger-milos-7.2.patch` | Patch on top of `milos-mainline/linux` (commit in `kernel/BASE_COMMIT`): Frogger DTS, NT37706A panel driver, FocalTech touch driver, AW88261/AudioReach/MI2S audio fixes, DPU/DSI fixes. Contains `NURA-DBG`/`NURA-TX` debug prints. |
| `kernel/config-milos.aarch64` | Kernel config for the mainline-based kernel |
| `kernel/nura-ovl/` | Out-of-tree module that applies `nura-display.dts` as a device-tree overlay at runtime (mdss/dispcc are disabled in the base DTB) |
| `stage1/` | init script and kernel config of the downstream stage 1 kernel |
| `stage2/` | init script of the stage 2 initramfs |
| `rootfs-overlay/` | Files laid over the Alpine/postmarketOS rootfs: OpenRC scripts, display bring-up, SIM helpers, DSDS proxy, greetd → Plasma Mobile, UCM profile, package list |
| `patches/` | `mm-dsds.patch` (ModemManager, second modem on a proxied QRTR node), `pd-dsds.patch` (plasma-dialer: modem/SIM selection) |
| `audio/Nothing-Phone-4a.m4` | AudioReach topology source |
| `scripts/` | Build scripts (kernel, boot image, rootfs) |
| `tools/` | `boot.sh` (fastboot boot + send rootfs), `send-rootfs.py`, `nssh`, `pil-squash.py` (joins `.mdt`+`.bNN` firmware) |

## Build

> The scripts were assembled from the commands used during development. The boot image in **Releases** is the
> tested artifact; the scripts have not been run end-to-end from a clean checkout yet — expect to fix small things and please send PRs.

### 1. Mainline kernel (stage 2)

```sh
scripts/build-kernel.sh          # → build/out-kernel/{Image-milos, milos-nothing-frogger.dtb, nura-display.dtbo, nura-ovl.ko, modroot/}
```

### 2. Boot image (stage 1 + stage 2)

```sh
scripts/build-boot-image.sh      # → build/nura-boot.img
```

This clones Nothing's kernel source (`NothingOSS/android_kernel_msm-6.1_nothing_sm7635`, commit `3d5142984`),
builds it with `stage1/config-stage1.aarch64` and the initramfs from `stage1/`, and wraps it with `mkbootimg` (header v4).
You can skip steps 1–2 and use `nura-boot-v57.img` from the Releases page.

### 3. Firmware (from your phone)

Firmware is proprietary and is **not** distributed here. Extract it from your own phone's partitions
(e.g. the `modem` image and `/vendor/firmware`) and put it in a directory laid out like this (names as expected by the DTS):

```
qcom/milos/nothing/frogger/{adsp.mbn,adsp_dtb.mbn,cdsp.mbn,cdsp_dtb.mbn,modem.mbn,wpss.mbn,ipa_fws.mbn,gen80300_zap.mbn,aw88261_acf.bin}
qcom/milos/nothing/frogger/{adspr,adsps,adspua,cdspr,modemr,battmgr}.jsn
qcom/milos/nothing/frogger/modem_pr/…           (modem configuration, copied as is)
qcom/gen80300_sqe.fw, qcom/gen80300_gmu.bin     (GPU, from /vendor/firmware)
qca/msbtfw12.mbn, qca/msbtfw12.tlv, qca/msnv12.bin  (Bluetooth, from the bluetooth image; the rest comes from linux-firmware)
```

Split firmware (`name.mdt` + `name.b00 …`) is joined with `tools/pil-squash.py <image dir> <out dir>`
(the `.bNN` numbers are decimal).

### 4. Audio topology

Copy `audio/Nothing-Phone-4a.m4` into a checkout of [linux-msm/audioreach-topology](https://github.com/linux-msm/audioreach-topology),
compile it with `m4` + `alsatplg` as the other `*.m4` files there, and install the result as
`/lib/firmware/qcom/milos/Nothing-Phone-4a-tplg.bin` in the rootfs.

### 5. Rootfs

```sh
FW_DIR=/path/to/firmware scripts/build-rootfs.sh     # → build/rootfs.tar.gz
```

Needs an aarch64 Linux with `apk` (or a privileged `--platform linux/arm64` Alpine container) and the postmarketOS package signing key.
Default accounts are `root` / `nura` with password **`nura`** — change them.
The stock ModemManager and plasma-dialer from the repository run fine, but only the first SIM is usable; for two SIMs
rebuild both packages with `patches/mm-dsds.patch` and `patches/pd-dsds.patch` (ModemManager 1.25.x, plasma-dialer 6.6.x).

## Boot it

```sh
tools/boot.sh build/nura-boot.img build/rootfs.tar.gz en5     # en5 = the Mac interface of the phone's USB ethernet
tools/nssh                                                    # ssh nura@fe80::ff:fe00:1%en5
```

The first screen is the kernel console, then the rootfs is received (about a minute for ~1 GB over USB 2/3) and Plasma Mobile starts.
Reboot the phone normally to get Android back.

## Warnings

* You are running experimental kernel code on your phone. `fastboot boot` does not write to flash, but a bad kernel can still hang the
  device until you hold the power button. **Never flash** `boot`, `vendor_boot`, `abl` or `xbl` with these images.
* Do not use `iommu.passthrough=1` — it hangs the phone.
* On this device the modem keeps its SIM slot configuration across reboots. Switching the active SIM slot or SIM provisioning from Linux
  (`qmicli --uim-switch-slot`, `--uim-change-provisioning-session`) can leave the phone in a single-SIM mode that Android cannot undo
  from the UI. Avoid touching it unless you know how to restore it.
* The audio topology and the AW88261 patches were tested on one phone only; a wrong amplifier setup can damage speakers. Start with low volume.
* The released boot image includes debug output (`NURA-DBG`, `NURA-TX`) that fills the kernel log.

## Credits

[milos-mainline/linux](https://github.com/milos-mainline/linux) (Milos mainline work), the postmarketOS and Nura projects,
Linaro's [audioreach-topology](https://github.com/linux-msm/audioreach-topology), Nothing's open-source kernel release, and the
Linux kernel, ModemManager and KDE Plasma Mobile developers.

## License

See `LICENSE`: MIT for the scripts and docs; kernel and package patches keep the licenses of the projects they modify.
