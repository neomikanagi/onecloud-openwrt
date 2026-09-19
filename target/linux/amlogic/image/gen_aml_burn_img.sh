#!/bin/sh
# Generate Amlogic USB Burning Tool image from eMMC disk image
# Usage: gen_aml_burn_img.sh <input.emmc.img> <output.burn.img>

set -e

INPUT_IMG="$1"
OUTPUT_IMG="$2"

[ -z "$INPUT_IMG" ] || [ -z "$OUTPUT_IMG" ] && { echo "Usage: $0 <input.emmc.img> <output.burn.img>"; exit 1; }
[ ! -f "$INPUT_IMG" ] && { echo "ERROR: input file not found: $INPUT_IMG"; exit 1; }

AMLIMG_VERSION="v0.3.1"
UBOOT_URL="https://github.com/hzyitc/u-boot-onecloud/releases/download/build-20221028-0940/eMMC.burn.img"

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# [1/6] Locate AmlImg (local, PATH, or download/build)
echo "==> [1/6] Preparing AmlImg tool"

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "linux_amd64" ;;
        aarch64|arm64) echo "linux_arm64" ;;
        armv7l|arm)    echo "linux_arm" ;;
        i386|i686)      echo "linux_386" ;;
        *) echo "ERROR: unsupported arch: $(uname -m)" >&2; exit 1 ;;
    esac
}

check_amlimg() {
    [ -x "$1" ] || return 1
    local fo=$(file "$1" 2>/dev/null) || return 1
    case "$(uname -s)" in
        Darwin) echo "$fo" | grep -q "Mach-O" || return 1 ;;
        Linux)  echo "$fo" | grep -q "ELF"     || return 1 ;;
    esac
    return 0
}

find_amlimg() {
    check_amlimg "$SCRIPT_DIR/AmlImg" && { echo "$SCRIPT_DIR/AmlImg"; return 0; }
    command -v AmlImg >/dev/null 2>&1 && check_amlimg "$(command -v AmlImg)" && { command -v AmlImg; return 0; }
    [ -n "$STAGING_DIR" ] && check_amlimg "$STAGING_DIR/host/bin/AmlImg" && { echo "$STAGING_DIR/host/bin/AmlImg"; return 0; }
    return 1
}

AMLIMG=$(find_amlimg 2>/dev/null || true)
if [ -z "$AMLIMG" ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
        echo "    Building AmlImg from source for macOS..."
        command -v go >/dev/null 2>&1 || { echo "ERROR: Go required" >&2; exit 1; }
        MAC_ARCH=$(uname -m)
        case "$MAC_ARCH" in arm64) GOARCH=arm64 ;; x86_64) GOARCH=amd64 ;; *) echo "ERROR: unsupported macOS arch" >&2; exit 1 ;; esac
        git clone --depth 1 https://github.com/hzyitc/AmlImg.git "$WORKDIR/AmlImg-src" >/dev/null 2>&1
        (cd "$WORKDIR/AmlImg-src" && GOOS=darwin GOARCH=$GOARCH go build -o "$WORKDIR/AmlImg" .) >/dev/null 2>&1
        chmod +x "$WORKDIR/AmlImg"
        AMLIMG="$WORKDIR/AmlImg"
    else
        echo "    Downloading AmlImg..."
        AMLIMG_ARCH=$(detect_arch)
        curl -sL --fail -o "$WORKDIR/AmlImg" \
            "https://github.com/hzyitc/AmlImg/releases/download/${AMLIMG_VERSION}/AmlImg_${AMLIMG_VERSION}_${AMLIMG_ARCH}"
        chmod +x "$WORKDIR/AmlImg"
        AMLIMG="$WORKDIR/AmlImg"
    fi
fi
echo "    Using AmlImg: $AMLIMG"

# [2/6] Obtain u-boot
echo "==> [2/6] Obtaining OneCloud u-boot"
UBOOT_IMG="$WORKDIR/uboot.img"

if [ -f "$SCRIPT_DIR/u-boot-onecloud.img" ]; then
    cp "$SCRIPT_DIR/u-boot-onecloud.img" "$UBOOT_IMG"
    echo "    Using local u-boot"
else
    echo "    Downloading u-boot..."
    curl -sL --fail -o "$UBOOT_IMG" "$UBOOT_URL"
fi
echo "    u-boot size: $(du -h "$UBOOT_IMG" | cut -f1)"

# [3/6] Unpack u-boot base structure
echo "==> [3/6] Unpacking u-boot base structure"
BURN_DIR="$WORKDIR/burn"
mkdir -p "$BURN_DIR"
"$AMLIMG" unpack "$UBOOT_IMG" "$BURN_DIR/" >/dev/null
echo "    Unpacked: $(ls "$BURN_DIR" | wc -l) files"

# [4/6] Read MBR and extract partitions
echo "==> [4/6] Reading partition table and extracting partitions"

read_partitions() {
    python3 - "$INPUT_IMG" << 'PYEOF'
import struct, sys
with open(sys.argv[1], "rb") as f:
    f.seek(0x1BE)
    for i in range(4):
        entry = f.read(16)
        if len(entry) < 16: break
        part_type = entry[4]
        lba_start = struct.unpack("<I", entry[8:12])[0]
        num_sectors = struct.unpack("<I", entry[12:16])[0]
        if num_sectors > 0:
            print(f"{i+1} {part_type} {lba_start} {num_sectors}")
PYEOF
}

PARTITIONS=$(read_partitions)
echo "$PARTITIONS" | while read idx type start sectors; do
    echo "      partition $idx: type=0x$(printf '%02x' $type), start=$start, size=$((sectors*512/1024/1024))MB"
done

BOOT_INFO=$(echo "$PARTITIONS" | sed -n '1p')
BOOT_START=$(echo "$BOOT_INFO" | awk '{print $3}')
BOOT_SECTORS=$(echo "$BOOT_INFO" | awk '{print $4}')

ROOTFS_INFO=$(echo "$PARTITIONS" | sed -n '2p')
ROOTFS_START=$(echo "$ROOTFS_INFO" | awk '{print $3}')
ROOTFS_SECTORS=$(echo "$ROOTFS_INFO" | awk '{print $4}')

dd if="$INPUT_IMG" of="$WORKDIR/boot.img" bs=512 skip="$BOOT_START" count="$BOOT_SECTORS" 2>/dev/null
dd if="$INPUT_IMG" of="$WORKDIR/rootfs_raw.img" bs=512 skip="$ROOTFS_START" count="$ROOTFS_SECTORS" 2>/dev/null
echo "    boot partition: $(du -h "$WORKDIR/boot.img" | cut -f1)"
echo "    rootfs partition: $(du -h "$WORKDIR/rootfs_raw.img" | cut -f1)"

# [5/6] Prepare rootfs and convert to sparse
echo "==> [5/6] Preparing rootfs and converting to sparse"

E2FSCK=""
RESIZE2FS=""
IMG2SIMG=""

for p in /opt/homebrew/opt/e2fsprogs/sbin /opt/homebrew/sbin /usr/sbin /sbin; do
    [ -x "$p/e2fsck" ] && E2FSCK="$p/e2fsck"
    [ -x "$p/resize2fs" ] && RESIZE2FS="$p/resize2fs"
done
command -v e2fsck >/dev/null 2>&1 && E2FSCK="e2fsck"
command -v resize2fs >/dev/null 2>&1 && RESIZE2FS="resize2fs"
command -v img2simg >/dev/null 2>&1 && IMG2SIMG="img2simg"
[ -x "/opt/homebrew/bin/img2simg" ] && IMG2SIMG="/opt/homebrew/bin/img2simg"

ROOTFS_IMG="$WORKDIR/rootfs.img"
cp "$WORKDIR/rootfs_raw.img" "$ROOTFS_IMG"

# Fix filesystem and resize to exact size (prevents img2simg crashes)
[ -n "$E2FSCK" ] && $E2FSCK -fy "$ROOTFS_IMG" >/dev/null 2>&1 || true
if [ -n "$RESIZE2FS" ]; then
    ROOTFS_SIZE_MB=$((ROOTFS_SECTORS * 512 / 1024 / 1024))
    echo "    Resizing to ${ROOTFS_SIZE_MB}MB..."
    $RESIZE2FS -f "$ROOTFS_IMG" ${ROOTFS_SIZE_MB}M >/dev/null 2>&1 || true
fi

# Convert to sparse (fallback to raw if img2simg fails)
if [ -n "$IMG2SIMG" ]; then
    echo "    Converting to sparse format..."
    if $IMG2SIMG "$WORKDIR/boot.img" "$BURN_DIR/boot.simg" 2>/dev/null && \
       $IMG2SIMG "$ROOTFS_IMG" "$BURN_DIR/rootfs.simg" 2>/dev/null; then
        echo "    boot.simg: $(du -h "$BURN_DIR/boot.simg" | cut -f1)"
        echo "    rootfs.simg: $(du -h "$BURN_DIR/rootfs.simg" | cut -f1)"
        cat >> "$BURN_DIR/commands.txt" << 'EOF'
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF
    else
        echo "    WARNING: img2simg failed, using raw partitions"
        cp "$WORKDIR/boot.img" "$BURN_DIR/boot.img"
        cp "$ROOTFS_IMG" "$BURN_DIR/rootfs.img"
        cat >> "$BURN_DIR/commands.txt" << 'EOF'
PARTITION:boot:sparse:boot.img
PARTITION:rootfs:sparse:rootfs.img
EOF
    fi
else
    echo "    WARNING: img2simg not found, using raw partitions"
    cp "$WORKDIR/boot.img" "$BURN_DIR/boot.img"
    cp "$ROOTFS_IMG" "$BURN_DIR/rootfs.img"
    cat >> "$BURN_DIR/commands.txt" << 'EOF'
PARTITION:boot:sparse:boot.img
PARTITION:rootfs:sparse:rootfs.img
EOF
fi

# [6/6] Pack
echo "==> [6/6] Packing Amlogic burn image"
"$AMLIMG" pack "$OUTPUT_IMG" "$BURN_DIR/" >/dev/null
echo "    burn image size: $(du -h "$OUTPUT_IMG" | cut -f1)"

echo ""
echo "Done! Burn image generated: $OUTPUT_IMG"
