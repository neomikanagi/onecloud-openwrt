# SPDX-License-Identifier: GPL-2.0-or-later
#
# OneCloud sysupgrade: write boot (p1) + rootfs (p2) only.
# Leaves Amlogic u-boot (pre-MBR) and data partition (p3) untouched.
# Accepts gzip-compressed or raw eMMC disk images (MBR).

REQUIRE_IMAGE_METADATA=0
RAMFS_COPY_BIN="head df"

fwtool_check_signature() {
	[ $# -gt 1 ] && return 1
	return 0
}

fwtool_check_image() {
	[ $# -gt 1 ] && return 1
	return 0
}

detect_img_cat() {
	local magic
	magic=$(dd if="$1" bs=2 count=1 2>/dev/null | hexdump -n 2 -e '1/1 "%02x"')
	[ "$magic" = "1f8b" ] && echo "zcat" || echo "cat"
}

find_emmc_device() {
	local dev fallback=""
	for dev in mmcblk1 mmcblk0; do
		[ -b "/dev/$dev" ] || continue
		[ "$(cat /sys/block/$dev/device/type 2>/dev/null)" = "MMC" ] && { echo "$dev"; return 0; }
		[ -z "$fallback" ] && ls "/dev/${dev}p"* >/dev/null 2>&1 && fallback="$dev"
	done
	[ -n "$fallback" ] && echo "$fallback" && return 0
	return 1
}

platform_check_image() {
	local img_cat magic
	img_cat=$(detect_img_cat "$1")
	magic=$($img_cat "$1" 2>/dev/null | dd bs=1 skip=510 count=2 2>/dev/null | hexdump -v -n 2 -e '1/1 "%02x"')
	[ "$magic" = "55aa" ] || { echo "Invalid image: expected eMMC disk image (MBR)." >&2; return 1; }
	return 0
}

# Stream bytes [skip, skip+count) from image onto a block device.
stream_part() {
	local img="$1" img_cat="$2" skip_bytes="$3" nbytes="$4" dest="$5"
	$img_cat "$img" 2>/dev/null | tail -c +$((skip_bytes + 1)) | head -c "$nbytes" > "$dest"
}

platform_do_upgrade() {
	local emmc_dev img_cat mbr_header="/tmp/mbr_header.img"
	local p1_start p1_sectors p2_start p2_sectors backup_file

	echo "platform_do_upgrade: flashing boot(p1)+rootfs(p2), preserving u-boot and data(p3)"

	emmc_dev=$(find_emmc_device) || {
		echo "ERROR: no eMMC device"
		return 1
	}
	echo "platform_do_upgrade: eMMC=/dev/$emmc_dev"

	backup_file=""
	for candidate in "$UPGRADE_BACKUP" "/tmp/sysupgrade.tgz" "/tmp/root/tmp/sysupgrade.tgz"; do
		if [ -n "$candidate" ] && [ -f "$candidate" ]; then
			backup_file="$candidate"
			break
		fi
	done

	img_cat=$(detect_img_cat "$1")
	rm -f "$mbr_header"
	$img_cat "$1" 2>/dev/null | dd of="$mbr_header" bs=1M count=1 2>/dev/null
	[ -s "$mbr_header" ] || { echo "ERROR: failed to read MBR"; return 1; }

	p1_start=$(dd if="$mbr_header" bs=1 skip=454 count=4 2>/dev/null | hexdump -e '1/4 "%d"')
	p1_sectors=$(dd if="$mbr_header" bs=1 skip=458 count=4 2>/dev/null | hexdump -e '1/4 "%d"')
	p2_start=$(dd if="$mbr_header" bs=1 skip=470 count=4 2>/dev/null | hexdump -e '1/4 "%d"')
	p2_sectors=$(dd if="$mbr_header" bs=1 skip=474 count=4 2>/dev/null | hexdump -e '1/4 "%d"')
	rm -f "$mbr_header"

	if [ -z "$p1_start" ] || [ -z "$p2_start" ] || [ "$p1_sectors" = "0" ] || [ "$p2_sectors" = "0" ]; then
		echo "ERROR: failed to parse MBR"
		return 1
	fi

	echo "platform_do_upgrade: p1 start=$p1_start sectors=$p1_sectors ($((p1_sectors/2048))MB)"
	echo "platform_do_upgrade: p2 start=$p2_start sectors=$p2_sectors ($((p2_sectors/2048))MB)"

	sync
	echo "platform_do_upgrade: writing boot p1..."
	stream_part "$1" "$img_cat" $((p1_start * 512)) $((p1_sectors * 512)) "/dev/${emmc_dev}p1"
	sync
	echo "platform_do_upgrade: writing rootfs p2..."
	stream_part "$1" "$img_cat" $((p2_start * 512)) $((p2_sectors * 512)) "/dev/${emmc_dev}p2"
	sync

	if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
		mkdir -p /mnt
		if mount -t vfat -o rw,noatime "/dev/${emmc_dev}p1" /mnt 2>/dev/null; then
			cp -af "$backup_file" /mnt/sysupgrade.tgz 2>/dev/null
			sync
			umount /mnt 2>/dev/null
			echo "platform_do_upgrade: config saved to p1"
		fi
	fi

	echo "platform_do_upgrade: done"
	return 0
}

platform_copy_config() {
	return 0
}
