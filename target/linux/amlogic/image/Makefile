#
# Copyright (C) 2017 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

# FAT boot partition size in 1024-byte blocks (CONFIG_TARGET_KERNEL_PARTSIZE is in MB)
FAT32_BLOCKS=$(shell echo $$(($(CONFIG_TARGET_KERNEL_PARTSIZE)*1024)))

# Build FAT boot partition: boot.scr + kernel.img + dtb.img
define Build/boot-partition
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "boot.scr" \
		-d $(TOPDIR)/target/linux/amlogic/image/boot.txt $@.boot.scr
	mkfs.fat -n boot -C $@ $(FAT32_BLOCKS)
	mcopy -i $@ $@.boot.scr ::boot.scr
	mcopy -i $@ $(IMAGE_KERNEL) ::kernel.img
	mcopy -i $@ $(DTS_DIR)/$(DEVICE_DTS).dtb ::dtb.img
	rm -f $@.boot.scr
endef

# Build eMMC disk image: bootloader + resource + MBR(boot+rootfs)
define Build/emmc-image
	$(TOPDIR)/target/linux/amlogic/image/gen_aml_emmc_img.sh $@.new \
		$@ $(IMAGE_ROOTFS) \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $(CONFIG_TARGET_ROOTFS_PARTSIZE)
	mv $@.new $@
endef

# Convert to Amlogic USB Burning Tool format
define Build/aml-burn-img
	$(TOPDIR)/target/linux/amlogic/image/gen_aml_burn_img.sh $@ $@.new
	mv $@.new $@
endef

define Device/Default
  FILESYSTEMS := ext4
  IMAGES := emmc.img sysupgrade.bin burn.img
  KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
  KERNEL_LOADADDR := 0x00208000
  KERNEL_NAME := Image
  KERNEL := kernel-bin | uImage none
endef

define Device/thunder-onecloud
  DEVICE_DTS := amlogic/meson8b-onecloud
  DEVICE_TITLE := Thunder OneCloud
  IMAGE/emmc.img := boot-partition | emmc-image
  IMAGE/sysupgrade.bin := boot-partition | emmc-image | append-metadata
  IMAGE/burn.img := boot-partition | emmc-image | aml-burn-img
endef

ifeq ($(SUBTARGET),meson8b)
  TARGET_DEVICES += thunder-onecloud
endif

$(eval $(call BuildImage))
