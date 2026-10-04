$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
$(call inherit-product, device/samsung/gvwifi/device.mk)

PRODUCT_DEVICE := gvwifi
PRODUCT_NAME := twrp_gvwifi
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-T670
PRODUCT_MANUFACTURER := samsung
