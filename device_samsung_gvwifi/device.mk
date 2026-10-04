LOCAL_PATH := device/samsung/gvwifi

# Device manifest so hwservicemanager accepts keymaster 3.0 and gatekeeper 1.0
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/manifest.xml:$(TARGET_COPY_OUT_RECOVERY)/root/vendor/etc/vintf/manifest.xml
