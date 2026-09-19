# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2013 OpenWrt.org

include $(TOPDIR)/rules.mk

ARCH:=arm
BOARD:=amlogic
BOARDNAME:=Amlogic Meson family
FEATURES:=boot-part rootfs-part ext4 fpu usbgadget
SUBTARGETS:=meson8b

KERNEL_PATCHVER:=6.12

define Target/Description
	Build firmware images for Amlogic Meson8b (S805) devices.
endef

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += \
	blkid \
	kmod-gpio-button-hotplug \
	e2fsprogs \
	losetup \
	partx-utils \
	resize2fs

KERNELNAME:=Image dtbs

$(eval $(call BuildTarget))
