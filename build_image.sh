#!/bin/bash
# Build the TWRP 11 boot image for the waipu.tv 4K Stick (SEI700WP / oppen),
# reattach the stock AVB footer and - optionally - flash it to boot_a.
#
# Absolute paths are intentional: the script can be started from any directory.
#
# Usage:
#   build_image.sh                 # build + AVB (default, no device needed)
#   build_image.sh --avb-only      # only reattach AVB to existing boot.img
#   build_image.sh --flash         # build + AVB + flash to boot_a
#   build_image.sh --flash-only    # flash existing final image only

set -eo pipefail
# Note: build/envsetup.sh references $ZSH_VERSION, so nounset is not enabled here.

BUILD_ROOT=/mnt/twrp-build/twrp11
DEVICE_TREE=$BUILD_ROOT/device/sei/SEI700WP
OUT=$BUILD_ROOT/out/target/product/SEI700WP
ENV_FILE=$BUILD_ROOT/env.sh
STOCK_BOOT=/home/bklumki/fw_dump/ota/extracted/boot.img
IMAGES_DIR=/home/bklumki/fw_dump/twrp_images
OUT_IMG=$IMAGES_DIR/twrp_SEI700WP_boot_poweroffhook_avb.img
EXPECTED_SHA=31295c621d702c655064ea765d587f2ac85c0bc95af5c126176878a14dfc8704
# In TWRP, /data is not mounted and /data/local/tmp does not exist. Use /tmp.
DEVICE_IMG=/tmp/twrp_flash.img

DO_BUILD=1
DO_AVB=1
DO_FLASH=0

case "${1:-}" in
    "") ;;
    --avb-only)   DO_BUILD=0 ;;
    --flash)      DO_FLASH=1 ;;
    --flash-only) DO_BUILD=0; DO_AVB=0; DO_FLASH=1 ;;
    -h|--help)
        sed -n '2,12p' "$0"
        exit 0 ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1 ;;
esac

for f in "$ENV_FILE" "$STOCK_BOOT" "$BUILD_ROOT/build/envsetup.sh"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing required file: $f" >&2
        exit 1
    fi
done

mkdir -p "$IMAGES_DIR" "$OUT/recovery/root/system/lib"

if [ "$DO_BUILD" -eq 1 ]; then
    echo "==> Preparing ramdisk inputs"

    # Without this library in the ramdisk the UI crashes at the waipu logo.
    if [ -f "$OUT/system/lib/libminuitwrp.so" ] && \
       [ ! -f "$OUT/recovery/root/system/lib/libminuitwrp.so" ]; then
        cp "$OUT/system/lib/libminuitwrp.so" "$OUT/recovery/root/system/lib/libminuitwrp.so"
        echo "    copied libminuitwrp.so into recovery ramdisk"
    fi

    LIB_SHA=$(sha256sum "$OUT/recovery/root/system/lib/libminuitwrp.so" | cut -d' ' -f1)
    grep -qx 'system/lib/libminuitwrp.so' "$OUT/recovery/root/ramdisk-files.txt" || \
        echo 'system/lib/libminuitwrp.so' >> "$OUT/recovery/root/ramdisk-files.txt"
    grep -q "  ./system/lib/libminuitwrp.so$" "$OUT/recovery/root/ramdisk-files.sha256sum" || \
        echo "$LIB_SHA  ./system/lib/libminuitwrp.so" >> "$OUT/recovery/root/ramdisk-files.sha256sum"

    # mka bootimage reuses cached ramdisk files otherwise.
    rm -f "$OUT/ramdisk-recovery.cpio" "$OUT/ramdisk-recovery.img" "$OUT/boot.img"

    echo "==> Building TWRP"
    source "$ENV_FILE"
    cd "$BUILD_ROOT"
    . "$BUILD_ROOT/build/envsetup.sh"
    lunch twrp_SEI700WP-eng
    mka bootimage -j4
fi

if [ "$DO_AVB" -eq 1 ]; then
    RAW_IMG=$OUT/boot.img
    if [ ! -f "$RAW_IMG" ]; then
        echo "ERROR: no boot.img at $RAW_IMG" >&2
        exit 1
    fi

    echo "==> Reattaching AVB footer"
    python3 - "$RAW_IMG" "$STOCK_BOOT" "$OUT_IMG" <<'PY'
import sys, struct, hashlib

src, stock_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(src, 'rb').read()
orig = len(data)
stock_data = open(stock_path, 'rb').read()

footer = stock_data[-64:]
if footer[:4] != b'AVBf':
    raise SystemExit('ERROR: stock image has no AVB footer')
vb_off = struct.unpack('>Q', footer[20:28])[0]
vb_size = struct.unpack('>Q', footer[28:36])[0]
vb = bytearray(stock_data[vb_off:vb_off + vb_size])

# Hashtree descriptor: update image size and digest for the new payload.
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
print('    raw boot.img :', orig, 'bytes')
print('    final image  :', len(img), 'bytes')
PY
fi

if [ ! -f "$OUT_IMG" ]; then
    echo "ERROR: no final image at $OUT_IMG" >&2
    exit 1
fi

IMAGE_SHA=$(sha256sum "$OUT_IMG" | cut -d' ' -f1)
echo "==> Result"
echo "    $OUT_IMG"
echo "    SHA-256: $IMAGE_SHA"
if [ "$IMAGE_SHA" = "$EXPECTED_SHA" ]; then
    echo "    Matches the verified release image."
else
    echo "    NOTE: differs from the verified release image ($EXPECTED_SHA)"
    echo "          - expected if you changed the source tree."
fi

if [ "$DO_FLASH" -eq 0 ]; then
    exit 0
fi

# ---------------- flashing ----------------

if ! command -v adb >/dev/null 2>&1; then
    echo "ERROR: adb not found in PATH" >&2
    exit 1
fi

STATE=$(adb get-state 2>/dev/null || true)
if [ "$STATE" != "recovery" ]; then
    echo "ERROR: device must be in TWRP recovery (adb state: '${STATE:-none}')" >&2
    exit 1
fi

echo "==> Flashing preconditions"
echo "    Device state : $STATE"
echo "    slot         : $(adb shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r')"
echo "    image        : $OUT_IMG"
echo "    SHA-256      : $IMAGE_SHA"
if [ "$IMAGE_SHA" != "$EXPECTED_SHA" ]; then
    echo "    WARNING: this is NOT the verified release image."
fi
echo
read -r -p "Type YES to write this image to /dev/block/by-name/boot_a: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Do NOT use 'adb exec-out dd ...': exec-out merges dd's stderr (the
# "N+0 records ..." statistics) into the data stream, producing extra bytes.
BACKUP=$IMAGES_DIR/boot_a_backup_$(date +%Y%m%d_%H%M%S).img
DEVICE_BACKUP=/tmp/boot_a_backup.img
echo "==> Backing up current boot_a to"
echo "    $BACKUP"
adb shell "dd if=/dev/block/by-name/boot_a of=$DEVICE_BACKUP bs=4M status=none"
adb shell sync
DEVICE_BACKUP_SHA=$(adb shell sha256sum $DEVICE_BACKUP | cut -d' ' -f1 | tr -d '\r')
adb pull "$DEVICE_BACKUP" "$BACKUP" >/dev/null
adb shell "rm -f $DEVICE_BACKUP" >/dev/null 2>&1 || true
BACKUP_SIZE=$(stat -c %s "$BACKUP")
BACKUP_SHA=$(sha256sum "$BACKUP" | cut -d' ' -f1)
if [ "$BACKUP_SIZE" -ne 67108864 ]; then
    echo "ERROR: backup has $BACKUP_SIZE bytes, expected 67108864. Not flashing." >&2
    exit 1
fi
if [ "$BACKUP_SHA" != "$DEVICE_BACKUP_SHA" ]; then
    echo "ERROR: backup hash mismatch (device: $DEVICE_BACKUP_SHA, host: $BACKUP_SHA)." >&2
    echo "       Not flashing." >&2
    exit 1
fi
echo "    backup SHA-256: $BACKUP_SHA"

HOST_EPOCH=$(date +%s)
adb shell "date @$HOST_EPOCH" >/dev/null 2>&1 || true

echo "==> Pushing image"
adb push "$OUT_IMG" "$DEVICE_IMG" >/dev/null

echo "==> Writing boot_a"
adb shell "dd if=$DEVICE_IMG of=/dev/block/by-name/boot_a bs=4M" 2>&1 | tail -2
adb shell sync

DEVICE_SHA=$(adb shell sha256sum /dev/block/by-name/boot_a 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "==> Verification"
echo "    device boot_a: $DEVICE_SHA"
if [ "$DEVICE_SHA" != "$IMAGE_SHA" ]; then
    echo "ERROR: hash mismatch. Restore the backup if the device misbehaves:" >&2
    echo "  adb push $BACKUP /tmp/boot_a_backup.img" >&2
    echo "  adb shell dd if=/tmp/boot_a_backup.img of=/dev/block/by-name/boot_a bs=4M" >&2
    exit 1
fi
echo "    Hash matches. Slot b and misc were not touched."

adb shell "rm -f $DEVICE_IMG" >/dev/null 2>&1 || true
echo "    Done. Reboot with: adb reboot"
echo "    After ~17 s check: adb shell grep -m1 'Using .* graphics' /tmp/recovery.log"
