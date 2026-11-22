#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit common TWRP stuff (TWRP AOSP 11 manifest provides vendor/twrp).
$(call inherit-product, vendor/twrp/config/common.mk)

# Inherit from SEI700WP device
$(call inherit-product, device/sei/SEI700WP/device.mk)

PRODUCT_DEVICE := SEI700WP
PRODUCT_NAME := twrp_SEI700WP
PRODUCT_BRAND := waiputv
PRODUCT_MODEL := waipu tv stick
PRODUCT_MANUFACTURER := sei

PRODUCT_GMS_CLIENTID_BASE := android-seirobotics-tv

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="SEI700WP-user 11 RTT0.211009.001 6958 release-keys"

BUILD_FINGERPRINT := waiputv/SEI700WP/SEI700WP:11/RTT0.211009.001/6958:user/release-keys
