#
# TWRP device tree for the Samsung Galaxy View SM-T670 (gvwifi), Exynos 7580.
# Built on twrp-14.1 for the unofficial LineageOS 23.2 (Android 16) ROM.
#

DEVICE_PATH := device/samsung/gvwifi

# Architecture: 64-bit kernel, 32-bit userspace (same as the ROM)
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := cortex-a53

TARGET_BOARD_PLATFORM := exynos5
TARGET_SOC := exynos7580
TARGET_BOOTLOADER_BOARD_NAME := universal7580
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true

# Kernel: the ROM's own kernel (same USB/SELinux/bootwatch patches).
# The image is packed afterwards with Samsung's DT layout by pack-recovery.sh,
# so the AOSP mkbootimg output is only an intermediate.
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
BOARD_KERNEL_BASE := 0x10000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_CMDLINE :=
# (build-twrp.sh packs the real image; see the load-window note there)
BOARD_MKBOOTIMG_ARGS := --kernel_offset 0x00008000 --ramdisk_offset 0x02000000 --tags_offset 0x00000100
BOARD_RAMDISK_USE_XZ := true

# Partitions
BOARD_FLASH_BLOCK_SIZE := 4096
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 39845888
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 3145728000
BOARD_USERDATAIMAGE_PARTITION_SIZE := 13514047488
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_COPY_OUT_VENDOR := vendor
BOARD_USES_METADATA_PARTITION := true

# Recovery
TARGET_RECOVERY_PIXEL_FORMAT := ABGR_8888
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab
TARGET_USES_MKE2FS := true

# Must match the ROM exactly. The ROM's keys are wrapped by the software keymaster 3
# (PureSoftKeymasterContext), which stamps each key with:
#   OS version     ro.build.version.release         16  (set via the release config in build-twrp.sh)
#   OS patch       ro.build.version.security_patch  2026-09-01
#   vendor patch   ro.vendor.build.security_patch   EMPTY on the ROM, so do not set VENDOR_SECURITY_PATCH
#   boot patch     derived from the OS patch
# A lower value makes the key unusable; a higher one makes vold upgrade and rewrite the
# key blob, which the ROM then rejects.
PLATFORM_SECURITY_PATCH := 2026-09-01

# Decryption: file-based encryption v2, no metadata encryption.
# Same stack as the ROM (checked on the device 2026-10-03): keymaster@3.0-service finds no
# keystore.<ro.hardware|ro.product.board|ro.board.platform> module (the Samsung library is
# named keystore.exynos7580), so it runs its built-in software keymaster; gatekeeper is the
# software service. Samsung's TEE (MobiCore) is not involved, so it is left out.
TW_INCLUDE_CRYPTO := true
TW_USE_FSCRYPT_POLICY := 2
TARGET_RECOVERY_DEVICE_MODULES += \
    hwservicemanager \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service \
    android.hardware.gatekeeper@1.0-service.software
# hwservicemanager is a system_ext module; listing it here also makes the build install it
TW_RECOVERY_ADDITIONAL_RELINK_BINARY_FILES += \
    $(TARGET_OUT_SYSTEM_EXT_EXECUTABLES)/hwservicemanager \
    $(TARGET_OUT_VENDOR_EXECUTABLES)/hw/android.hardware.keymaster@3.0-service \
    $(TARGET_OUT_VENDOR_EXECUTABLES)/hw/android.hardware.gatekeeper@1.0-service.software
TW_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_VENDOR_SHARED_LIBRARIES)/hw/android.hardware.keymaster@3.0-impl.so \
    $(TARGET_OUT_VENDOR_SHARED_LIBRARIES)/libkeymaster3device.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.keymaster@3.0.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.gatekeeper@1.0.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libboot_control_client.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libresetprop.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.boot-V1-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.confirmationui-V1-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.security.keymint-V3-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.security.rkp-V3-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.security.aaid_aidl-cpp.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.system.keystore2-V4-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.system.suspend-V1-ndk.so
# TWRP's own relink list (bootable/recovery/prebuilt/Android.mk) misses the recovery
# binary's libboot_control_client/libresetprop and names the V1 keystore2/keymint AIDL
# libraries, while this tree builds the versions above. build-twrp.sh checks the result.

# TWRP UI
# Version shows as 3.7.1_14-A16: TWRP 3.7.1 from the twrp-14.1 (Android 14) branch, built
# for the LineageOS 23.2 / Android 16 ROM.
TW_DEVICE_VERSION := A16
TW_THEME := landscape_hdpi
# The panel is mounted upside down (the ROM rotates 180 too). TW_ROTATION only rotates the
# drawing; touch already reports upright coordinates, so no touch flip is needed.
TW_ROTATION := 180
# USB dropped once TWRP got past /data (2026-10-03); the configfs setup in
# init.recovery.samsungexynos7580.rc only defines adb/fastboot, so keep TWRP off MTP.
TW_EXCLUDE_MTP := true
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 160
RECOVERY_SDCARD_ON_DATA := true
TW_HAS_DOWNLOAD_MODE := true
TW_NO_REBOOT_BOOTLOADER := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_USE_TOOLBOX := true
TW_INCLUDE_NTFS_3G := false

# Keep the ramdisk small (about 20 MB is left next to the 19 MB kernel)
TW_EXTRA_LANGUAGES := false
TW_EXCLUDE_TWRPAPP := true
TW_EXCLUDE_APEX := true
TW_EXCLUDE_PYTHON := true
TW_EXCLUDE_NANO := true
TW_EXCLUDE_BASH := true
TW_EXCLUDE_LPDUMP := true
TW_EXCLUDE_LPTOOLS := true
TW_NO_HAPTICS := true

# Logging (useful while bringing up decryption)
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TW_CRYPTO_SYSTEM_VOLD_DEBUG := true
