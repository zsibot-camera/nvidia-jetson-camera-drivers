# Thor 四目 ISX031 驱动包

Jetson AGX Thor Devkit 上的四目 ISX031 GMSL2 相机驱动交付包：

- 拓扑：1× MAX96712 解串器 + 4× MAX96717 串行器 + 4× ISX031
- 输出：四路 1920×1536 YUYV422，30 fps，可同时出流
- 同步：MAX96712 内部 FSYNC 30 Hz，经 GMSL2 backchannel 到串行器 MFP8；
  **不需要外部触发引脚**，串行器引脚保持默认
- 形式：**二进制驱动包**，不含源码、SDK、ROS2 节点、深度算法或标定文件

彩色流通过标准 V4L2 输出，客户可用 `v4l2-ctl`、GStreamer 或自研程序采集。

## 1. 包内容

| 路径 | 说明 |
|---|---|
| `driver/ko/nv_isx031.ko` | ISX031 sensor 驱动，Thor 源码树内重编 |
| `driver/ko/nv_max96717.ko` | MAX96717 serializer 驱动，Thor 源码树内重编 |
| `driver/dtb/tegra264-p4071-camera-isx031-quad-overlay.dtbo` | 四目设备树 overlay |
| `driver/install.sh` | 检查、备份、安装模块和 dtbo，写入 extlinux 启动项 |
| `driver/load_modules.sh` | 加载相机栈并检查四个 video 节点 |
| `driver/uninstall.sh` | 用安装备份回滚，或移除本包文件并清理启动项 |
| `preflight.sh` | 只读预检：平台、文件、vermagic、依赖、启动项、运行态 |
| `checksums.txt` | 本包文件 SHA256 |
| `docs/VERSION.md` | 版本、绑定关系、兼容与升级约束 |
| `docs/VERIFICATION.md` | 上板验证记录与证据 |

校验：

```sh
sha256sum -c checksums.txt
```

## 2. 系统要求

| 项目 | 要求 |
|---|---|
| 平台 | Jetson AGX Thor Devkit（P4071 + P3834-0008） |
| JetPack / L4T | JetPack 7.0 / L4T R39.2.1 |
| 内核 | `6.8.12-1021-tegra`（`uname -r` 必须一致） |
| 系统依赖 | 自带 `serdes_core`、`nv_max96712` 模块（本包不覆盖） |
| 工具 | `python3`、`depmod`、`modinfo`；建议 `v4l2-ctl`、`media-ctl` |

`.ko` 与内核版本绑定，dtbo 与 Thor Devkit 的 compatible 绑定。系统或内核升级后
必须用目标版本的 Thor L4T 源码树重新编译，不能直接复用本包。

## 3. 快速开始

### 3.1 预检

```sh
cd 四目isx031
./preflight.sh
./driver/install.sh --check
```

`preflight.sh` 只读；`install.sh --check` 也只检查平台、文件和依赖，不写系统。

### 3.2 安装

```sh
sudo ./driver/install.sh
```

脚本会：

1. 校验 aarch64、内核 `6.8.12-1021-tegra`、L4T R39.2.1、依赖模块和包文件；
2. 把原模块、dtbo、`extlinux.conf` 备份到 `driver/backup/<时间戳>/`，
   首次安装另存一份 `driver/backup/pre-install/`；
3. 安装 `nv_max96717.ko`、`nv_isx031.ko` 到
   `/lib/modules/6.8.12-1021-tegra/updates/`；
4. 安装 dtbo 到 `/boot/`；
5. 在 `/boot/extlinux/extlinux.conf` 的**第一个** `OVERLAYS` 行中移除
   OG02D10/OG02B10 相机 overlay，并写入 ISX031 overlay；
6. 执行 `depmod -a`。

如果启动项由外部工具管理，可用：

```sh
sudo ./driver/install.sh --no-extlinux
```

然后手工确保主启动项只有：

```
OVERLAYS /boot/tegra264-p4071-camera-isx031-quad-overlay.dtbo
```

### 3.3 重启并加载

```sh
sudo reboot
sudo ./driver/load_modules.sh
```

脚本按 `serdes_core → nv_max96712 → nv_max96717 → nv_isx031` 顺序加载，
等待最多 15 秒，确认至少有 4 个 `isx031` 视频节点，并打印格式。

### 3.4 验证四路出流

```sh
for d in /dev/video0 /dev/video1 /dev/video2 /dev/video3; do
    v4l2-ctl -d "$d" --get-fmt-video
done
```

并发采集各 30 帧：

```sh
for i in 0 1 2 3; do
    v4l2-ctl -d "/dev/video$i" \
        --set-fmt-video=width=1920,height=1536,pixelformat=YUYV \
        --stream-mmap --stream-count=30 --stream-to="/tmp/cam$i.yuv" &
done
wait
ls -l /tmp/cam*.yuv
```

每帧 5,898,240 字节；30 帧应为 176,947,200 字节。四路内容应互不相同。

GStreamer 单路预览/落盘示例：

```sh
gst-launch-1.0 v4l2src device=/dev/video0 num-buffers=30 \
    ! 'video/x-raw,format=YUY2,width=1920,height=1536,framerate=30/1' \
    ! fakesink
```

## 4. 节点映射

本机实测的物理链路映射：

| 链路 | 串行器代理地址 | 串行器 | VC | 实测 devnode |
|---|---|---|---|---|
| A（link0） | 0x11 | 0x41 | 0 | `/dev/video3` |
| B（link1） | 0x12 | 0x42 | 1 | `/dev/video2` |
| C（link2） | 0x13 | 0x43 | 2 | `/dev/video1` |
| D（link3） | 0x14 | 0x44 | 3 | `/dev/video0` |

`/dev/videoN` 编号由 Linux 分配，**不等于**设备树里的 A/B/C/D 顺序。换载板、
换接插件或改 overlay 后，以 `media-ctl -p` 或 dmesg 的
`VI capture setup ... vc=N` 为准，不要按节点编号假定相机字母。

## 5. FSYNC 同步

```text
MAX96712 内部 FSYNC 30 Hz（GPIO ID 8）
  └─ GMSL2 backchannel 广播到 4× MAX96717
       └─ 串行器 MFP8（GPIO_RX_GMSL，默认 RX ID 8）→ 模组 FSYNC
            └─ ISX031 在 SG_MODE=1（外部脉冲同步）下曝光
```

- 本板没有外部触发输入，同步完全由解串器内部产生。
- 串行器引脚保持模组默认配置，驱动不写 MFP8。
- 每次 stream-on 先启动解串器 FSYNC，再打开 CSI 输出门；启动失败直接报错，
  不让 VI 空等到超时。

dmesg 应出现：

```text
nv_max96712 12-006b: deser FSYNC period 33333000 ns (833325 xtal cycles), GPIO ID 8
nv_max96712 12-006b: deser FSYNC trigger on (1 user(s))
```

## 6. 回滚

```sh
sudo ./driver/uninstall.sh
sudo reboot
```

优先用 `driver/backup/pre-install/`（首次安装前快照）恢复原模块、dtbo 和
`extlinux.conf`；没有该快照时用最近一次 `driver/backup/<时间戳>/`；都没有时
删除本包安装的文件，并从 `OVERLAYS` 行移除 ISX031。

回滚脚本不会 `rmmod`/重载 `nv_max96712`、`nv_max9295d`，也不会操作 sysfs
unbind/rebind。

## 7. 故障排查

| 现象 | 处理 |
|---|---|
| `insmod`/`modprobe` 报 `Invalid module format` | 内核不是 `6.8.12-1021-tegra`，或系统已升级；用对应源码树重编 |
| 重启后没有 `/dev/video0..3` | 确认 extlinux 主启动项只有 ISX031 overlay；`dmesg | grep -Ei 'isx031|max96717|max96712'` |
| 只有部分节点 | 用 `i2cdetect` 和 MAX96712 link lock 位确认四条 GMSL 链路；检查模组/线束；不要重载 serdes 驱动 |
| 节点在但取流超时 | 检查是否有其他进程占用（`fuser /dev/videoN`）；看 dmesg 的 CSI/VI 错误 |
| 冷启动首次取流报 I2C `-121` | 重新发起取流；不要重载驱动。该现象在验证中只出现过一次，重试恢复 |
| 启动打印 `v4l2_subdev_has_pad_interdep` WARNING | 该平台 sensor 驱动的共性日志噪声，不影响出流 |
| 图像四路相同/错位 | 核对 `vc=N` 与物理链路映射，不要按 `/dev/videoN` 猜相机 |

## 8. 已知风险与禁令

- **禁止 `rmmod`/重载 `nv_max96712`、`nv_max9295d`，禁止 sysfs unbind/rebind。**
  Thor 上会导致内核卡死或板子重启。相机停帧时重启采集服务或整机。
- **不要把本包的 ISX031 overlay 与 OG02D10/OG02B10 overlay 同时启用。**
  它们都使用 MAX96712 `0x6b` 和 I2C12，会互相覆盖。一个启动周期只保留一种相机拓扑。
- 不要把 Orin NX 的 `.ko`/dtbo 拿到 Thor 复用；本包是在 Thor 源码树内重编的版本。
- 本包不含深度、标定、ROS2 或 SDK；不要套用 OG02D10 的标定/深度配置。
- 模组实际 sensor 地址、link 顺序或载板变化时，需要按实际硬件修改设备树并重编 dtbo，
  不要直接改已发布的二进制。

## 9. 验证状态

2026-11-18 在 Jetson AGX Thor Devkit、L4T R39.2.1、内核
`6.8.12-1021-tegra` 上完成：

- 四路 `/dev/video0..3` 均为 1920×1536 YUYV，每帧 5,898,240 字节；
- 每路 240 帧，29.99–30.00 fps；
- 四路并发 90 帧/路全部完成，四路图像内容互不相同；
- 两两时间戳差中位 4–11 µs、最大 42 µs（门限 1 ms）；
- 20 轮 × 4 路 × 4 帧压力测试 80/80 通过。

详见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。发布用 `.ko` 已剥离调试段和
内部构建路径，代码/数据/只读数据/模块信息段与上板验证版本逐字节一致。

版本与升级约束见 [docs/VERSION.md](docs/VERSION.md)。
