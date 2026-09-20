#!/bin/bash
# Runs inside the OpenWrt tree after `feeds install`.
# Usage: diy-part2.sh [LAN_IP] [use_ccache]
set -euo pipefail

LAN_IP="${1:-10.10.10.1}"
USE_CCACHE="${2:-true}"

CFG=package/base-files/files/bin/config_generate

# HomeProxy is not in the official feeds; it lives in its own repo.
rm -rf package/homeproxy
git clone --depth=1 https://github.com/immortalwrt/homeproxy.git package/homeproxy

# LAN address
sed -i "s/192\.168\.1\.1/${LAN_IP}/g" "$CFG"

# Hostname. Timezone (Asia/Tokyo) is set in files/etc/uci-defaults/99-onecloud:
# 25.12's config_generate uses timezone='GMT0', so sed on timezone='UTC' misses.
sed -i "s/hostname='OpenWrt'/hostname='OneCloud'/g" "$CFG"

# NTP pool -> reachable public servers, plus keep serving time on the LAN
sed -i 's/0\.openwrt\.pool\.ntp\.org/time.windows.com/' "$CFG"
sed -i 's/1\.openwrt\.pool\.ntp\.org/time.apple.com/' "$CFG"
sed -i 's/2\.openwrt\.pool\.ntp\.org/time.google.com/' "$CFG"
sed -i 's/3\.openwrt\.pool\.ntp\.org/time.cloudflare.com/' "$CFG"

# Default root password: "password". Change it on first login.
sed -i 's|^root:::0:99999:7:::|root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::|' \
	package/base-files/files/etc/shadow

# Version stamp
if [ -f package/base-files/files/etc/openwrt_release ]; then
	sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" \
		package/base-files/files/etc/openwrt_release
fi

# ccache
sed -i '/CONFIG_DEVEL/d;/CONFIG_CCACHE/d' .config
if [ "${USE_CCACHE}" = "true" ]; then
	printf 'CONFIG_DEVEL=y\nCONFIG_CCACHE=y\n' >> .config
fi

echo "diy-part2: LAN=${LAN_IP} ccache=${USE_CCACHE}"
