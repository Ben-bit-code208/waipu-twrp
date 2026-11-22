# TWRP device tree: waipu.tv 4K Stick (SEI700WP / oppen)

WIP TWRP 11 device tree for the waipu.tv 4K Stick (Amlogic S905Y4, Android 11).
It was generated with `twrpdtgen` from the stock `boot.img` and then adapted.

**This is not a finished, tested recovery.** Use it only with `fastboot boot`
until it has been verified on real hardware.

## Device

| | |
|---|---|
| Codename | `SEI700WP` |
| Board | `oppen` |
| SoC | Amlogic S905Y4 |
| Android | 11 |
| Kernel | `5.4.242-ab6958` (prebuilt, gzip blob from stock `boot.img`) |
| Recovery | recovery-as-boot, no separate `recovery` partition |

## Status / details

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
mka recoveryimage -j"$(nproc)"
```

Output: `out/target/product/SEI700WP/recovery.img`

## Testing (important)

Do **not** flash directly. Boot the image into RAM only:

```sh
fastboot boot out/target/product/SEI700WP/recovery.img
```

If anything goes wrong, simply reboot – the stock `boot_a` partition stays untouched.
Always keep byte-identical backups of `boot_a` and `vendor_boot_a` before any flashing.

## Notes on included files

- `prebuilt/kernel` is the original gzip kernel blob from the stock `boot.img`
  (8,843,069 bytes). Do not replace it with a decompressed `magiskboot` kernel.
- `recovery/root/` contains stock display init files, stock IR remote config,
  BT firmware/modules and the BT HID keylayout for local building.
  The vendor blobs are proprietary; check your local laws before redistributing them.
- No device serial numbers or personal data are included.

## XDA thread

https://xdaforums.com/t/wip-guide-oem-unlock-waipu-tv-4k-stick-sei700wp-oppen-s905y4-no-soldering.4809559/
