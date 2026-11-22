# TWRP device tree: waipu.tv 4K Stick (SEI700WP / oppen)

WIP TWRP 11 device tree for the waipu.tv 4K Stick (Amlogic S905Y4, Android 11).
It was generated with `twrpdtgen` from the stock `boot.img` and then adapted.

**This is not a finished, tested recovery.** Boot and flash only with the
procedure in `BOOT_AND_FLASH.md`. Slot `b` is broken – use slot `a` only.

## Device

| | |
|---|---|
| Codename | `SEI700WP` |
| Board | `oppen` |
| SoC | Amlogic S905Y4 |
| Android | 11 |
| Kernel | `5.4.242-ab6958` (prebuilt, gzip blob from stock `boot.img`) |
| Recovery | recovery-as-boot, no separate `recovery` partition |

## Prebuilt image

If you do not want to build yourself, a ready-to-flash image is attached to the
[latest release](https://github.com/Ben-bit-code208/waipu-twrp/releases/latest):

| | |
|---|---|
| Asset | `twrp_SEI700WP_boot_poweroffhook_avb.img` |
| SHA-256 | `31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704` |
| Target | slot `a` only (`/dev/block/by-name/boot_a`) |
| TWRP | `3.7.0_11-0`, fbdev graphics, ADB enabled |

The AVB footer is already reattached. Skip sections 2 and 3 of
`BOOT_AND_FLASH.md` and go straight to section 4. Verify the hash before
flashing:

```sh
sha256sum twrp_SEI700WP_boot_poweroffhook_avb.img
# 31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704
```

## Status / details

- `BOOT_AND_FLASH.md` – OEM unlock, build, AVB footer, flashing and boot tests
- `README_TWRP_STATUS.md` – port status, build environment, findings
- `BT_RECOVERY_PLAN.md` – Bluetooth remote research and implementation plan

The stock remote driver in the recovery ramdisk (`sbin/remotecfg`) is **IR only**.
The included waipu remote is BT HID (`B18F Keyboard`, `2d01:c006`), so BT support
requires additional work (see `BT_RECOVERY_PLAN.md`). ADB is the fallback.

## Building

Tested build layout (adjust paths as needed):

```sh
mkdir twrp11 && cd twrp11
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git \
    -b twrp-11 --depth=1
repo sync -j4
git clone https://github.com/Ben-bit-code208/waipu-twrp.git device/sei/SEI700WP

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export ALLOW_MISSING_DEPENDENCIES=true

. build/envsetup.sh
lunch twrp_SEI700WP-eng
mka bootimage -j"$(nproc)"
```

Output: `out/target/product/SEI700WP/boot.img` (recovery-as-boot).
The AVB footer must be reattached before flashing; see `BOOT_AND_FLASH.md`.

## Testing (important)

`fastboot boot` is ignored by this device's bootloader, and DNL memory boot is
blocked. See `BOOT_AND_FLASH.md` for the method that actually works: push the
image over ADB and write it to `boot_a` from a running TWRP.

Always keep byte-identical backups of `boot_a`, `vendor_boot_a` and `misc`
before any flashing, and never use slot `b`.

## Notes on included files

- `prebuilt/kernel` is the original gzip kernel blob from the stock `boot.img`
  (8,843,069 bytes). Do not replace it with a decompressed `magiskboot` kernel.
- `recovery/root/` contains stock display init files, stock IR remote config,
  BT firmware/modules and the BT HID keylayout for local building.
  The vendor blobs are proprietary; check your local laws before redistributing them.
- No device serial numbers or personal data are included.

## XDA thread

https://xdaforums.com/t/wip-guide-oem-unlock-waipu-tv-4k-stick-sei700wp-oppen-s905y4-no-soldering.4809559/
