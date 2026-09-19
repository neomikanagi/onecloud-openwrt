# SPDX-License-Identifier: GPL-2.0-or-later
#
# sysupgrade for Amlogic Meson8b eMMC devices.
#
# The image is a full MBR disk image, but only the two partitions it
# declares are written: p1 (FAT boot: uImage/dtb/boot.scr) and p2 (ext4
# rootfs). The MBR itself, the 4 MiB Amlogic bootloader gap in front of
# it and anything past p2 are never touched, so u-boot survives and the
# box stays recoverable without the USB Burning Tool.

REQUIRE_IMAGE_METADATA=1

platform_check_image() {
	local diskdev magic

	[ "$#" -gt 1 ] && return 1

	export_bootdevice && export_partdevice diskdev 0 || {
		v "Unable to determine boot device"
		return 1
	}

	get_image_dd "$1" of=/tmp/image.bs count=1 bs=512b
	magic=$(hexdump -v -n 2 -s 510 -e '1/1 "%02x"' /tmp/image.bs)
	rm -f /tmp/image.bs

	[ "$magic" = "55aa" ] || {
		v "Invalid image: no MBR signature found"
		return 1
	}

	return 0
}

platform_do_upgrade() {
	local diskdev partdev part start size devsize

	export_bootdevice && export_partdevice diskdev 0 || {
		v "Unable to determine boot device"
		return 1
	}

	v "Reading partition table from the image"
	get_image_dd "$1" of=/tmp/image.bs count=1 bs=512b
	get_partitions /tmp/image.bs image
	rm -f /tmp/image.bs

	[ -s /tmp/partmap.image ] || {
		v "Image has no usable partition table"
		return 1
	}

	sync

	while read part start size; do
		case "$part" in
		1|2) ;;
		*)
			v "Leaving partition $part on /dev/$diskdev alone"
			continue
			;;
		esac

		export_partdevice partdev "$part" || {
			v "Unable to find partition $part on /dev/$diskdev, skipped"
			continue
		}

		devsize=$(cat "/sys/class/block/$partdev/size" 2>/dev/null)
		[ -n "$devsize" ] && [ "$size" -gt "$devsize" ] && {
			v "Refusing upgrade: image partition $part needs $size sectors, /dev/$partdev only has $devsize"
			return 1
		}

		v "Writing image partition $part to /dev/$partdev..."
		get_image_dd "$1" of="/dev/$partdev" ibs=512 obs=1M \
			skip="$start" count="$size" conv=fsync || return 1
	done < /tmp/partmap.image

	rm -f /tmp/partmap.image
	sync
	sleep 1
}

platform_copy_config() {
	local partdev

	export_bootdevice && export_partdevice partdev 1 || return 0

	mkdir -p /boot
	mount -t vfat -o rw,noatime "/dev/$partdev" /boot || return 0
	cp -af "$UPGRADE_BACKUP" "/boot/$BACKUP_FILE"
	sync
	umount /boot
}
