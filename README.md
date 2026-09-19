# onecloud-openwrt

玩客云（迅雷 OneCloud / Amlogic S805 / meson8b，32 位）的 **官方 OpenWrt 25.12** 精简固件。

每月 1 号云编译。源码是 [openwrt/openwrt](https://github.com/openwrt/openwrt) 的 `openwrt-25.12` 稳定分支，设备支持用自定义 `target/linux/amlogic` 注入（官方 24.10+ 已删除 32 位 meson8b target）。

## 默认

| 项 | 值 |
| --- | --- |
| LAN | `10.10.11.1/24`（对应 ssh host `op1`；N1/`op0` 已占用 `10.10.10.1`） |
| 用户 / 密码 | `root` / `password` |
| 主机名 | `op1` |
| 时区 / NTP | `Asia/Tokyo`；`time.windows.com` `time.apple.com` `time.google.com` `time.aws.com` `time.cloudflare.com`，并开 NTP server |
| WAN | `eth1` DHCP（USB 网卡 / 手机共享），没有就不工作，LAN 仍可用 |
| LuCI | 官方 luci + bootstrap + 简体中文 |
| 防火墙 | firewall4 / nftables |

## 装了什么 / 砍了什么

**留：** Docker 全家桶 + `luci-app-dockerman`（数据目录 `/mnt/data/docker`，sysupgrade 不丢容器）、HomeProxy + sing-box、zram、BBR+fq、irqbalance、packet_steering、ttyd、UPnP、USB 存储、手机共享/USB 网卡驱动、常见 USB WiFi（mt76u / rtl8xxxu / rt2800）、WireGuard、SFTP。

**砍：** LXC、晶晨宝盒 `luci-app-amlogic`、Samba、DDNS、frp、mosdns、Argon、Passwall、SQM、attended sysupgrade。

**不装 mosdns 的原因：** 现网 `op0` 的 DNS 已经是 `dnsmasq:53 → sing-box/homeproxy:5333`（DoH + 广告规则集）。mosdns 会再加一层 Go 进程和配置，和 HomeProxy 功能重叠，1GB/32 位上是负担，不是免费升级。

玩客云只有 1GB RAM + 32 位。Docker 镜像大量是 aarch64，能跑的是 `linux/arm/v7`。这是硬件限制，不是固件漏装。

## 刷机与更新

### 第一次（或变砖）

1. Releases 里下 `*emmc.burn.img.xz`
2. [Amlogic USB Burning Tool](https://androiddatahost.com/khfj4) + 双公头 USB
3. 红灯闪 = 启动中，蓝灯心跳 = 起来了（第一次可能要几分钟）

### 以后每月更新（这才是重点）

已经刷过一次、eMMC 上是这套分区之后：

- LuCI → 系统 → 备份/升级，刷 `*sysupgrade.bin` 或 `*emmc.img.gz`
- 或 SSH：`sysupgrade -n /tmp/xxx.img.gz`（要保留配置去掉 `-n`）

脚本只写 **p1 boot（内核+dtb）+ p2 rootfs**，**不动 u-boot，不动 p3 `/mnt/data`**。

剩余 eMMC 第一次启动会建成 p3，挂在 `/mnt/data`。Docker 默认写这里。

### USB 卡刷进 eMMC（armbian-install 同类）

前提：机器已经线刷过一次（u-boot 能 USB 启动）。

1. 把 `*emmc.img` dd 到 U 盘
2. 串口打断 u-boot，或等 eMMC 失败后自动尝试 USB（`boot.txt` 有 USB fallback）
3. 进系统后：

```sh
onecloud-install-emmc          # 把当前 USB 系统拷到 eMMC p1+p2
# 或
onecloud-install-emmc /tmp/xxx-emmc.img.gz
```

全网以前几乎没有这条路径，不是做不出来，是打包方式决定的。见下面。

## 为什么以前没有「卡刷进 eMMC」的玩客云 OpenWrt

N1 能 `openwrt-install` / Armbian 能 `armbian-install`，玩客云 OpenWrt 却几乎全是线刷包或让你插着 U 盘用。原因不是 magick，是三件事叠在一起：

1. **引导协议不同。** 玩客云出厂是晶晨 USB Burning 协议。没有 TF 卡槽。第一次进任何非安卓系统，都必须用 `burn.img` 把 u-boot 写进 eMMC。N1 的 u-boot 已经能从 USB/SD 起完整 Linux，所以「先 U 盘再 install」是默认故事。

2. **打包目标不同。** N1/ophub 走的是 **通用 aarch64 rootfs tarball + flippy 内核 + luci-app-amlogic**：镜像是「可安装的系统」，install 脚本负责分区、拷文件、写 u-boot。玩客云社区（LEDE / 各种 Actions）走的是 **整盘 eMMC 镜像**，再额外打成 Burning Tool 格式。产物是「整盘快照」，不是「可 sysupgrade 的设备」。`IMAGES := emmc.img`，没有 `sysupgrade.bin`，`platform.sh` 也是空的。所以你只能再线刷一次。

3. **官方已经删了 32 位 meson8b。** OpenWrt 24.10+ 和 ImmortalWrt 都不再带这个 target。社区各自抄一份 DTS + 自己的 image Makefile，大多数人只做到「能烧进去」，没有把 OpenWrt 的 `sysupgrade` / `emmc_do_upgrade` 接上。接上之后，更新路径就是普通路由器那条，不需要 armbian-install。

**能做出来。** 本仓库做了三件事：

- 官方 25.12 源码 + 注入 meson8b-onecloud target（DTS / 6.12 内核补丁 / u-boot 打包）
- 同时打出 `burn.img`（第一次）、`emmc.img`（U 盘）、`sysupgrade.bin`（以后）
- `platform.sh` 按分区写 p1+p2；`onecloud-install-emmc` 给「已经能 USB 启动」的机器一条和 armbian-install 同类的命令

第一次仍然要线刷一次——这是晶晨 ROM 决定的，谁也跳不过。线刷过之后，更新不再拆机、不再双公头。

## 自己编译

GitHub Actions → **Build OpenWrt OneCloud** → Run workflow。或 fork 后等每月 1 号。

本地（Linux x86_64，磁盘 > 30G）：

```sh
git clone --depth=1 -b openwrt-25.12 https://github.com/openwrt/openwrt.git
cp -a target files openwrt/
cd openwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../config/onecloud.config .config
../scripts/diy-part2.sh 10.10.11.1 true
make defconfig
make -j$(nproc)
```

## 参考

- 设备树 / u-boot：[hzyitc/u-boot-onecloud](https://github.com/hzyitc/u-boot-onecloud)、[hzyitc/AmlImg](https://github.com/hzyitc/AmlImg)
- target 参考：[lxhao61/OneCloud-OpenWrt](https://github.com/lxhao61/OneCloud-OpenWrt)（官方 25.12 + 6.12）、[jovinleung/OneCloud](https://github.com/jovinleung/OneCloud)（sysupgrade / burn 脚本）
- N1 定制层：`neomikanagi/amlogic-s9xxx-openwrt`（IP/NTP/HomeProxy/Docker 取向）
