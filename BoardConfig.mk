#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/sei/SEI700WP

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true

# A/B
# Disabled for first boot test: no bootctrl.SEI700WP HAL in this tree.
AB_OTA_UPDATER := false
AB_OTA_PARTITIONS +=
BOARD_USES_RECOVERY_AS_BOOT := true

# Architecture
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_USES_64_BIT_BINDER := true

# APEX
OVERRIDE_TARGET_FLATTEN_APEX := true

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := SEI700WP
TARGET_NO_BOOTLOADER := true

# Display
TARGET_SCREEN_DENSITY := 320
# Amlogic DRM dumb-buffer mmap is broken in this kernel; use fbdev instead.
TW_TARGET_USES_DRM := false
# Do not blank the TV screen after 60 s of inactivity.
TW_NO_SCREEN_TIMEOUT := true

# Kernel
BOARD_BOOTIMG_HEADER_VERSION := 3
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_KERNEL_CONFIG := SEI700WP_defconfig
TARGET_KERNEL_SOURCE := kernel/sei/SEI700WP

# Kernel - prebuilt
TARGET_FORCE_PREBUILT_KERNEL := true
ifeq ($(TARGET_FORCE_PREBUILT_KERNEL),true)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
endif

# Partitions
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor
BOARD_SUPER_PARTITION_SIZE := 9126805504 # TODO: Fix hardcoded value
BOARD_SUPER_PARTITION_GROUPS := sei_dynamic_partitions
BOARD_SEI_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext vendor product odm
BOARD_SEI_DYNAMIC_PARTITIONS_SIZE := 9122611200 # TODO: Fix hardcoded value

# Platform
TARGET_BOARD_PLATFORM := SEI700WP

# Recovery
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Verified Boot
# Bootloader is unlocked/secure=no; disable AVB for the first fastboot boot test.
BOARD_AVB_ENABLE := false
# BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3

# Hack: prevent anti rollback
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31
PLATFORM_VERSION := 16.1.0

# TWRP Configuration
TW_THEME := landscape_hdpi
TW_EXTRA_LANGUAGES := true
TW_SCREEN_BLANK_ON_BOOT := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_USE_TOOLBOX := true
TW_INCLUDE_REPACKTOOLS := true
