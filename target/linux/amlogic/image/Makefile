# SPDX-License-Identifier: GPL-2.0-only
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

FAT32_BLOCK_SIZE=1024
FAT32_BLOCKS=$(shell echo $$(($(CONFIG_TARGET_KERNEL_PARTSIZE)*1024*1024/$(FAT32_BLOCK_SIZE))))

# FAT boot partition: boot.scr + uImage + dtb, exactly the layout the
# OneCloud u-boot expects.
define Build/boot-part
	rm -f $@.boot
	mkfs.fat -n BOOT -C $@.boot $(FAT32_BLOCKS)
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "boot.scr" \
		-d boot.txt $(KDIR)/boot.scr
	mcopy -i $@.boot $(KDIR)/boot.scr ::boot.scr
	mcopy -i $@.boot $(IMAGE_KERNEL) ::uImage
	$(foreach dts,$(DEVICE_DTS),mcopy -i $@.boot $(DTS_DIR)/$(dts).dtb ::dtb;)
endef

# MBR disk image: 4 MiB gap for the Amlogic bootloader, p1 FAT boot, p2 ext4 root.
define Build/emmc-img
	./gen_aml_emmc_img.sh $@ $@.boot $(IMAGE_ROOTFS) \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $(CONFIG_TARGET_ROOTFS_PARTSIZE)
	rm -f $@.boot
endef

### Devices ###
define Device/Default
  FILESYSTEMS := ext4
  KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
  KERNEL_NAME := Image
  KERNEL_LOADADDR := 0x00208000
  KERNEL := kernel-bin | uImage none
  IMAGES := sysupgrade.img.gz
  IMAGE/sysupgrade.img.gz := boot-part | emmc-img | gzip | append-metadata
  PROFILES = Default $$(DEVICE_NAME)
endef

define Device/thunder-onecloud
  DEVICE_VENDOR := Thunder
  DEVICE_MODEL := OneCloud
  DEVICE_DTS := amlogic/meson8b-onecloud
  SUPPORTED_DEVICES := thunder,onecloud
endef

ifeq ($(SUBTARGET),meson8b)
  TARGET_DEVICES += thunder-onecloud
endif

$(eval $(call BuildImage))
