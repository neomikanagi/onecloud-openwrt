# OneCloud OpenWrt

玩客云（Thunder OneCloud，Amlogic S805 / meson8b，32 位）的 OpenWrt 固件。

源码是官方 [openwrt/openwrt](https://github.com/openwrt/openwrt) 的 `openwrt-25.12` 稳定分支。官方源码树里没有 S805 的 target，设备支持（设备树、6.12 内核补丁、镜像打包）由本仓库的 `target/linux/amlogic` 提供。

每月 1 号自动云编译一次，产物发在 [Releases](../../releases)。

## 下载哪个文件

| 文件 | 什么时候用 |
| --- | --- |
| `*-emmc.burn.img.xz` | 第一次刷机，或者刷坏了要救砖 |
| `*-sysupgrade.img.gz` | 已经装好了，之后每次升级 |

## 第一次刷机

玩客云出厂只认晶晨的 USB 刷机协议，也没有 TF 卡槽，所以第一次必须线刷一次，把 u-boot 写进 eMMC。

1. 解压 `*-emmc.burn.img.xz`
2. 装 [Amlogic USB Burning Tool](https://androiddatahost.com/khfj4)，导入镜像
3. 拆机，短接主板上的刷机触点（或按住机内的小按钮），用双公头 USB 线接电脑，通电
4. 点开始，等进度走完

红灯闪 = 正在启动，蓝灯呼吸 = 已经起来了。第一次启动要多等一会儿，它在把根分区扩容到整块 eMMC。

启动完成后浏览器打开 `http://10.10.10.1`。

## 之后怎么升级

这是这个仓库存在的主要理由：**刷过一次之后就不用再拆机线刷了。**

LuCI → 系统 → 备份/升级 → 刷写新的固件，选 `*-sysupgrade.img.gz`。或者命令行：

```bash
sysupgrade -v /tmp/openwrt-*-sysupgrade.img.gz
```

升级只写引导分区和根分区，**不碰 u-boot**，所以升级失败也不会变砖，大不了再线刷一次。勾选「保留配置」会把 `/etc` 备份带到新系统里。

## 从 U 盘装进 eMMC

已经有 u-boot 的机器（也就是线刷过至少一次的），可以把镜像写进 U 盘启动，再装到 eMMC：

```bash
# 电脑上：把镜像写进 U 盘
gzip -dc openwrt-*-sysupgrade.img.gz | sudo dd of=/dev/sdX bs=4M status=progress

# 插上 U 盘开机，进系统后：
onecloud-install-emmc
```

引导脚本的顺序是 eMMC → SD → USB，所以 eMMC 里已经有能启动的系统时不会走 U 盘。

## 默认配置

| 项 | 值 |
| --- | --- |
| LAN | `10.10.10.1/24` |
| 用户名 / 密码 | `root` / `password`（请尽快改） |
| 主机名 | `OneCloud` |
| 时区 | `Asia/Tokyo` |
| Web 界面 | 官方 LuCI，简体中文 |
| 防火墙 | firewall4 / nftables |

玩客云只有一个 100M 网口。想当主路由用的话，WAN 需要插 USB 网卡或者手机 USB 共享网络，固件里已经预置了 `eth1` 的 DHCP WAN 口，插上就能用；不插也不影响 LAN。

## 包含

- 官方 LuCI + 简体中文
- Docker + Docker Compose + LuCI 管理界面
- HomeProxy（sing-box）
- zram 压缩交换分区、BBR、irqbalance、多核软中断分流
- USB 存储（ext4 / vfat / exfat / ntfs3 / f2fs）
- USB 网卡（RTL8152、AX88179、ASIX、SMSC95xx）、安卓 / iPhone USB 共享网络、4G 上网卡
- 常见 USB 无线网卡（MT7601U、MT76x0U、MT76x2U、RTL8XXXU、RT2800）
- WireGuard、UPnP、ttyd 网页终端

Docker 数据默认放在根分区，升级时会被覆盖。经常用 Docker 的话建议插一个 U 盘或硬盘，在 LuCI 的 Docker 设置里把数据目录指到挂载点上。

## 已知限制

- S805 是 32 位 ARM。Docker 只能跑 `linux/arm/v7` 的镜像，很多只发 `arm64` 的镜像用不了，这是 CPU 决定的。
- 1GB 内存 + 100M 网口。当旁路由 / 软路由 / 轻量 NAS 没问题，别指望跑满千兆。
- 没有内置无线，需要无线得插 USB 网卡。

## 自己编译

Actions → **Build OpenWrt OneCloud** → Run workflow，可以改 LAN IP。

本地编译（Linux x86_64，空闲磁盘 30G 以上）：

```bash
git clone --depth=1 -b openwrt-25.12 https://github.com/openwrt/openwrt.git
git clone https://github.com/neomikanagi/onecloud-openwrt.git custom
cp -a custom/target custom/files openwrt/
cd openwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../custom/config/onecloud.config .config
../custom/scripts/diy-part2.sh 10.10.10.1 true
./scripts/feeds install -a
make defconfig
make -j"$(nproc)"
```

## 致谢

- [hzyitc/u-boot-onecloud](https://github.com/hzyitc/u-boot-onecloud)、[hzyitc/AmlImg](https://github.com/hzyitc/AmlImg) — u-boot 和晶晨刷机包打包工具
- [lxhao61/OneCloud-OpenWrt](https://github.com/lxhao61/OneCloud-OpenWrt)、[shiyu1314/openwrt-onecloud](https://github.com/shiyu1314/openwrt-onecloud) — S805 设备树与镜像打包的参考
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy)

## 许可

GPL-2.0，同 OpenWrt。
