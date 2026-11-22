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
  (`lunch twrp_SEI700WP-eng`, `mka recoveryimage -j4`).
- GitHub-Repo (nur Device-Tree): https://github.com/Ben-bit-code208/waipu-twrp
- Source-Sync läuft mit `repo sync -j4 --no-clone-bundle --fail-fast`
  (Log: `/mnt/twrp-build/twrp11/repo-sync.log`).

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

Die dafür nötigen BT-Blobs und Keylayouts liegen bereits unter
`recovery/root/vendor/...` und `recovery/root/system/usr/keylayout/`
(nur lokal, nicht für öffentliche XDA-Zips).

## Offene Punkte vor dem Build

- Source-Sync abschließen (läuft).
- `vendor/twrp/config/common.mk` ist synchronisiert und geprüft.
- `bootctrl.SEI700WP` existiert nicht – A/B vorerst deaktiviert (siehe oben).
- `BOARD_SUPER_PARTITION_*`, `PLATFORM_VERSION := 16.1.0` validieren.
- Display-Module (`aml_drm.ko` etc.) ggf. in die Recovery-Ramdisk legen.
- BT laut `BT_RECOVERY_PLAN.md`: zuerst HCI-Bring-up (`hci0`), dann Brücke.

## Sicherheitsregel

**Nie direkt flashen.** Test immer mit:

```
fastboot boot twrp.img
```

Das lädt das Image nur in den RAM. Stock-`boot_a` bleibt unangetastet.
Vor jedem Flash: bytegleiche Backups von `boot_a` und `vendor_boot_a`
liegen bereits in `/home/bklumki/fw_dump/`.
