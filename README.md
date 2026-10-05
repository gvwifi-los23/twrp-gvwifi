# TWRP 3.7.1 (twrp-14.1) for the Galaxy View SM-T670 (`gvwifi`), LineageOS 23.2

TWRP built from the `twrp-14.1` minimal manifest, for the [`lineage-gvwifi`](https://github.com/gvwifi-los23/lineage-gvwifi)
ROM. Version string `3.7.1_14-A16` (the `14` is TWRP's Android 14 branch; `A16` marks the target ROM).

**Works:** boots (upright display, touch), adb, automatic FBE decryption (the same software
keymaster 3.0 and gatekeeper as the ROM), Data backup **with** fscrypt policies, restore, Format Data.

## Build
```
# TWRP source:
# repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp -b twrp-14.1 --depth=1
KERNEL=<Image built with lineage-gvwifi kernel patches 0012-0014> bash build-twrp.sh
```
`build-twrp.sh` copies `device_samsung_gvwifi/` into the tree, applies `patches/`, builds, trims the
ramdisk, and packs a Samsung image (`mkdtbhbootimg`, DT, `SEANDROIDENFORCE`). It refuses to pack when:
- `ro.build.version.release` / `security_patch` / `ro.vendor.build.security_patch` differ from the ROM
  (16 / 2026-09-01 / empty): the software keymaster stamps keys with them, and a mismatch makes vold
  reject or rewrite key blobs;
- a shared-library dependency is missing (checked recursively over every ELF);
- the image doesn't fit S-Boot's load window (the image must end below `0x42000000`).

It expects the LineageOS build's kernel, `dt.img` and `mkdtbhbootimg` in `~/gvwifi-keep/`.

## Patches
| Patch | Why |
|---|---|
| `bootable_recovery/0001` | keystore AIDL libs are `-ndk` on Android 13+; libtar's missing link deps |
| `bootable_recovery/0002` | "no FDE" stubs: TWRP still calls FDE helpers only android-12.1's vold has |
| `bootable_recovery/0003` | link libsysutils for libvold |
| `bootable_recovery/0004` | exclude the `/data/user/0` bind mount from Data backups (it duplicated every app's data) |
| `bootable_recovery/0005` | release `/data/user/0` before unmounting `/data` (Format Data failed with EBUSY) |
| `bootable_recovery/0006` | the ABX (binary XML) converter read 64-bit values as `long`, 4 bytes on this 32-bit recovery, so `/data/system/users/0.xml` came out garbled and TWRP showed "Error parsing XML file" at startup |
| `system_vold/0001` | TeamWin's "dynamically choose fscrypt policy [2/2]" (only on android-12.1), ported to 14.1 |
| kernel 0012 (in `lineage-gvwifi`) | `FS_IOC_GET_ENCRYPTION_POLICY_EX` was declared but never implemented, so backups lost every policy |
| kernel 0013 (in `lineage-gvwifi`) | FunctionFS leaked the open adb endpoints whenever adbd stopped, so USB adb could stay offline after an adbd restart |
| kernel 0014 (in `lineage-gvwifi`) | reused inodes kept another file's encryption key or fs-verity state: backups/restores could read files as I/O errors or write them with the wrong key |

## Device-tree notes
- Same keymaster as the ROM: `keymaster@3.0-service` finds no `keystore.<board>` module and runs its
  built-in software keymaster; Samsung's MobiCore TEE is not involved and is left out.
- The build adds `/system/bin/bootstrap/linker`, `/vendor/lib/hw` (keymaster impl link), an empty
  framework VINTF manifest and `task_profiles.json`, which this twrp-14.1 combination never installs.
- Keymaster and gatekeeper start on `ro.crypto.state=encrypted` (twrp-14.1 no longer sets `crypto.ready`).
- After **Format Data**, `/cache` (a link to `/data/cache`) points at nothing, so a ROM zip
  install aborts with `E1001: mkdir "/cache/recovery/..." failed`. Create it first:
  `adb shell mkdir -p /data/cache/recovery`, then install.
- `TW_ROTATION := 180` (the panel is mounted upside down; touch is already upright); MTP excluded.
