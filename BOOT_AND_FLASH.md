# Boot and flash guide: waipu.tv 4K Stick (SEI700WP / oppen)

All commands below were tested on:

| Item | Value |
|---|---|
| Bootloader | `01.01.240422.151641` |
| Android | 11, security patch `2024-08-05` |
| SoC | Amlogic S905Y4 |
| Active slot | `_a` |
| USB IDs | DNL `1b8e:c004`, U-Boot fastboot `18d1:0d02`, ADB `18d1:4ee7`, sideload `18d1:d001` |

---

## 0. Read this first

- **Only use slot `a`.** Slot `b` bootloops even with a stock `boot.img`. Do not
  flash, wipe or switch to slot `b`.
- This is **recovery-as-boot**: there is no `recovery` partition. The built image
  is `boot.img`, not `recovery.img`.
- Keep byte-identical backups of `boot_a`, `vendor_boot_a` and `misc` before any
  flash. On the tested device they live in `/home/bklumki/fw_dump/`.
- `fastboot flashing unlock` wipes `userdata` and `metadata`. Do it only once,
  with nothing you need on the device.
- The stick has **no working RTC**. After every boot the clock is 1970; set it
  in each ADB session with `adb shell date @$(date +%s)`.

---

## Prebuilt image (skip sections 2 and 3)

A ready-to-flash image is attached to the
[release 0.0.1](https://github.com/Ben-bit-code208/waipu-twrp/releases/tag/0.0.1).
Use it if you do not want to build locally; the AVB footer is already reattached.

```
twrp_SEI700WP_boot_poweroffhook_avb.img
SHA-256: 31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704
```

Verify it on the PC before pushing it to the device:

```bash
sha256sum twrp_SEI700WP_boot_poweroffhook_avb.img
# 31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704
```

It targets slot `a` only. If the hash matches, continue with section 4.

---

## 1. OEM unlock (one time)

`fastboot oem ...` does not work in U-Boot fastboot – every variant returns
`oem unlock fail`. The unlock requires the Amlogic DNL path. The full guide with
the USB helper script is in the XDA thread (see `README.md`); short version:

```bash
# 1. From Android, with USB debugging authorized:
adb reboot update
sleep 15
lsusb | grep -i 1b8e          # expect: ID 1b8e:c004 (DNL mode)

# 2. Bypass the secure-boot whitelist. The '&&' is essential:
sudo python3 dnl_send.py "oem printenv && setenv oemlock unlock && saveenv"
# expect: b'OKAY' (the trailing USBTimeoutError is normal)

# 3. Reboot from DNL into U-Boot fastboot:
sudo ./adnl reboot bootloader
sleep 10
lsusb | grep -i 18d1          # expect: ID 18d1:0d02
fastboot devices

# 4. Unlock:
fastboot flashing unlock
fastboot getvar unlocked      # unlocked: yes
fastboot getvar secure        # secure: no
fastboot reboot
```

Afterwards:

```bash
adb shell getprop ro.boot.verifiedbootstate   # orange
adb shell getprop ro.boot.vbmeta.device_state # unlocked
```

Do **not** run `fastboot flashing lock` afterwards unless you deliberately want
to relock.

---

## 2. Build the image

```sh
mkdir twrp11 && cd twrp11
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git \
    -b twrp-11 --depth=1
repo sync -j4 --no-clone-bundle --fail-fast
git clone https://github.com/Ben-bit-code208/waipu-twrp.git device/sei/SEI700WP

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export ALLOW_MISSING_DEPENDENCIES=true

. build/envsetup.sh
lunch twrp_SEI700WP-eng
mka bootimage -j4
```

Output: `out/target/product/SEI700WP/boot.img`.
The `recoveryimage` target is empty with `BOARD_USES_RECOVERY_AS_BOOT := true`.

**Ramdisk cache trap:** after changing anything in `recovery/root/`, delete
`ramdisk-recovery.cpio`, `ramdisk-recovery.img` and `boot.img` before rebuilding,
otherwise the old files from `ramdisk-files.sha256sum` are reused. Also make sure
`system/lib/libminuitwrp.so` is in `recovery/root/`, `ramdisk-files.txt` and
`ramdisk-files.sha256sum` – without it the UI crashes at the waipu logo.

---

## 3. Reattach the AVB footer

`mka bootimage` produces a bare image. The bootloader needs the stock AVB vbmeta
and footer, otherwise the image is not accepted. Run this from the build root
after every build:

```bash
python3 - <<'PY'
import struct, hashlib

src   = 'out/target/product/SEI700WP/boot.img'
stock = '/home/bklumki/fw_dump/ota/extracted/boot.img'
out   = 'twrp_SEI700WP_boot_avb.img'

data = open(src, 'rb').read()
orig = len(data)
stock_data = open(stock, 'rb').read()

footer = stock_data[-64:]
assert footer[:4] == b'AVBf', 'stock image has no AVB footer'
vb_off  = struct.unpack('>Q', footer[20:28])[0]
vb_size = struct.unpack('>Q', footer[28:36])[0]
vb = bytearray(stock_data[vb_off:vb_off + vb_size])

# Update the hashtree descriptor in vbmeta: image size + hash of the new image.
desc = 256
salt = bytes(vb[desc + 136:desc + 168])
digest = hashlib.sha256(salt + data).digest()
struct.pack_into('!Q', vb, desc + 16, orig)
vb[desc + 168:desc + 200] = digest

img = bytearray(len(stock_data))
img[:orig] = data
img[orig:orig + vb_size] = vb

new_footer = bytearray(64)
new_footer[:4] = b'AVBf'
struct.pack_into('>I', new_footer, 4, 1)          # version
struct.pack_into('>I', new_footer, 8, 0)          # flags
struct.pack_into('>Q', new_footer, 12, orig)      # image size
struct.pack_into('>Q', new_footer, 20, orig)      # vbmeta offset
struct.pack_into('>Q', new_footer, 28, vb_size)   # vbmeta size
img[-64:] = new_footer

open(out, 'wb').write(img)
print('sha256', hashlib.sha256(img).hexdigest())
PY
```

Last verified output: `twrp_SEI700WP_boot_poweroffhook_avb.img`,
SHA-256 `31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704`.

---

## 4. Boot methods

### What does NOT work on this device

```bash
fastboot boot boot.img     # ignored by the bootloader
```

DNL memory boot is blocked too. Stock OTA sideload fails with a footer/signature
error. Do not waste time on these.

### What works: flash from a running TWRP

This assumes TWRP is already running (from a previous flash) and ADB is available.
If the device currently boots Android, temporarily flash the stock `boot.img`
first (see section 6), boot into Android, then use `adb reboot recovery` only if
you already have TWRP in `boot_a`.

```bash
HOST_EPOCH=$(date +%s)
adb shell "date @$HOST_EPOCH"       # fix the 1970 clock

adb push twrp_SEI700WP_boot_avb.img /data/local/tmp/twrp_new.img

adb shell 'dd if=/data/local/tmp/twrp_new.img of=/dev/block/by-name/boot_a bs=4M'
adb shell sync

# Must match the SHA-256 printed by the build step:
adb shell sha256sum /dev/block/by-name/boot_a
```

Then reboot:

```bash
adb reboot
```

TWRP should come up after about 17 s. Check:

```bash
adb shell getprop ro.twrp.version          # 3.7.0_11-0
adb shell 'grep -m1 "Using .* graphics" /tmp/recovery.log'   # Using fbdev graphics.
adb shell sha256sum /dev/block/by-name/misc # 1c16ac591e620d5553b4ab0ef839ad11843c8fee4490462e5f6252b674eb53da
```

`misc` must stay byte-identical (`boot-recovery` at offset 0, `_a`/`BCAB` at
`0x800`). Never wipe `misc`.

---

## 5. First-boot checklist over ADB

```bash
adb shell twrp --version
adb shell twrp set tw_mount_system_ro 1

# Backup/restore of boot (the /dev/block/boot -> boot_a symlink makes this work):
adb shell 'mount -t tmpfs -o size=512m tmpfs /sdcard'   # /data is FBE encrypted
adb shell twrp backup B checklist
adb shell twrp restore /sdcard/TWRP/BACKUPS/<serial>/checklist B
adb shell sha256sum /dev/block/by-name/boot_a           # unchanged

# ADB backup/restore:
adb backup --twrp -f checklist.ab boot
adb restore checklist.ab

# Sideload a regular flashable zip:
adb shell twrp sideload
adb sideload checklist_noop.zip
adb reboot recovery

# Reboots:
adb shell twrp reboot recovery
adb shell twrp reboot bootloader
fastboot continue

# USB modes:
adb shell setprop sys.usb.config mtp,adb
adb shell setprop sys.usb.config adb
```

`/sdcard` is only a tmpfs here (no µSD slot, `/data` is FBE encrypted without a
key), so TWRP backups do not survive a reboot. Use `adb backup --twrp` for
persistent copies on the PC.

---

## 6. Returning to Android

With TWRP installed in `boot_a`, `adb shell twrp reboot system` boots back into
TWRP – that is expected, because TWRP *is* `boot_a`. To boot Android, flash the
stock image back temporarily:

```bash
adb push /home/bklumki/fw_dump/ota/extracted/boot.img /data/local/tmp/stock_boot.img
adb shell 'dd if=/data/local/tmp/stock_boot.img of=/dev/block/by-name/boot_a bs=4M'
adb shell sync
adb reboot
```

Stock `boot_a` SHA-256: `9e52620ce0c060aebed5bdf3d2d423b983e6791f49b84cd4f886c76aa9181ce8`.

Important: several waipu services keep the device from suspending properly.
Under Android, suspend them after each boot:

```bash
adb shell pm suspend com.nes.skywayclient
adb shell pm suspend com.nes.leanbacklauncher.partnercustomizer
adb shell pm suspend com.nes.remoteota.waipu
adb shell pm suspend com.nes.coreservice
```

---

## 7. Poweroff behaviour

`recovery/root/system/bin/poweroff.sh` is called automatically by TWRP when
powering off. It sets:

```
tw_enable_adb=1
tw_enable_fastboot=0
tw_mount_system_ro=1
tw_never_show_system_ro_page=1
tw_no_screen_timeout=1
```

A `/tmp/.twrp_poweroff_done` guard makes repeated calls a no-op. The script must
never call `twrp reboot poweroff` itself, or the hook recurses.

Test it without actually powering off:

```bash
adb shell /system/bin/poweroff.sh
adb shell ls -l /tmp/.twrp_poweroff_done
adb shell /system/bin/poweroff.sh     # silent: guard worked
```
