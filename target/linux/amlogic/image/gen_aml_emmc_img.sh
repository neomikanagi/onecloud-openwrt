#!/bin/sh
#
# Copyright (C) 2017 OpenWrt.org
#
# Generate Amlogic eMMC disk image:
#   bootloader at sector 1, resource at 12MB, MBR: boot(FAT) + rootfs(ext4) + data(ext4)

[ $# -eq 5 ] || {
    echo "SYNTAX: $0 <file> <bootfs image> <rootfs image> <bootfs size> <rootfs size>"
    exit 1
}

OUTPUT="$1"
BOOTFS="$2"
ROOTFS="$3"
BOOTFSSIZE="$4"
ROOTFSSIZE="$5"

# eMMC total size in MB (OneCloud 8GB eMMC actual usable ~7.28GB)
# p3 (data partition) will fill the remaining space after p2
EMMC_SIZE_MB="${EMMC_SIZE_MB:-7424}"

# Use real rootfs size if larger
if [ -f "$ROOTFS" ]; then
    ROOTFS_REAL_SIZE=$(wc -c < "$ROOTFS" | tr -d ' ')
    ROOTFS_REAL_SIZE_MB=$((ROOTFS_REAL_SIZE / 1024 / 1024))
    [ "$ROOTFS_REAL_SIZE_MB" -gt "$ROOTFSSIZE" ] && ROOTFSSIZE="$ROOTFS_REAL_SIZE_MB"
fi

head=4
sect=2048

# Step 1: Generate MBR with p1+p2 only to get p2 end offset
TMP_PT=$(mktemp)
set -- $(ptgen -o "$TMP_PT" -h $head -s $sect -l 32768 -t c -p ${BOOTFSSIZE}M -t 83 -p ${ROOTFSSIZE}M | grep -E '^[0-9]+$')
P2_OFFSET_BYTES="$3"
P2_SIZE_BYTES="$4"
P2_END_MB=$(( (P2_OFFSET_BYTES + P2_SIZE_BYTES) / 1024 / 1024 ))
rm -f "$TMP_PT"

# Step 2: Calculate p3 size (remaining space, aligned to 4MB cylinder)
P3_SIZE_MB=$(( EMMC_SIZE_MB - P2_END_MB ))
# Align down to 4MB (cylinder size = head*sect = 4*2048 = 8192 sectors = 4MB)
P3_SIZE_MB=$(( P3_SIZE_MB - (P3_SIZE_MB % 4) ))

# Safety: ensure at least 16MB for data partition; skip p3 if too small
if [ "$P3_SIZE_MB" -lt 16 ]; then
    echo "WARNING: insufficient space for data partition (${P3_SIZE_MB}MB), skipping p3"
    P3_SIZE_MB=0
fi

echo "    eMMC total: ${EMMC_SIZE_MB}MB"
echo "    p2 end at: ${P2_END_MB}MB"
echo "    p3 (data) size: ${P3_SIZE_MB}MB"

# Step 3: Generate MBR with p1=FAT(c), p2=Linux(83), p3=Linux(83) if size > 0
if [ "$P3_SIZE_MB" -gt 0 ]; then
    set -- $(ptgen -o $OUTPUT -h $head -s $sect -l 32768 \
        -t c -p ${BOOTFSSIZE}M \
        -t 83 -p ${ROOTFSSIZE}M \
        -t 83 -p ${P3_SIZE_MB}M | grep -E '^[0-9]+$')
else
    set -- $(ptgen -o $OUTPUT -h $head -s $sect -l 32768 \
        -t c -p ${BOOTFSSIZE}M \
        -t 83 -p ${ROOTFSSIZE}M | grep -E '^[0-9]+$')
fi

BOOTOFFSET="$(($1 / 512))"
BOOTSIZE="$(($2 / 512))"
ROOTFSOFFSET="$(($3 / 512))"
ROOTFSSIZE="$(($4 / 512))"
DATAOFFSET="${5:-0}"
DATASIZE="${6:-0}"
[ -n "$DATAOFFSET" ] && DATAOFFSET="$(($DATAOFFSET / 512))" || DATAOFFSET=0
[ -n "$DATASIZE" ] && DATASIZE="$(($DATASIZE / 512))" || DATASIZE=0

echo "    boot partition: offset=$BOOTOFFSET sectors, size=$((BOOTSIZE*512/1024/1024))MB"
echo "    rootfs partition: offset=$ROOTFSOFFSET sectors, size=$((ROOTFSSIZE*512/1024/1024))MB"
[ "$DATASIZE" -gt 0 ] && echo "    data partition: offset=$DATAOFFSET sectors, size=$((DATASIZE*512/1024/1024))MB"

# Write partitions (p3 left unformatted/zero for user data)
dd bs=512 if="$BOOTFS" of="$OUTPUT" seek="$BOOTOFFSET" conv=notrunc 2>/dev/null
dd bs=512 if="$ROOTFS" of="$OUTPUT" seek="$ROOTFSOFFSET" conv=notrunc 2>/dev/null

# Write Amlogic bootloader (sector 1) and resource (sector 24576 = 12MB)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UBOOT_IMG="$SCRIPT_DIR/u-boot-onecloud.img"
AMLIMG="$SCRIPT_DIR/AmlImg"

if [ -f "$UBOOT_IMG" ] && [ -x "$AMLIMG" ]; then
    EXTRACT_DIR="$(mktemp -d)"
    if "$AMLIMG" unpack "$UBOOT_IMG" "$EXTRACT_DIR/" >/dev/null 2>&1; then
        [ -f "$EXTRACT_DIR/4.bootloader.PARTITION" ] && dd bs=512 if="$EXTRACT_DIR/4.bootloader.PARTITION" of="$OUTPUT" seek=1 conv=notrunc 2>/dev/null && echo "    bootloader: written to sector 1"
        [ -f "$EXTRACT_DIR/6.resource.PARTITION" ] && dd bs=512 if="$EXTRACT_DIR/6.resource.PARTITION" of="$OUTPUT" seek=24576 conv=notrunc 2>/dev/null && echo "    resource: written to sector 24576 (12MB)"
    fi
    rm -rf "$EXTRACT_DIR"
elif [ -f "$SCRIPT_DIR/bootloader.bin" ]; then
    dd bs=512 if="$SCRIPT_DIR/bootloader.bin" of="$OUTPUT" seek=1 conv=notrunc 2>/dev/null
    [ -f "$SCRIPT_DIR/resource.bin" ] && dd bs=512 if="$SCRIPT_DIR/resource.bin" of="$OUTPUT" seek=24576 conv=notrunc 2>/dev/null
fi
