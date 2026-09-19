#!/bin/bash
# After feeds install. Args: LAN_IP [use_ccache]
set -euo pipefail

LAN_IP="${1:-10.10.11.1}"
USE_CCACHE="${2:-true}"

# HomeProxy (sing-box LuCI) — same source as N1 fork
rm -rf package/homeproxy
git clone --depth=1 https://github.com/immortalwrt/homeproxy.git package/homeproxy

# LAN IP (N1 uses 10.10.10.1; OneCloud defaults to 10.10.11.1 = ssh host op1)
if grep -q 'ipaddr:-"192.168.1.1"' package/base-files/files/bin/config_generate 2>/dev/null; then
	sed -i "s/ipaddr:-\"192.168.1.1\"/ipaddr:-\"${LAN_IP}\"/" package/base-files/files/bin/config_generate
fi
sed -i "s/192.168.1.1/${LAN_IP}/g" package/base-files/files/bin/config_generate

# Hostname / timezone (match op0: JST-9)
sed -i "s/hostname='OpenWrt'/hostname='op1'/g" package/base-files/files/bin/config_generate
sed -i "s/timezone='UTC'/timezone='JST-9'/g" package/base-files/files/bin/config_generate
sed -i "/timezone='JST-9'/a\\		set system.@system[-1].zonename='Asia/Tokyo'" package/base-files/files/bin/config_generate

# NTP — same as N1
sed -i 's/0.openwrt.pool.ntp.org/time.windows.com/' package/base-files/files/bin/config_generate
sed -i 's/1.openwrt.pool.ntp.org/time.apple.com/' package/base-files/files/bin/config_generate
sed -i 's/2.openwrt.pool.ntp.org/time.google.com/' package/base-files/files/bin/config_generate
sed -i 's/3.openwrt.pool.ntp.org/time.aws.com/' package/base-files/files/bin/config_generate
if grep -q "add_list system.ntp.server='time.aws.com'" package/base-files/files/bin/config_generate; then
	sed -i "/add_list system.ntp.server='time.aws.com'/a\\		add_list system.ntp.server='time.cloudflare.com'" package/base-files/files/bin/config_generate
fi

# root password = password (same as N1 ophub)
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# Banner / release stamp
if [ -f package/base-files/files/etc/openwrt_release ]; then
	sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/base-files/files/etc/openwrt_release
	grep -q DISTRIB_SOURCEREPO package/base-files/files/etc/openwrt_release || {
		echo "DISTRIB_SOURCEREPO='github.com/openwrt/openwrt'" >> package/base-files/files/etc/openwrt_release
		echo "DISTRIB_SOURCECODE='openwrt'" >> package/base-files/files/etc/openwrt_release
		echo "DISTRIB_SOURCEBRANCH='openwrt-25.12'" >> package/base-files/files/etc/openwrt_release
	}
fi

# ccache
sed -i '/CONFIG_DEVEL/d' .config
sed -i '/CONFIG_CCACHE/d' .config
if [ "${USE_CCACHE}" = "true" ]; then
	echo "CONFIG_DEVEL=y" >> .config
	echo "CONFIG_CCACHE=y" >> .config
fi

echo "diy-part2 done (LAN=${LAN_IP})"
