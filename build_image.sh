#!/bin/bash
# Build the TWRP 11 boot image for the waipu.tv 4K Stick (SEI700WP / oppen)
# and reattach the stock AVB footer so the result can actually be flashed.
#
# Absolute paths are intentional: the script can be started from any directory.
#
# Usage:
#   /home/bklumki/waipu-twrp-device-tree/build_image.sh            # full build + AVB
#   /home/bklumki/waipu-twrp-device-tree/build_image.sh --avb-only # only AVB from existing boot.img

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

SKIP_BUILD=0
if [ "${1:-}" = "--avb-only" ]; then
    SKIP_BUILD=1
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '2,9p' "$0"
    exit 0
elif [ $# -gt 0 ]; then
    echo "Unknown option: $1" >&2
    exit 1
fi

for f in "$ENV_FILE" "$STOCK_BOOT" "$BUILD_ROOT/build/envsetup.sh"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing required file: $f" >&2
        exit 1
    fi
done

mkdir -p "$IMAGES_DIR" "$OUT/recovery/root/system/lib"

if [ "$SKIP_BUILD" -eq 0 ]; then
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

ACTUAL_SHA=$(sha256sum "$OUT_IMG" | cut -d' ' -f1)
echo "==> Result"
echo "    $OUT_IMG"
echo "    SHA-256: $ACTUAL_SHA"
if [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
    echo "    Matches the verified release image."
else
    echo "    NOTE: differs from the verified release image ($EXPECTED_SHA)"
    echo "          - expected if the source tree changed."
    echo "          - check with 'sha256sum /dev/block/by-name/boot_a' before flashing."
fi
