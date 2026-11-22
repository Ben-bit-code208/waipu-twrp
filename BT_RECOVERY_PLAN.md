# BT remote in TWRP – research & plan

Updated: 2026-11-22

## Research result

There is **no ready-made BT HID driver for TWRP 11 / Amlogic / MT7663** that
could simply be dropped in. Only building blocks were found:

- [CoreELEC/linux-amlogic `btmtksdio.c`](https://github.com/CoreELEC/linux-amlogic/blob/5.15.196_20260225/drivers/bluetooth/btmtksdio.c)
  – kernel driver, no recovery integration.
- [CoreELEC/remotes](https://github.com/CoreELEC/remotes) +
  [wiki: Bluetooth remotes](http://wiki.coreelec.org/remote:rr_bluetooth)
  – BlueZ in userspace, not in TWRP.
- [abrasive/tinyhidd](https://github.com/abrasive/tinyhidd) – BTstack + UHID,
  no BlueZ/D-Bus/kernel BT.
- [bluekitchen/btstack `hid_host_demo.c`](https://github.com/bluekitchen/btstack/blob/master/example/hid_host_demo.c)
  – Classic HID host with boot protocol fallback.
- [zampierilucas/kindle-hid-passthrough](https://github.com/zampierilucas/kindle-hid-passthrough)
  – userspace BT → UHID.

## Evaluation of the options

| Option | Verdict | Reason |
|---|---|---|
| Native Fluoride / `system/bt` | ❌ discard | HID host depends on `com.android.bluetooth`, JNI and the HIDL HAL. No standalone daemon for recovery. |
| BlueZ + key conversion | ⚠️ possible but heavier | Needs GLib ≥ 2.28 + D-Bus ≥ 1.6. Important: set `UserspaceHID=true` ([input.conf](https://raw.githubusercontent.com/bluez/bluez/5.55/profiles/input/input.conf)), otherwise kernel `CONFIG_BT_HIDP` would be required. |
| Minimal Mgmt/L2CAP → UHID bridge | ✅ recommended | Uses existing `CONFIG_UHID` / `CONFIG_HID_GENERIC`; no `HIDP`, no D-Bus, no GLib. Boot protocol is sufficient for a keyboard-style remote. |

`CONFIG_BT_HIDP` is missing from the stock kernel and cannot be rebuilt without
kernel sources – userspace HID avoids it.

## Files already staged locally

Under `recovery/root/` in the device tree (both in the source tree and in the
generated tree):

```text
vendor/lib/modules/btmtksdio.ko          326440 B
vendor/lib/modules/sdio_bt.ko             31296 B
vendor/lib/modules/wlan_mt7663_sdio.ko  3397976 B
vendor/firmware/mt7663_patch_e2_hdr.bin  278558 B
vendor/firmware/bt_mt7663.cfg              1015 B
vendor/firmware/EEPROM_MT7663.bin          1536 B
vendor/usr/keylayout/Vendor_2d01_Product_c006.kl  1730 B
system/usr/keylayout/Vendor_2d01_Product_c006.kl  1730 B
vendor/etc/bluetooth/bt_vendor.conf        271 B
```

`aml_sdio.ko` does **not** exist on the device – `init.amlogic.bluetooth.rc`
references it, but the module is not shipped. The init sketch below therefore
leaves it out.

## Concrete HCI bring-up (second research pass, 2026-11-22)

Init rules and module aliases extracted from `vendor.img`:

- `btmtksdio.ko` has the SDIO aliases `v037Ad7663` (function 2) and no module
  parameters. It is loaded via `vendor.sys.mtkbtdriver=true`.
- `wlan_mt7663_sdio.ko` has the alias `v037Ad7603` (function 1, WLAN).
- `sdio_bt.ko` only has the parameter `chip_name`; stock passes **no** value.
  `aml_sdio.ko` is missing; some of its symbols are built into the kernel.
- **`btmtksdio.ko` requests `bt.cfg`, not `bt_mt7663.cfg`.** Both are in
  `vendor.img` but are **not** byte-identical:
  `RESET_STACK_AFTER_WOBLE` is `1` in `bt.cfg` and `0` in `bt_mt7663.cfg`.
  Use the real `bt.cfg` from the dump, do not just rename the other file.
- Further `request_firmware()` names: `mt7663_patch_e2_hdr.bin`,
  `EEPROM_MT7663.bin`, `wifi.cfg`, `woble_setting_7663.bin`,
  `WIFI_RAM_CODE_MT7663.bin`, `TxPwrLimit_MT76x8.dat`.

The required files are now staged locally under
`/home/bklumki/fw_dump/bt_recovery_firmware/` (not in the public repo).

Order in recovery (set the stock props only, do not import the stock RC,
otherwise `insmod` runs twice):

```sh
mkdir -p /vendor/firmware /vendor/lib/modules /data/misc/bluetooth
chmod 0666 /dev/uhid
echo -n /vendor/firmware > /sys/module/firmware_class/parameters/path

insmod /vendor/lib/modules/wlan_mt7663_sdio.ko   # WLAN/RAM patch first
sleep 2
insmod /vendor/lib/modules/sdio_bt.ko            # may fail on unresolved symbols
insmod /vendor/lib/modules/btmtksdio.ko          # -> hci0

setprop vendor.sys.amlbtsdiodriver true
setprop vendor.sys.mtkbtdriver true
setprop persist.vendor.bt_module btmtksdio
```

Success criterion and diagnostics:

```sh
ls -l /sys/class/bluetooth/hci0
cat /sys/class/bluetooth/hci0/address
for d in /sys/bus/sdio/devices/*; do cat "$d/uevent"; done   # 037A:7603 + 037A:7663
dmesg | grep -iE 'btmtk|sdio|wmt|firmware|hci0|mmc2'
```

Important log lines: `request_firmware(... mt7663_patch_e2_hdr.bin)`,
`patch downoad finish`, `set driver own success`, `hci0`.
The ROM patch is shared with WLAN via WMT – if WLAN holds the patch, BT may
fail with `Firmware already downloaded` / `wmt command timed out`; in that
case unload both modules and load WLAN → BT again.
`bt_vendor.conf` points at `/dev/ttyS1` and is the **UART** variant – do not
use it as a template for SDIO.

**Note:** These are proprietary vendor blobs. Only use them locally for
building; do not put them in a public XDA attachment.

## Init sketch (NOT ACTIVATED YET)

The following lines are a draft for `init.recovery.amlogic.rc`. They will only
be added once the bridge exists and HCI bring-up works.

```rc
on early-init
    mkdir /vendor 0755 root root
    mkdir /vendor/firmware 0755 root root
    mkdir /vendor/lib/modules 0755 root root
    mkdir /data/misc/bluetooth 0700 root root
    chmod 0666 /dev/uhid
    write /sys/module/firmware_class/parameters/path /vendor/firmware

on init
    # Order matters: WLAN/BT share SDIO
    insmod /vendor/lib/modules/wlan_mt7663_sdio.ko
    insmod /vendor/lib/modules/sdio_bt.ko
    insmod /vendor/lib/modules/btmtksdio.ko
    setprop vendor.sys.mtkbtdriver true
    setprop vendor.sys.amlbtsdiodriver true

service btremote /vendor/bin/bt-hid-bridge
    class late_start
    user root
    group root net_admin bluetooth
    seclabel u:r:recovery:s0
    oneshot
    disabled
```

Prefer explicit `insmod` lines over `import /vendor/etc/init/bluetooth.rc`:
the stock RC sets properties that are not evaluated in recovery.

## Pairing key

Android stores the link key in `/data/misc/bluedroid/bt_config.conf`
(`LinkKey`, `LinkKeyType`, `PinLength`). With FBE/BFU and no decryption the
file is not readable in TWRP → extract the key **beforehand** and put it in
the ramdisk. See [Android Forensics article](https://www.androidforensics.org/en/artifacts/bluetooth-bt-config).

For BlueZ: `/var/lib/bluetooth/<adapter>/<remote>/info`, section `[LinkKey]`
with `Key=` (32 hex characters), `Type=`, `PINLength=`
([BlueZ settings storage](https://bluez.readthedocs.io/en/latest/settings-storage/)).
For the Mgmt API: `Load Link Keys (0x0012)`, key type `0x00`–`0x08`
([mgmt-api.txt](https://raw.githubusercontent.com/bluez/bluez/5.55/doc/mgmt-api.txt)).

**Trap:** The adapter MAC must match the stored MAC, otherwise the key is
discarded.

## Smallest bridge (recommended)

1. HCI bring-up: load modules + firmware, `hci0` must appear.
2. Mgmt socket: `Powered`, `Pairable`, optionally `Load Link Keys` (`CAP_NET_ADMIN`).
3. L2CAP connect on PSM `0x11` (HID Control) / `0x13` (Interrupt).
4. Parse boot protocol reports → `UHID_CREATE2` / `UHID_INPUT` to `/dev/uhid`.
5. Keep the keylayout `Vendor_2d01_Product_c006.kl` active (already staged).

## Pitfalls

- **SELinux:** recovery is usually permissive; if not: `seclabel u:r:recovery:s0`
  plus rules for `/dev/uhid`, the Mgmt socket and L2CAP (`net_admin`).
- **/data encryption:** see above.
- **Firmware path:** without a `/vendor` mount, set `firmware_class.path` explicitly.
- **UHID permissions:** `/dev/uhid` must be writable.
- **MT7663 probe order:** load `wlan_mt7663_sdio.ko` before `btmtksdio.ko`,
  otherwise `hci0` will not appear.
- **No Java framework:** Fluoride/HID host fails on `com.android.bluetooth`
  + JNI – therefore discard it.

## Recommended order

1. **HCI bring-up first**: verify modules + firmware + `hci0`. If that fails,
   everything else is moot.
2. **Mgmt/L2CAP/UHID bridge** using the boot protocol (smallest version:
   `UHID_INPUT` only, no long-term keys).
3. **Inject the pairing key** from a decrypted `bt_config.conf`.
4. **BlueZ only** if the bridge is not enough and D-Bus/GLib can be made
   available (`UserspaceHID=true`!).
5. **Do not attempt Fluoride.**

Realistically this is a from-scratch build, not dropping in a finished driver.
The hurdle is not HID but the SDIO/firmware bring-up of the MT7663 in the
recovery kernel.
