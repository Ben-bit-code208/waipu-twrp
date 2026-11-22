# First boot test checklist (SEI700WP / waipu.tv 4K Stick)

This image is booted **temporarily** only. Never flash it for the first test.

## 1. Host preparation

```bash
IMG=/mnt/twrp-build/twrp11/out/target/product/SEI700WP/boot.img
sha256sum "$IMG"
adb devices
adb reboot bootloader
fastboot devices
fastboot boot "$IMG"
```

Do **not** use `fastboot flash boot`, `flash recovery` or any `erase` command.

## 2. After TWRP has booted

```bash
adb devices                      # must show ... recovery
adb shell twrp --version
adb shell getprop ro.twrp.version
adb shell cat /proc/version       # must still be 5.4.242-ab6958 (stock kernel)
adb shell ls -l /dev/block/by-name/
adb shell cat /etc/recovery.fstab
adb shell mount /system
adb shell mount /vendor
adb shell ls /system/bin | head
```

Check on the TV/HDMI output: TWRP UI visible, landscape, touch/remote input.

## 3. Do NOT do on the first test

- No wipe, no factory reset, no format.
- No write to `userdata`, `metadata` or `super`.
- No flashing of any partition.
- Do not install Magisk or any zip yet.

## 4. Exit back to Android

```bash
adb reboot bootloader
fastboot reboot
```

Then verify on Android:

```bash
adb shell getprop ro.boot.verifiedbootstate   # orange
fastboot getvar unlocked                      # yes (needs bootloader)
adb shell pm list packages -s | grep nes
```

## 5. If it bootloops or hangs

The stock `boot_a` was never touched. Bootloader mode remains reachable via
the DNL button trick (USB unplug, hold RESET, plug in, 10-15 s) or, if still
working, `adb reboot bootloader`. Restore from the byte-identical backup in
`/home/bklumki/fw_dump/` only if something was actually written.
