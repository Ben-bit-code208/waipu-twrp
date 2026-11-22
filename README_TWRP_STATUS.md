# TWRP port status: waipu.tv 4K Stick (SEI700WP / oppen)

Updated: 2026-11-22

## What has been done so far

A TWRP device tree was generated from the **stock `boot.img`**
(`/home/bklumki/fw_dump/ota/extracted/boot.img`) with `twrpdtgen` 3.0.0
(venv: `../venv`):

```
/home/bklumki/fw_dump/twrp_base/device_tree/sei/SEI700WP
```

This is a **starting point**, not a finished port.

## Build environment (external 1 TB drive)

- Drive: `/dev/sda1` (btrfs, UUID `2d7b00bc-6067-46d0-985b-a572f7bba2f9`),
  mounted at `/mnt/twrp-build` (`subvolid=5`), ~681 GB free.
- Own subvolume: `/mnt/twrp-build/twrp11` (owned by `bklumki`).
- Installed: `repo`, `openjdk-11-jdk` (Java 11.0.33.1).
- Environment: `/mnt/twrp-build/twrp11/env.sh`
  (`JAVA_HOME`, `PATH`, 50 GB ccache, `ALLOW_MISSING_DEPENDENCIES`).
- Manifest: `minimal-manifest-twrp/platform_manifest_twrp_aosp`, branch `twrp-11`
  (`repo init -u ... -b twrp-11 --depth=1`).
  Actual TWRP is pulled in via `remove.xml → remove-minimal.xml → twrp-extras.xml`
  (among others `TeamWin/android_bootable_recovery` and `vendor/twrp`).
- Device tree in the source tree: `/mnt/twrp-build/twrp11/device/sei/SEI700WP`.
- Build script: `/mnt/twrp-build/twrp11/build_twrp.sh`
  (`lunch twrp_SEI700WP-eng`, `mka bootimage -j4`).
  **Important:** With `BOARD_USES_RECOVERY_AS_BOOT := true`, TWRP 11 does not
  produce a `recovery.img`; the recovery image is
  `out/target/product/SEI700WP/boot.img`. The `recoveryimage` target is empty
  in this setup.
- GitHub repo (device tree only): https://github.com/Ben-bit-code208/waipu-twrp
- Source sync complete (log: `/mnt/twrp-build/twrp11/repo-sync.log`).

## Key findings from the stock ramdisk

- `boot.img` contains the **stock recovery directly** (`init.recovery.amlogic.rc`,
  `res/images/*`, `system/bin/recovery`, `adbd`, `minadbd`).
  There is **no `recovery` partition** – TWRP has to go into `boot.img`
  (`BOARD_USES_RECOVERY_AS_BOOT := true` is already set).
- Kernel: `Linux version 5.4.242-ab6958`, Clang 11.0.1, built 2024-09-20.
- `prebuilt/kernel` is the **original gzip kernel blob** from `boot.img`
  (8,843,069 bytes, SHA-256 `8026f56d...`).
  The decompressed version extracted with `magiskboot` is at
  `boot_unpack/kernel` (21,313,544 bytes) – **do not** use it with mkbootimg.
- The `vendor_boot` ramdisk contains 45 kernel modules, including `aml_drm.ko`
  (display), `aml_irblaster.ko`, `exfat.ko`, `meson_*`. These need to be copied
  into the recovery ramdisk later.
- Dynamic partitions (from `/dev/block/mapper`): `system system_ext vendor product odm`.
  `odm_ext`, `oem`, `param`, `metadata`, `tee` are physical.
- `/data` uses FBE plus metadata encryption (`fileencryption=aes-256-xts`,
  `keydirectory=/metadata/vold/metadata_encryption`) → without the key there
  are no usable files in TWRP, but a raw backup is possible.

## Corrections made to the generated tree

1. `BOARD_SEI_DYNAMIC_PARTITIONS_PARTITION_LIST` was empty → filled with
   `system system_ext vendor product odm`.
2. `TW_THEME` was `portrait_hdpi` → `landscape_hdpi` (the TV is landscape).
3. Copied from the stock ramdisk into `recovery/root/`:
   - `mesondisplay.cfg` + `system/bin/systemcontrol_static` (HDMI init,
     otherwise black screen in recovery)
   - `sbin/remotecfg`, `remote.cfg`, `remote.tab1-3`, `recovery.kl`
4. TWRP 11 conventions: `omni_SEI700WP.mk` → `twrp_SEI700WP.mk`,
   `PRODUCT_NAME := twrp_SEI700WP`, lunch targets `twrp_SEI700WP-*`,
   `vendor/omni/config/common.mk` → `vendor/twrp/config/common.mk`.
5. Added dynamic partitions, `boot_a`, `vendor_boot_a`, `dtbo_a` and `super`
   to `recovery.fstab`.
6. For the first boot test: removed the obsolete `PRODUCT_STATIC_BOOT_CONTROL_HAL`
   and the non-existent `bootctrl.SEI700WP`, set `AB_OTA_UPDATER := false` and
   `BOARD_AVB_ENABLE := false`.
   Reason: the TWRP 11 tree has no matching bootctrl HAL. A/B slot switching
   and AVB need to be added back later.

## Remote control (Zulip question)

The stock recovery has a **ready-made** remote driver: `sbin/remotecfg` with
`remote.cfg`. However, this is Amlogic's generic **IR** setup
(`work_mode`, `custom_code = 0xfb04`, `meson_rc.h`) – **not Bluetooth**.

The waipu remote is a **BT HID device** (`B18F Keyboard`,
VID `2d01` / PID `c006`, keylayout `Vendor_2d01_Product_c006.kl`).

Findings from the device:

- Kernel: `CONFIG_BT=y`, `CONFIG_BT_BREDR=y`, `CONFIG_BT_HCIBTSDIO=y`,
  `CONFIG_BT_HCIUART=y`, `CONFIG_UHID=y`, `CONFIG_HID_GENERIC=y`.
  `CONFIG_BT_HIDP` is missing.
- BT runs over **SDIO** (`btmtksdio.ko`, `sdio_bt.ko`, `wlan_mt7663_sdio.ko`),
  not UART. Firmware: `mt7663_patch_e2_hdr.bin`, `bt_mt7663.cfg`,
  `EEPROM_MT7663.bin`.
- HAL: `android.hardware.bluetooth@1.0-service-droidlogic` with
  `libbt-vendor_mtk.so` / `libbluetooth_mtkbt.so`.
- Pairing key in Android: `/data/misc/bluedroid/bt_config.conf`.
- In the stock recovery: no BlueZ, no BT module, no BT firmware.

No ready-made TWRP BT driver was found. The research is complete; details,
blobs and an init sketch are in **`BT_RECOVERY_PLAN.md`**.
A minimal Mgmt/L2CAP → UHID bridge is recommended (drop Fluoride,
BlueZ only as option 2). ADB remains the fallback in any case.

The keylayouts are under `recovery/root/system/usr/keylayout/` and
`recovery/root/vendor/usr/keylayout/`. The proprietary MT7663 blobs
(`vendor/firmware/`, `vendor/lib/modules/`, `vendor/etc/bluetooth/bt_vendor.conf`)
are **not** part of this public repo (see `.gitignore`).
For a local build they must be copied from your own firmware dump to
`device/sei/SEI700WP/recovery/root/vendor/`.

## Open items after the first build

- Build script and docs switched to `mka bootimage` (see above).
- `vendor/twrp/config/common.mk` is synced and checked.
- `bootctrl.SEI700WP` does not exist – A/B disabled for now (see above).
- Validate `BOARD_SUPER_PARTITION_*`, `PLATFORM_VERSION := 16.1.0`.
- Possibly add display modules (`aml_drm.ko` etc.) to the recovery ramdisk.
- BT per `BT_RECOVERY_PLAN.md`: first HCI bring-up (`hci0`), then the bridge.

## Safety rule

**Never flash directly.** Test with:

```
fastboot boot boot.img
```

(`recovery_as_boot`: the built image is `boot.img`.)
This only loads the image into RAM. Stock `boot_a` stays untouched.
Byte-identical backups of `boot_a` and `vendor_boot_a` already exist in
`/home/bklumki/fw_dump/`.

Note: on this particular device the bootloader ignores `fastboot boot` and
DNL memory boot is blocked. The working method is documented under
"UI repair" below.

## UI repair (2026-11-22, headless)

TWRP boots and ADB/MTP work. Initially the UI only showed the waipu logo
because `libminuitwrp` crashed on the Amlogic DRM `mmap()`. Fixed by:

- `TW_TARGET_USES_DRM := false` (this repo): minuitwrp now uses
  `/dev/graphics/fbdev` instead of `/dev/dri/card0`.
- `TW_NO_SCREEN_TIMEOUT := true` (this repo): no 60-second blank.

Two additional patches exist **only locally in the AOSP build tree**, not in
this public device-tree repo:

1. `bootable/recovery/minuitwrp/libminuitwrp_defaults.go`
   `-DHAS_DRM` and `graphics_drm.cpp` are only enabled when
   `TW_TARGET_USES_DRM := true`. Otherwise `graphics_drm.cpp` is compiled in
   regardless of the flag and the DRM crash remains.
2. `bootable/recovery/data.cpp`
   Set `tw_mount_system_ro` to `1` and `tw_never_show_system_ro_page` to `1`
   so the initial "Keep System Read only?" dialog does not appear.

Ramdisk cache note: after changing files in `recovery/root/` you must delete
`ramdisk-recovery.cpio`, `ramdisk-recovery.img` and `boot.img` and rebuild.
Otherwise `mka bootimage` reuses the old files listed in
`ramdisk-files.sha256sum`.

Flashing on this device: `fastboot boot` is ignored by the bootloader;
DNL memory boot is blocked. The tested method is instead
`adb push ... /data/local/tmp/`, then from the running TWRP
`dd if=/data/local/tmp/<image> of=/dev/block/by-name/boot_a bs=4M`
and verification with `sha256sum /dev/block/by-name/boot_a`.

Earlier tested image: `twrp_SEI700WP_boot_uifix4_avb.img`,
SHA-256 `1c302a8b0e52eaf04f753383ab05444da5870a6db811a000d363ce634e84a220`.
Slot `a` is healthy; slot `b` bootloops even with the stock `boot.img` and
must not be used.

## Backup / poweroff fixes (2026-11-22)

- `recovery/root/init.recovery.amlogic.rc`
  The symlink `/dev/block/boot -> /dev/block/boot_a` is missing from the
  original device tree. Without it `twrp backup B` fails with
  `Error opening: '' (No such file or directory)` because `recovery.fstab`
  maps `/boot` to `/dev/block/boot`, while the device only has
  `boot_a`/`boot_b`. With the link, `twrp backup B <name>` and
  `twrp restore ... B` work reliably (64 MB, hash identical before/after).
- `recovery/root/system/bin/poweroff.sh`
  Automatically called by TWRP from `TWFunc::tw_reboot(rb_poweroff)` via
  `check_and_run_script()`. On poweroff it sets `tw_enable_adb=1`,
  `tw_enable_fastboot=0`, `tw_mount_system_ro=1`,
  `tw_never_show_system_ro_page=1` and `tw_no_screen_timeout=1`.
  The `/tmp/.twrp_poweroff_done` guard makes a second call a no-op. The script
  deliberately does **not** call `twrp reboot poweroff` itself – that would
  trigger the hook recursively.
- `recovery.fstab`
  `;ro` on the dynamic partitions. This is a no-op on this kernel
  (`EXT4-fs (dm-0): couldn't mount RDWR because of unsupported optional
  features (4000)`); RO manual mount works, but the TWRP CLI still mounts RW.
  It is kept only to document the attempt.

Two more AOSP patches, **not in this repo**, are active in the build tree:
`bootable/recovery/data.cpp` (`tw_mount_system_ro=1`) and
`bootable/recovery/partitionmanager.cpp` (`Change_Mount_Read_Only(true)` in
`Prepare_Super_Volume`). Neither could fix the RW mount error either.

Tested image with the backup fix + poweroff hook:
`twrp_SEI700WP_boot_poweroffhook_avb.img`,
SHA-256 `31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704`.
Hash verified, TWRP boots after ~17 s with `Using fbdev graphics.`,
hook executed manually and guard verified.
