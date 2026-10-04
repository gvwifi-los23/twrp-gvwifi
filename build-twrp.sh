#!/usr/bin/env bash
# Build TWRP (twrp-14.1) for the Galaxy View SM-T670, using the LineageOS 23.2 build's kernel.
#   bash build-twrp.sh          # set up the tree, build, pack
# Output: ~/twrp-out/twrp-<version>-gvwifi-<date>.img and .tar (Odin), e.g. twrp-3.7.1_14-A16-gvwifi-20261003
set -euo pipefail
export PATH=$HOME/bin:$PATH
# This script's directory: holds device_samsung_gvwifi/ and patches/
HERE=$(cd "$(dirname "$0")" && pwd)
T=$HOME/android/twrp
L=$HOME/android/lineage
# Kernel, dt.img and mkdtbhbootimg saved from the LineageOS build (its out/ was deleted for space)
KEEP=$HOME/gvwifi-keep
D=$T/device/samsung/gvwifi

echo "== device tree"
rm -rf "${D:?}"; mkdir -p "$D"
cp -r "$HERE/device_samsung_gvwifi/." "$D/"

echo "== prebuilts from the LineageOS build"
mkdir -p "$D/prebuilt"
# KERNEL=<path to Image> builds TWRP with another kernel (e.g. one with kernel patch 0012,
# fscrypt get_policy_ex, which TWRP needs to back up /data with its encryption policies)
KERNEL=${KERNEL:-$KEEP/kernel}
echo "   kernel: $KERNEL ($(strings "$KERNEL" | grep -m1 -o 'Linux version [^ ]* [^ ]*'))"
cp "$KERNEL" "$D/prebuilt/Image"
cp "$KEEP/dt.img" "$D/prebuilt/dt.img"
# Samsung TEE sources are not used (the ROM's keys don't involve MobiCore); remove any
# copy left by earlier versions of this script
rm -rf "$T/hardware/samsung_slsi"

echo "== OS version 16"
# ro.build.version.release must be 16, as on the ROM (keymaster stamps keys with it), and
# TWRP unlocks the DE keys while reading the fstab, before TW_OVERRIDE_SYSTEM_PROPS runs.
# On this Android 14 tree it is RELEASE_PLATFORM_VERSION_LAST_STABLE from the release config
# (BoardConfig PLATFORM_VERSION has no effect), and CTS's makefile only accepts versions in
# its platform_releases.txt. Neither file is part of the recovery image.
sed -i 's/value("RELEASE_PLATFORM_VERSION_LAST_STABLE", "14")/value("RELEASE_PLATFORM_VERSION_LAST_STABLE", "16")/' \
    "$T/build/release/build_config/ap2a.scl"
grep -q '"RELEASE_PLATFORM_VERSION_LAST_STABLE", "16"' "$T/build/release/build_config/ap2a.scl"
grep -qx 16 "$T/cts/tests/tests/os/assets/platform_releases.txt" || \
    echo 16 >> "$T/cts/tests/tests/os/assets/platform_releases.txt"

echo "== TWRP source fixes"
# Upstream twrp-14.1 does not compile with TW_INCLUDE_CRYPTO; see each patch's message.
#   twrp/patches/<project with / as _>/NNNN-*.patch, applied in order, skipped if present
apply_patches() {
    local repo=$1 dir=$2 p subj
    for p in "$dir"/*.patch; do
        [ -e "$p" ] || continue
        # mailinfo unfolds long Subject: headers and strips the leading [PATCH]
        subj=$(git mailinfo /dev/null /dev/null < "$p" | sed -n 's/^Subject: //p')
        # (not grep -q: under pipefail, git log's SIGPIPE would read as "not found")
        if git -C "$repo" log --format=%s -200 | grep -xF "$subj" >/dev/null; then
            echo "   already applied: $subj"
        else
            echo "   applying: $subj"
            git -C "$repo" -c user.name="gvwifi build" -c user.email=build@local am -q "$p"
        fi
    done
}
apply_patches "$T/system/vold" "$HERE/patches/system_vold"
apply_patches "$T/bootable/recovery" "$HERE/patches/bootable_recovery"

echo "== build"
cd "$T"
# envsetup/lunch read unset variables on purpose
set +u
source build/envsetup.sh >/dev/null
lunch twrp_gvwifi-ap2a-eng
export ALLOW_MISSING_DEPENDENCIES=true
# Incremental builds never delete files dropped from the image; rebuild the recovery root
# so nothing stale (e.g. an old keystore module) ends up in it
rm -rf "$T/out/target/product/gvwifi/recovery" "$T/out/target/product/gvwifi/ramdisk-recovery."*
m -j"${JOBS:-12}" recoveryimage
set -u

echo "== check against the ROM (values read from the tablet 2026-10-03)"
R=$T/out/target/product/gvwifi/recovery/root
prop() { { grep -sh "^$1=" "$R/prop.default" "$R/system/etc/prop.default" || true; } | tail -1 | cut -d= -f2-; }
fail=0
want() {  # want <prop> <value>   (empty value = must be unset or empty)
    local got; got=$(prop "$1")
    if [ "$got" = "$2" ]; then echo "   ok   $1=[$got]"; else echo "   BAD  $1=[$got], ROM has [$2]"; fail=1; fi
}
want ro.build.version.release 16
want ro.build.version.security_patch 2026-09-01
want ro.vendor.build.security_patch ""
for f in system/bin/hwservicemanager system/bin/android.hardware.keymaster@3.0-service \
         system/bin/android.hardware.gatekeeper@1.0-service.software \
         system/lib/android.hardware.keymaster@3.0-impl.so system/bin/keystore2 \
         vendor/etc/vintf/manifest.xml init.recovery.samsungexynos7580.rc; do
    if [ -e "$R/$f" ]; then echo "   ok   $f"; else echo "   MISSING $f"; fail=1; fi
done
# Every shared library the decryption services need, recursively, must be in the ramdisk
# (a missing one only shows up on the device as a service that never starts)
missing=$(python3 - "$R" <<'PY'
import os, subprocess, sys
root = sys.argv[1]
libdirs = [os.path.join(root, d) for d in ('system/lib', 'system/lib/hw', 'vendor/lib', 'vendor/lib/hw')]
def needed(path):
    out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    return [l.split('[')[1].split(']')[0] for l in out.splitlines() if '(NEEDED)' in l]
def find(lib):
    for d in libdirs:
        p = os.path.join(d, lib)
        if os.path.exists(p): return p
# every ELF executable in the ramdisk, plus the HAL implementations loaded by name
todo = [os.path.join(root, 'system/lib/android.hardware.keymaster@3.0-impl.so')]
for d in ('system/bin', 'system/bin/hw', 'vendor/bin', 'vendor/bin/hw'):
    pd = os.path.join(root, d)
    for f in (os.listdir(pd) if os.path.isdir(pd) else []):
        p = os.path.join(pd, f)
        if os.path.isfile(p) and not os.path.islink(p) and open(p, 'rb').read(4) == b'\x7fELF':
            todo.append(p)
seen, bad = set(), set()
while todo:
    f = todo.pop()
    if f in seen: continue
    seen.add(f)
    for lib in needed(f):
        p = find(lib)
        if p: todo.append(os.path.realpath(p))
        else: bad.add(f"{lib} (needed by {os.path.basename(f)})")
print('\n'.join(sorted(bad)))
PY
)
if [ -n "$missing" ]; then echo "$missing" | sed 's/^/   MISSING lib /'; fail=1; else echo "   ok   all shared library dependencies present"; fi
# The software keymaster must be used, as on the ROM: no keystore.* hardware module
if find "$R" -name 'keystore.*.so' | grep . ; then echo "   BAD  keystore hardware module present"; fail=1; fi
[ $fail = 0 ] || { echo "recovery does not match the ROM; not packing"; exit 1; }

echo "== trim the ramdisk to fit S-Boot's load window"
OUT=$T/out/target/product/gvwifi
# Drop shared libraries that no ELF in the ramdisk links against (unused adb/vibrator/wifi
# libraries, ~1.8 MB compressed). lib/hw is kept: HAL implementations are loaded by name at
# runtime. The result is checked again for missing dependencies before it is packed.
TRIM=$OUT/ramdisk-trimmed.img
export TASK_PROFILES=$OUT/system/etc/task_profiles.json
[ -f "$TASK_PROFILES" ] || { echo "task_profiles.json not built"; exit 1; }
python3 - "$OUT/ramdisk-recovery.img" "$TRIM" <<'PY'
import lzma, os, struct, subprocess, sys, tempfile
src, dst = sys.argv[1], sys.argv[2]
data = lzma.decompress(open(src, 'rb').read())
# --- read newc entries
entries, p = [], 0
while True:
    f = [int(data[p+6+i*8:p+14+i*8], 16) for i in range(13)]
    namesize, filesize = f[11], f[6]
    name = data[p+110:p+110+namesize-1].decode()
    p = (p + 110 + namesize + 3) & ~3
    body = data[p:p+filesize]; p = (p + filesize + 3) & ~3
    if name == 'TRAILER!!!': break
    entries.append((name, f, body))
# --- find libraries reachable from every ELF executable
tmp = tempfile.mkdtemp()
files = {}
for name, f, body in entries:
    if (f[1] & 0o170000) == 0o100000:
        path = os.path.join(tmp, name); os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'wb').write(body); files[name] = path
def needed(path):
    out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    return [l.split('[')[1].split(']')[0] for l in out.splitlines() if '(NEEDED)' in l]
libdirs = ['system/lib', 'system/lib/hw', 'vendor/lib', 'vendor/lib/hw']
symlinks = {name: body.decode() for name, f, body in entries if (f[1] & 0o170000) == 0o120000}
def follow(n):
    for _ in range(8):                       # follow (possibly relative) symlinks
        if n not in symlinks: return n
        t = symlinks[n]
        n = os.path.normpath(t.lstrip('/') if t.startswith('/') else os.path.join(os.path.dirname(n), t))
    return n
def resolve(lib):
    for d in libdirs:
        n = follow(f'{d}/{lib}')
        if n in files: return n
roots = [n for n, path in files.items() if open(path, 'rb').read(4) == b'\x7fELF'
         and not n.endswith('.so')]
roots += [n for n in files if '/hw/' in n and n.endswith('.so')]   # loaded by name at runtime
# dlopen'd by HIDL passthrough (via the /vendor/lib/hw link added below), so no ELF links it
KEEP_DLOPEN = ['system/lib/android.hardware.keymaster@3.0-impl.so']
for n in KEEP_DLOPEN:
    if n not in files: sys.exit(f"missing {n}")
    roots.append(n)
seen, todo = set(), list(roots)
while todo:
    n = todo.pop()
    if n in seen: continue
    seen.add(n)
    for lib in needed(files[n]):
        r = resolve(lib)
        if r: todo.append(r)
drop = {n for n in files if n.endswith('.so') and n.startswith(('system/lib/', 'vendor/lib/'))
        and '/hw/' not in n and n not in seen}
# also: UI translations other than English (TWRP falls back to en), and the TWRP app
# installer (TW_EXCLUDE_TWRPAPP did not keep it out)
drop |= {n for n in files if n.startswith('twres/languages/') and not n.endswith('/en.xml')}
drop |= {n for n in files if os.path.basename(n) in ('me.twrp.twrpapp.apk', 'privapp-permissions-twrpapp.xml')}
saved = sum(len(b) for n, f, b in entries if n in drop)
print(f"   dropping {len(drop)} unused libraries ({saved // 1024} KB raw)")
# --- write newc
out = bytearray(); ino = 300000
def add(name, f, body):
    global ino
    ino += 1
    nb = name.encode() + b'\0'
    hdr = '070701' + ''.join(f'{v:08x}' for v in [ino, f[1], f[2], f[3], f[4], f[5], len(body),
                                                     f[7], f[8], f[9], f[10], len(nb), 0])
    out.extend(hdr.encode() + nb); out.extend(b'\0' * ((4 - len(out) % 4) % 4))
    out.extend(body); out.extend(b'\0' * ((4 - len(out) % 4) % 4))
for name, f, body in entries:
    if name not in drop: add(name, f, body)
# --- pieces this TWRP/Android 14 combination needs but never installs (found on the
#     device 2026-10-03, each one stopped key setup):
existing = {n for n, f, b in entries}
DIR, LNK, REG = 0o040755, 0o120777, 0o100644
def meta(mode): return [0, mode, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
extras = [
    # hwservicemanager and servicemanager are "bootstrap" binaries (interpreter
    # /system/bin/bootstrap/linker); without it they fail with exit 127
    ('system/bin/bootstrap', DIR, b''),
    ('system/bin/bootstrap/linker', LNK, b'/system/bin/linker'),
    # HIDL passthrough looks for keymaster@3.0-impl in /vendor/lib/hw
    ('vendor/lib', DIR, b''),
    ('vendor/lib/hw', DIR, b''),
    ('vendor/lib/hw/android.hardware.keymaster@3.0-impl.so', LNK,
     b'/system/lib/android.hardware.keymaster@3.0-impl.so'),
    # servicemanager only reads the VINTF fragments (keystore2's declaration) if a main
    # framework manifest exists; it must not declare keystore2 again
    ('system/etc/vintf/manifest.xml', REG,
     b'<manifest version="8.0" type="framework">\n</manifest>\n'),
    # logd aborts without it
    ('system/etc/task_profiles.json', REG, open(os.environ['TASK_PROFILES'], 'rb').read()),
]
for name, mode, body in extras:
    if name in existing:
        print(f"   (already present: {name})"); continue
    add(name, meta(mode), body); print(f"   added {name}")
add('TRAILER!!!', [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0], b'')
filters = [{'id': lzma.FILTER_LZMA2, 'preset': 6, 'dict_size': 32 << 20}]
open(dst, 'wb').write(lzma.compress(bytes(out), format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32, filters=filters))
print(f"   ramdisk {os.path.getsize(src)} -> {os.path.getsize(dst)} bytes")
PY
# re-check the trimmed ramdisk's dependencies
CHK=$(mktemp -d)
python3 - "$TRIM" "$CHK" <<'PY'
import lzma, os, sys
data = lzma.decompress(open(sys.argv[1], 'rb').read()); root = sys.argv[2]; p = 0
while True:
    f = [int(data[p+6+i*8:p+14+i*8], 16) for i in range(13)]
    name = data[p+110:p+110+f[11]-1].decode(); p = (p + 110 + f[11] + 3) & ~3
    body = data[p:p+f[6]]; p = (p + f[6] + 3) & ~3
    if name == 'TRAILER!!!': break
    t = os.path.join(root, name); mode = f[1] & 0o170000
    if mode == 0o040000: os.makedirs(t, exist_ok=True)
    elif mode == 0o120000:
        os.makedirs(os.path.dirname(t), exist_ok=True); os.path.lexists(t) or os.symlink(body.decode(), t)
    elif mode == 0o100000:
        os.makedirs(os.path.dirname(t), exist_ok=True); open(t, 'wb').write(body)
PY
miss=$(cd "$CHK" && for f in system/bin/* system/bin/hw/* system/lib/hw/*.so vendor/lib/hw/*.so system/lib/*.so; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
        [ -e "system/lib/$n" ] || [ -e "system/lib/hw/$n" ] || [ -e "vendor/lib/$n" ] || [ -e "vendor/lib/hw/$n" ] || echo "$n (needed by $f)"
    done
done | sort -u)
for f in system/lib/android.hardware.keymaster@3.0-impl.so system/lib/libkeymaster3device.so \
         system/lib/libsoftkeymasterdevice.so system/etc/task_profiles.json system/etc/vintf/manifest.xml \
         system/etc/vintf/manifest/android.system.keystore2-service.xml; do
    [ -f "$CHK/$f" ] || miss="$miss
$f (file)"
done
for f in system/bin/bootstrap/linker vendor/lib/hw/android.hardware.keymaster@3.0-impl.so; do
    [ -L "$CHK/$f" ] || miss="$miss
$f (link)"
done
miss=$(echo "$miss" | sed '/^$/d')
rm -rf "$CHK"
if [ -n "$miss" ]; then echo "$miss" | sed 's/^/   MISSING after trim: /'; exit 1; fi
echo "   ok   trimmed ramdisk: all dependencies present"

echo "== pack Samsung recovery image (kernel + TWRP ramdisk + dt.img + SEANDROIDENFORCE)"
MK=$KEEP/bin/mkdtbhbootimg
# date and time, so two builds on the same day never share a file name
DATE=$(date +%Y%m%d-%H%M)
DST=$HOME/twrp-out; mkdir -p "$DST"
# Name files after the version TWRP reports: TW_MAIN_VERSION_STR + "-" + TW_DEVICE_VERSION
TWVER=$(sed -n 's/.*TW_MAIN_VERSION_STR *"\([^"]*\)".*/\1/p' "$T/bootable/recovery/variables.h")-$(sed -n 's/^TW_DEVICE_VERSION := *//p' "$D/BoardConfig.mk")
NAME=twrp-$TWVER-gvwifi-$DATE
echo "   TWRP version: $TWVER"
IMG=$DST/$NAME.img
# Samsung S-Boot loads the WHOLE image at RAM 0x40204800 and puts the ramdisk at 0x42000000
# (last_kmsg: "pack_atags: ramdisk ... start 0x42000000"). The LineageOS images (27-28 MB)
# boot; TWRP at 32.2 MB, which crosses 0x42000000, hung before the kernel logged anything,
# also with the header ramdisk_offset raised to 0x02800000 (S-Boot apparently ignores it).
# So keep the stock offset and keep the image inside the window.
RAMDISK_OFFSET=0x02000000
"$MK" --kernel "$D/prebuilt/Image" --ramdisk "$TRIM" --dt "$D/prebuilt/dt.img" \
    --base 0x10000000 --pagesize 2048 --kernel_offset 0x00008000 --ramdisk_offset $RAMDISK_OFFSET \
    --tags_offset 0x00000100 --cmdline "" --output "$IMG"
echo -n "SEANDROIDENFORCE" >> "$IMG"
SIZE=$(stat -c %s "$IMG"); MAX=39845888
RD_SIZE=$(stat -c %s "$TRIM")
LOAD=$((0x40204800)); RD_DST=$((0x40000000 + RAMDISK_OFFSET)); MOBICORE=$((0x43e00000))
MARGIN=$((512 * 1024))
echo "image $SIZE bytes (partition $MAX); loaded image ends 0x$(printf %x $((LOAD + SIZE))), ramdisk at 0x$(printf %x $RD_DST); margin $(( (RD_DST - LOAD - SIZE) / 1024 )) KB"
[ "$SIZE" -le "$MAX" ] || { echo "TOO BIG for the recovery partition"; exit 1; }
[ $((LOAD + SIZE + MARGIN)) -le $RD_DST ] || { echo "image too big for S-Boot's load window (needs <= $((RD_DST - LOAD - MARGIN)) bytes)"; exit 1; }
[ $((RD_DST + RD_SIZE)) -le $MOBICORE ] || { echo "ramdisk would run into the MobiCore region"; exit 1; }
( cd "$DST" && cp "$IMG" recovery.img && tar -H ustar -cf "$NAME.tar" recovery.img && rm recovery.img )
sha256sum "$IMG" "$DST/$NAME.tar"
