#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/sei/SEI700WP

# Dynamic partitions (super_a: system, system_ext, vendor, product, odm)
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_TARGET_VNDK_VERSION := 30
PRODUCT_SHIPPING_API_LEVEL := 30
PRODUCT_PLATFORM := SEI700WP

# A/B boot control is disabled for the first boot test.
# The generator referenced bootctrl.SEI700WP, which does not exist in this
# source tree. Re-enable only after a bootctrl.default alias/HAL is provided.
# AB_OTA_UPDATER := true

PRODUCT_PACKAGES += \
    otapreopt_script \
    cppreopts.sh \
    update_engine \
    update_verifier \
    update_engine_sideload
