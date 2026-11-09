# 双 OG02D10 (GMSL2) 相机驱动包 — Jetson AGX Thor

本目录是**二进制驱动包**（不含源码），用于在 Jetson AGX Thor 上启用双 OG02D10
全局快门相机（MAX96712 解串 + MAX9295D 串行，GMSL2）。

## 包内容

```
driver/
├── ko/
│   ├── serdes_core.ko        # SerDes 公共核心（31KB）
│   ├── nv_max9295d.ko        # MAX9295D 串行器驱动
│   ├── nv_max96712.ko        # MAX96712 解串器驱动（含内部 FSYNC）
│   └── nv_og02d10.ko         # OG02D10 ISP endpoint 驱动
├── dtb/
│   └── tegra264-p4071-camera-og02d10-dual-overlay.dtbo
├── install.sh                # 安装（校验版本 → 拷贝 → depmod → 写 OVERLAYS）
├── load_modules.sh           # 加载模块并检查 /dev/video*
├── uninstall.sh              # 卸载/回滚
└── README.md
```

## 环境要求（必须严格匹配）

| 项 | 要求 |
|---|---|
| 平台 | Jetson AGX Thor Devkit（P4071 + P3834-0008） |
| JetPack | 7.0 |
| L4T | **R39.2.1**（`nvidia-l4t-core` 39.2.1） |
| 内核 | **6.8.12-1021-tegra**（`.ko` 的 vermagic 锁死） |
| 启动方式 | 标准 L4T extlinux（`/boot/extlinux/extlinux.conf`） |

> `.ko` 使用 `modversions`，内核小版本变化即无法加载；`dtbo` 的 compatible
> 为 `nvidia,p4071-0000+p3834-0008`。升级 JetPack 后必须使用对应版本的新驱动包。

## 安装

```bash
# 1. 先把整个 driver/ 目录拷到 Thor 上，例如 /home/nvidia/driver
cd /home/nvidia/driver

# 2. 预检查（不写入任何文件）
sudo ./install.sh --check

# 3. 安装
sudo ./install.sh

# 4. 重启（设备树 overlay 只在启动时生效）
sudo reboot
```

重启后验证：

```bash
sudo ./load_modules.sh
```

期望输出：

```
/dev/video0: vi-output, og02d10 12-0030
/dev/video1: vi-output, og02d10 12-0020
```

设备映射（与 `depth_sdk_vpi.conf` 的 `camera.uri` 一致）：

| 节点 | I2C 地址 | VC | 说明 |
|---|---|---|---|
| `/dev/video0` | 0x30 | VC1 | 相机 B |
| `/dev/video1` | 0x20 | VC0 | 相机 A |

> 系统 udev 会按设备树 compatible 自动加载这些模块；`load_modules.sh` 只用于
> 手动确认或排障，正常情况下不需要每次开机手动执行。

## 快速验证出流

```bash
# 查看支持的格式（应看到 1920x1280 YUYV）
v4l2-ctl -d /dev/video0 --list-formats-ext

# 抓 30 帧确认能出图（需要 gstreamer）
gst-launch-1.0 v4l2src device=/dev/video0 num-buffers=30 ! \
  'video/x-raw,width=1920,height=1280,format=YUY2,framerate=30/1' ! fakesink
```

如果使用深度 SDK，请改用 SDK 包里的 `start_depth_ros.sh`（它会独占相机）。

## 回滚

```bash
sudo ./uninstall.sh
sudo reboot
```

`install.sh` 会把被覆盖的原文件备份到 `driver/backup/<时间戳>/`
（原 `.ko`、`dtbo`、`extlinux.conf`）。`uninstall.sh` 默认从最近一次备份恢复；
若没有备份，则删除安装的文件并从 `extlinux.conf` 的 `OVERLAYS` 行移除条目。

## 故障排查

| 现象 | 排查 |
|---|---|
| `insmod`/`modprobe` 报 `Invalid module format` | 内核/L4T 版本不匹配，见上表 |
| 重启后没有 `/dev/video0` | `dmesg | grep -iE "og02d10|max96712|max9295"`；确认 `extlinux.conf` 有 `OVERLAYS` 行且指向本 dtbo |
| 模块加载了但无 video 节点 | 检查硬件供电（载板 12V）与 GMSL2 线束；`i2cdetect -y -r 12` 应看到 0x20/0x30/0x40/0x6b |
| 出流报 `No space left`/超时 | 确认没有其他进程占用 `/dev/video0/1`（`fuser -v /dev/video0`） |
| 深度 SDK 启动报 `VPI set call` 失败 | 确认 `vpi4-dev`/`libnvvpi4` 已安装（JetPack 7 自带），且驱动节点为 video0/1 |

## 兼容性说明

- 内核镜像（`/boot/Image`）与 `tegra-camera.ko` 使用系统自带版本，**本包不修改**。
- 只替换本目录中列出的 4 个 out-of-tree 模块与 1 个设备树 overlay。
- 若客户自行升级 L4T，需要重新提供/编译对应版本的驱动包。
