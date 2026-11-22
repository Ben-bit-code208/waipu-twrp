# TWRP-Port-Status: waipu.tv 4K Stick (SEI700WP / oppen)

Stand: 2026-11-22

## Was bisher passiert ist

Mit `twrpdtgen` 3.0.0 (venv: `../venv`) wurde aus der **Stock-`boot.img`**
(`/home/bklumki/fw_dump/ota/extracted/boot.img`) ein TWRP-Device-Tree erzeugt:

```
/home/bklumki/fw_dump/twrp_base/device_tree/sei/SEI700WP
```

Das ist ein **Ausgangspunkt**, kein fertiger Port.

## Build-Umgebung (externe 1-TB-Platte)

- Platte: `/dev/sda1` (btrfs, UUID `2d7b00bc-6067-46d0-985b-a572f7bba2f9`),
  eingehängt auf `/mnt/twrp-build` (`subvolid=5`), ~681 GB frei.
- Eigene Subvolume: `/mnt/twrp-build/twrp11` (gehört `bklumki`).
- Installiert: `repo`, `openjdk-11-jdk` (Java 11.0.33.1).
- Umgebung: `/mnt/twrp-build/twrp11/env.sh`
  (`JAVA_HOME`, `PATH`, ccache 50 GB, `ALLOW_MISSING_DEPENDENCIES`).
- Manifest: `minimal-manifest-twrp/platform_manifest_twrp_aosp`, Branch `twrp-11`
  (`repo init -u ... -b twrp-11 --depth=1`).
  Das echte TWRP kommt über `remove.xml → remove-minimal.xml → twrp-extras.xml`
  (u. a. `TeamWin/android_bootable_recovery` und `vendor/twrp`).
- Device-Tree im Source-Tree: `/mnt/twrp-build/twrp11/device/sei/SEI700WP`.
- Build-Skript: `/mnt/twrp-build/twrp11/build_twrp.sh`
  (`lunch twrp_SEI700WP-eng`, `mka bootimage -j4`).
  **Wichtig:** Bei `BOARD_USES_RECOVERY_AS_BOOT := true` erzeugt TWRP 11
  kein `recovery.img`; das Recovery-Image heißt
  `out/target/product/SEI700WP/boot.img`. Das Ziel `recoveryimage` ist
  in diesem Setup leer.
- GitHub-Repo (nur Device-Tree): https://github.com/Ben-bit-code208/waipu-twrp
- Source-Sync abgeschlossen (Log: `/mnt/twrp-build/twrp11/repo-sync.log`).

## Wichtige Erkenntnisse aus der Stock-Ramdisk

- Die `boot.img` enthält die **Stock-Recovery direkt mit** (`init.recovery.amlogic.rc`,
  `res/images/*`, `system/bin/recovery`, `adbd`, `minadbd`).
  Es gibt **keine `recovery`-Partition** – TWRP muss in `boot.img` landen
  (`BOARD_USES_RECOVERY_AS_BOOT := true` ist bereits gesetzt).
- Kernel: `Linux version 5.4.242-ab6958`, Clang 11.0.1, Build 2024-09-20.
- `prebuilt/kernel` ist das **originale gzip-Kernelblob** aus `boot.img`
  (8.843.069 Bytes, SHA-256 `8026f56d...`).
  Die von `magiskboot` entpackte, unkomprimierte Version liegt unter
  `boot_unpack/kernel` (21.313.544 Bytes) – **nicht** für mkbootimg verwenden.
- Die `vendor_boot`-Ramdisk enthält 45 Kernelmodule, u. a. `aml_drm.ko`
  (Display), `aml_irblaster.ko`, `exfat.ko`, `meson_*`. Diese müssen später
  in die Recovery-Ramdisk übernommen werden.
- Dynamische Partitionen (aus `/dev/block/mapper`): `system system_ext vendor product odm`.
  `odm_ext`, `oem`, `param`, `metadata`, `tee` sind physisch.
- `/data` ist FBE + Metadata-Encryption (`fileencryption=aes-256-xts`,
  `keydirectory=/metadata/vold/metadata_encryption`) → ohne Key keine
  nutzbaren Dateien in TWRP, aber Raw-Backup möglich.

## Am generierten Tree korrigiert

1. `BOARD_SEI_DYNAMIC_PARTITIONS_PARTITION_LIST` war leer → gefüllt mit
   `system system_ext vendor product odm`.
2. `TW_THEME` war `portrait_hdpi` → `landscape_hdpi` (TV ist quer).
3. Aus der Stock-Ramdisk übernommen nach `recovery/root/`:
   - `mesondisplay.cfg` + `system/bin/systemcontrol_static` (HDMI-Init,
     sonst schwarzer Bildschirm in Recovery)
   - `sbin/remotecfg`, `remote.cfg`, `remote.tab1-3`, `recovery.kl`
4. TWRP-11-Konvention: `omni_SEI700WP.mk` → `twrp_SEI700WP.mk`,
   `PRODUCT_NAME := twrp_SEI700WP`, Lunch-Ziele `twrp_SEI700WP-*`,
   `vendor/omni/config/common.mk` → `vendor/twrp/config/common.mk`.
5. `recovery.fstab` um dynamische Partitionen, `boot_a`, `vendor_boot_a`,
   `dtbo_a` und `super` ergänzt.
6. Für den ersten Boot-Test: veraltetes `PRODUCT_STATIC_BOOT_CONTROL_HAL`
   und das nicht existierende `bootctrl.SEI700WP` entfernt,
   `AB_OTA_UPDATER := false` und `BOARD_AVB_ENABLE := false` gesetzt.
   Grund: im TWRP-11-Tree gibt es kein passendes bootctrl-HAL. A/B-Slotwechsel
   und AVB müssen später nachgerüstet werden.

## Fernbedienung (Zulip-Frage)

Die Stock-Recovery hat einen **fertigen** Remote-Treiber: `sbin/remotecfg`
mit `remote.cfg`. Das ist aber Amlogics generisches **IR**-Setup
(`work_mode`, `custom_code = 0xfb04`, `meson_rc.h`) – **kein Bluetooth**.

Die waipu-Fernbedienung ist ein **BT-HID-Gerät** (`B18F Keyboard`,
VID `2d01` / PID `c006`, Keylayout `Vendor_2d01_Product_c006.kl`).

Befunde vom Gerät:

- Kernel: `CONFIG_BT=y`, `CONFIG_BT_BREDR=y`, `CONFIG_BT_HCIBTSDIO=y`,
  `CONFIG_BT_HCIUART=y`, `CONFIG_UHID=y`, `CONFIG_HID_GENERIC=y`.
  `CONFIG_BT_HIDP` fehlt.
- BT läuft über **SDIO** (`btmtksdio.ko`, `sdio_bt.ko`, `wlan_mt7663_sdio.ko`),
  nicht UART. Firmware: `mt7663_patch_e2_hdr.bin`, `bt_mt7663.cfg`,
  `EEPROM_MT7663.bin`.
- HAL: `android.hardware.bluetooth@1.0-service-droidlogic` mit
  `libbt-vendor_mtk.so` / `libbluetooth_mtkbt.so`.
- Pairing-Key in Android: `/data/misc/bluedroid/bt_config.conf`.
- In der Stock-Recovery: kein BlueZ, kein BT-Modul, keine BT-Firmware.

Ein fertiger TWRP-BT-Treiber wurde **nicht** gefunden. Die Recherche ist
abgeschlossen; Details, Blobs und Init-Skizze stehen in **`BT_RECOVERY_PLAN.md`**.
Empfohlen wird eine minimale Mgmt/L2CAP→UHID-Brücke (Fluoride verwerfen,
BlueZ nur als Option 2). ADB bleibt in jedem Fall der Fallback.

Die Keylayouts liegen unter `recovery/root/system/usr/keylayout/` und
`recovery/root/vendor/usr/keylayout/`. Die proprietären MT7663-Blobs
(`vendor/firmware/`, `vendor/lib/modules/`, `vendor/etc/bluetooth/bt_vendor.conf`)
sind **nicht** Teil dieses öffentlichen Repos (siehe `.gitignore`).
Für einen lokalen Build müssen sie aus dem eigenen Firmware-Dump nach
`device/sei/SEI700WP/recovery/root/vendor/` kopiert werden.

## Offene Punkte nach dem ersten Build

- Build-Skript und Doku auf `mka bootimage` umgestellt (siehe oben).
- `vendor/twrp/config/common.mk` ist synchronisiert und geprüft.
- `bootctrl.SEI700WP` existiert nicht – A/B vorerst deaktiviert (siehe oben).
- `BOARD_SUPER_PARTITION_*`, `PLATFORM_VERSION := 16.1.0` validieren.
- Display-Module (`aml_drm.ko` etc.) ggf. in die Recovery-Ramdisk legen.
- BT laut `BT_RECOVERY_PLAN.md`: zuerst HCI-Bring-up (`hci0`), dann Brücke.

## Sicherheitsregel

**Nie direkt flashen.** Test immer mit:

```
fastboot boot boot.img
```

(`recovery_as_boot`: das gebaute Image ist `boot.img`.)
Das lädt das Image nur in den RAM. Stock-`boot_a` bleibt unangetastet.
Vor jedem Flash: bytegleiche Backups von `boot_a` und `vendor_boot_a`
liegen bereits in `/home/bklumki/fw_dump/`.

## UI-Reparatur (2026-11-22, Headless)

TWRP bootet und ADB/MTP laufen. Die UI zeigte zunächst nur das Waipu-Logo,
weil `libminuitwrp` beim Amlogic-DRM-`mmap()` abstürzte. Behoben durch:

- `TW_TARGET_USES_DRM := false` (dieses Repo): minuitwrp nutzt jetzt
  `/dev/graphics/fbdev` statt `/dev/dri/card0`.
- `TW_NO_SCREEN_TIMEOUT := true` (dieses Repo): kein 60-Sekunden-Blank.

Zwei zusätzliche Patches liegen **nur lokal im AOSP-Build-Tree**, nicht in
diesem öffentlichen Device-Tree-Repo:

1. `bootable/recovery/minuitwrp/libminuitwrp_defaults.go`
   `-DHAS_DRM` und `graphics_drm.cpp` werden nur noch bei
   `TW_TARGET_USES_DRM := true` aktiviert. Sonst wird `graphics_drm.cpp`
   unabhängig vom Flag einkompiliert und der DRM-Crash bleibt bestehen.
2. `bootable/recovery/data.cpp`
   `tw_mount_system_ro` auf `0` und `tw_never_show_system_ro_page` auf `1`
   setzen, damit der erste „Keep System Read only?“-Dialog nicht erscheint.

Hinweis zum Ramdisk-Cache: Nach Änderung an Dateien in `recovery/root/`
müssen `ramdisk-recovery.cpio`, `ramdisk-recovery.img` und `boot.img`
gelöscht und neu gebaut werden. Andernfalls übernimmt `mka bootimage`
die alten Dateien aus `ramdisk-files.sha256sum`.

Flash auf diesem Gerät: `fastboot boot` wird vom Bootloader ignoriert;
DNL-Memory-Boot ist blockiert. Getestet wurde stattdessen
`adb push ... /tmp/`, dann aus dem laufenden TWRP
`dd if=/tmp/<image> of=/dev/block/by-name/boot_a bs=4M`
und Prüfung mit `sha256sum /dev/block/by-name/boot_a`.

Letztes getestetes Image: `twrp_SEI700WP_boot_uifix4_avb.img`,
SHA-256 `1c302a8b0e52eaf04f753383ab05444da5870a6db811a000d363ce634e84a220`.
Slot `a` ist gesund; Slot `b` bootet auch mit Stock-`boot.img` in eine
Bootloop und darf nicht verwendet werden.

## Backup-/Poweroff-Fixes (2026-11-22)

- `recovery/root/init.recovery.amlogic.rc`
  Der Symlink `/dev/block/boot -> /dev/block/boot_a` fehlt im Original-Device-Tree.
  Ohne ihn scheitert `twrp backup B` mit `Error opening: '' (No such file or
  directory)`, weil `recovery.fstab` `/boot` auf `/dev/block/boot` abbildet, das
  Gerät aber nur `boot_a`/`boot_b` hat. Damit laufen `twrp backup B <name>` und
  `twrp restore ... B` zuverlässig (64 MB, Hash vorher/nachher identisch).
- `recovery/root/system/bin/poweroff.sh`
  Wird von TWRP in `TWFunc::tw_reboot(rb_poweroff)` über
  `check_and_run_script()` automatisch aufgerufen. Setzt beim Poweroff
  `tw_enable_adb=1`, `tw_enable_fastboot=0`, `tw_mount_system_ro=1`,
  `tw_never_show_system_ro_page=1` und `tw_no_screen_timeout=1`.
  Der Guard `/tmp/.twrp_poweroff_done` sorgt dafür, dass ein zweiter Aufruf
  nichts tut. Das Skript ruft bewusst **nicht** selbst `twrp reboot poweroff`
  auf – sonst würde der Hook rekursiv ausgelöst.
- `recovery.fstab`
  `;ro` an den dynamischen Partitionen. Auf diesem Kernel wirkungslos
  (`EXT4-fs (dm-0): couldn't mount RDWR because of unsupported optional
  features (4000)`); RO-Manualmount funktioniert, TWRP-CLI mountet aber
  weiterhin RW. Steht nur zur Dokumentation des Versuchs drin.

Zwei weitere, **nicht in diesem Repo** liegende AOSP-Patches sind im Build-Tree
aktiv: `bootable/recovery/data.cpp` (`tw_mount_system_ro=1`) und
`bootable/recovery/partitionmanager.cpp` (`Change_Mount_Read_Only(true)` in
`Prepare_Super_Volume`). Auch sie konnten den RW-Mountfehler nicht beheben.

Getestetes Image mit Backup-Fix + Poweroff-Hook:
`twrp_SEI700WP_boot_poweroffhook_avb.img`,
SHA-256 `31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704`.
UUID/Hash geprüft, TWRP bootet nach ~17 s mit `Using fbdev graphics.`,
Hook manuell ausgeführt und Guard verifiziert.
