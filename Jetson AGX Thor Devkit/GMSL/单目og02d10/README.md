# Thor 四目 OG02D10 驱动包（MAX96712 + MAX96717F）

Jetson AGX Thor Devkit 上的四目 OG02D10 GMSL2 相机驱动交付包：

- 拓扑：1× MAX96712 解串器 + 4× MAX96717F 串行器 + 4× OG02D10 单目模组
- 输出：四路 1920×1280 YUYV422，30 fps，可同时出流
- 出流模式：OG02D10 模组自由运行（free-run），不从 GMSL backchannel 取触发；
  overlay 保留 MAX96712 内部 FSYNC 属性但不会被传感器订阅，**不需要外部触发引脚**
- 形式：**二进制驱动包**，不含源码、SDK、ROS2 节点、深度算法或标定文件

彩色流通过标准 V4L2 输出，客户可用 `v4l2-ctl`、GStreamer 或自研程序采集。

> 本包与仓库中的“双目 OG02D10”是两套独立驱动。双目包使用
> `ovti,og02d10`（MAX96712 + MAX9295D + FH833X）；本包使用
> `nvidia,og02d10-single`，只驱动 MAX96712 + MAX96717F 拓扑，不覆盖、
> 不影响旧双目实现。
>
> 交付目录按仓库槽位命名为 `单目og02d10`；本包实际验证的是四路 OG02D10
> 同时出流。

## 1. 包内容

| 路径 | 说明 |
|---|---|
| `driver/ko/serdes_core.ko` | SerDes OPS 公共层（新增 `stream_id` 与 `write_regs` 表操作；与相机模块符号 CRC 绑定） |
| `driver/ko/nv_max96712.ko` | MAX96712 解串器驱动（与 OG02B10 四目同一份源码，随新 serdes_core 重编） |
| `driver/ko/nv_max96717.ko` | MAX96717/96717F 串行器驱动（新增 TX_STR_SEL、lane 配置位域修正、寄存器表操作） |
| `driver/ko/nv_og02d10_single.ko` | OG02D10 单目 endpoint 驱动（`nvidia,og02d10-single`） |
| `driver/dtb/tegra264-p4071-camera-og02d10-quad-overlay.dtbo` | 四目设备树 overlay |
| `driver/install.sh` | 检查、备份、安装模块和 dtbo，写入 extlinux 启动项 |
| `driver/load_modules.sh` | 加载相机栈并检查四个 video 节点 |
| `driver/uninstall.sh` | 用安装备份回滚，或移除本包文件并清理启动项 |
| `preflight.sh` | 只读预检：平台、文件、vermagic、启动项、运行态 |
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
| JetPack / L4T | JetPack 7.2.1 / L4T R39.2.1 |
| 内核 | `6.8.12-1021-tegra`（`uname -r` 必须一致） |
| 系统依赖 | `nvidia-l4t-camera` 提供的 `tegra-camera` 等基础模块 |
| 工具 | `python3`、`depmod`、`modinfo`；建议 `v4l2-ctl`、`media-ctl` |

本包**自带** `serdes_core`、`nv_max96712`、`nv_max96717`、`nv_og02d10_single`
四个模块，四件必须同批安装：`serdes_ctx` 结构在本版本新增了 `stream_id`，
其余三个模块与该结构做符号 CRC 绑定，不能与旧构建混用。

`.ko` 与内核版本绑定，dtbo 与 Thor Devkit 的 compatible 绑定。系统或内核升级后
必须用目标版本的 Thor L4T 源码树重新编译，不能直接复用本包。

## 3. 快速开始

### 3.1 预检

```sh
cd 单目og02d10
./preflight.sh
./driver/install.sh --check
```

`preflight.sh` 只读；`install.sh --check` 也只检查平台、文件和依赖，不写系统。

### 3.2 安装

```sh
sudo ./driver/install.sh
```

脚本会：

1. 校验 aarch64、内核 `6.8.12-1021-tegra`、L4T R39.2.1 和包文件；
2. 把原模块、dtbo、`extlinux.conf` 备份到 `driver/backup/<时间戳>/`，
   首次安装另存一份 `driver/backup/pre-install/`；
3. 按板上既有布局安装模块，避免同一模块出现两份：
   - `serdes_core.ko`、`nv_max96712.ko` →
     `/lib/modules/6.8.12-1021-tegra/updates/drivers/media/i2c/`
   - `nv_max96717.ko`、`nv_og02d10_single.ko` →
     `/lib/modules/6.8.12-1021-tegra/updates/`
4. 安装 dtbo 到 `/boot/`；
5. 在 `/boot/extlinux/extlinux.conf` 的**第一个** `OVERLAYS` 行中移除
   ISX031 / 双目 OG02D10 / 四目 OG02B10 等相机 overlay，并写入本包 overlay；
6. 执行 `depmod -a`。

如果启动项由外部工具管理，可用：

```sh
sudo ./driver/install.sh --no-extlinux
```

然后手工确保主启动项只有：

```
OVERLAYS /boot/tegra264-p4071-camera-og02d10-quad-overlay.dtbo
```

### 3.3 重启并加载

```sh
sudo reboot
sudo ./driver/load_modules.sh
```

脚本按 `serdes_core → nv_max96712 → nv_max96717 → nv_og02d10_single` 顺序加载，
等待最多 15 秒，确认至少有 4 个 `og02d10sgl` 视频节点，并打印格式。

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
        --set-fmt-video=width=1920,height=1280,pixelformat=YUYV \
        --stream-mmap --stream-count=30 --stream-to="/tmp/cam$i.yuv" &
done
wait
ls -l /tmp/cam*.yuv
```

每帧 1920×1280×2 = 4,915,200 字节；30 帧应为 147,456,000 字节。
四路内容应互不相同。

GStreamer 单路预览/落盘示例：

```sh
gst-launch-1.0 v4l2src device=/dev/video0 num-buffers=30 \
    ! 'video/x-raw,format=YUY2,width=1920,height=1280,framerate=30/1' \
    ! fakesink
```

### 3.5 节点名与 `v4l2-ctl` 的 32 字节限制

Tegra VI 的 `VIDIOC_QUERYCAP` 会把视频节点名拷进 32 字节的
`v4l2_capability.card`。默认 subdev 名 `og02d10_single 12-0013` 生成的节点名
超长，`v4l2-ctl` 打开时会报 `Failed to open ...: File name too long`。
本驱动在 probe 中使用短名 `og02d10sgl`，节点名形如：

```text
vi-output, og02d10sgl 12-0013
```

这是预期行为，不是故障；不要用默认长名构建替换本包驱动。

## 4. 节点映射

本机实测的物理链路映射：

| 链路 | 串行器代理地址 | 串行器运行地址 | VC | 实测 devnode |
|---|---|---|---|---|
| A（link0） | 0x11 | 0x43 | 0 | `/dev/video2`（12-0011） |
| B（link1） | 0x12 | 0x44 | 1 | `/dev/video1`（12-0012） |
| C（link2） | 0x13 | 0x45 | 2 | `/dev/video0`（12-0013） |
| D（link3） | 0x14 | 0x46 | 3 | `/dev/video3`（12-0014） |

OG02D10 的真实 sensor 地址为 `0x20`，四颗共用；驱动通过串行器地址翻译使用
`0x11..0x14` 代理。串行器上电地址为 `0x42`；本次验证的启动周期中模块未断电，
串行器已处于运行地址，dmesg 为 `already at 0x4x, skip remap`。冷启动/模组重新
上电后若回到 `0x42`，驱动会执行地址重映射，以 dmesg 为准。

`/dev/videoN` 编号由 Linux 分配，**不等于**设备树里的 A/B/C/D 顺序。换载板、
换接插件或改 overlay 后，以 `media-ctl -p` 或 dmesg 的
`VI capture setup ... vc=N` 为准，不要按节点编号假定相机字母。

## 5. 出流模式与模组上电时序

```text
MAX96712 内部 FSYNC 发生器（25 MHz xtal，已在驱动中初始化）
  └─ 本包 OG02D10 驱动不订阅 FSYNC trigger
       └─ 4× OG02D10 自由运行 30 fps，经 MAX96717F 2-lane MIPI
            └─ MAX96712 每 link 独立 pipe 0..3，汇成 4-lane CSI（VC0..3）
```

- OG02D10 模组自带 30 fps 时序，本包不写 sensor 寄存器，也不请求外部触发。
- 因此 dmesg 只有 `frame sync from the internal generator, 25000000 Hz`，
  不出现 `deser FSYNC period ...` / `trigger on`，也没有 MFP7
  `GPIO_RX_GMSL` 触发配置。这是预期行为。
- 四路是独立自由运行，**未做跨路曝光同步**。需要硬件同步时，应改用支持外部
  触发并由 FSYNC 驱动的模组/固件，本包不提供该能力。
- 模组上电的 MFP5/MFP7/MFP8/MFP0 时序按厂商 ini
  `max9296_96717f_OG02D10_YUV_1920x1280_30fps_2lane.ini` 在驱动中逐行写入
  串行器；ini 中 `0xfff8,0x90` 之后的 MAX9296A EVB 配置块不适用于本板，
  驱动未使用。

## 6. 上板验证摘要（2026-11-19）

验证板：`NVIDIA Jetson AGX Thor Developer Kit`，L4T R39.2.1，
内核 `6.8.12-1021-tegra`。

| 项目 | 实测结果 |
|---|---|
| 节点 | `/dev/video0..3` = `vi-output, og02d10sgl 12-0013/0012/0011/0014`（VC2/VC1/VC0/VC3） |
| 格式 | 四路均 1920×1280 YUYV，Bytes per Line 3840，Size Image 4,915,200 B |
| GMSL link | 四路全部锁定：`link 0x4/0x2/0x1/0x8 locked, lock time 0ms` |
| 串行器 | 运行地址 0x43..0x46；本次启动周期 `already at 0x4x, skip remap` |
| 帧率 | 四路并发各 300 帧，10.101 s 完成 = 29.70 fps/路 |
| 四路并发 | 每路首帧 4,915,200 B，四路 SHA-256 互不相同 |
| 图像 | 未装镜头；四路 Y 均值 110.2–126.4、std 1.9–4.4，内容不作判据 |
| 错误 | 取流期间无 CSI/VI 错误 |

完整证据见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。

## 7. 回滚

```sh
sudo ./driver/uninstall.sh
sudo reboot
```

优先用 `driver/backup/pre-install/`（首次安装前快照）恢复原模块、dtbo 和
`extlinux.conf`；没有该快照时用最近一次 `driver/backup/<时间戳>/`；都没有时
删除本包安装的文件，并从 `OVERLAYS` 行移除本包 overlay。

本包会替换 `serdes_core`、`nv_max96712`、`nv_max96717`，回滚脚本会一并恢复
安装前的旧版本，使仓库中依赖旧 `serdes_core` 的相机包（ISX031、OG02B10、
双目 OG02D10）在重启后重新可用。

回滚脚本不会 `rmmod`/重载 `nv_max96712`、`nv_max9295d`，也不会操作 sysfs
unbind/rebind。

## 8. 故障排查

| 现象 | 处理 |
|---|---|
| `modprobe` 报 `disagrees about version of symbol serdes_` | `serdes_core` 与相机模块不是同批构建；用本包四件一起重装后重启 |
| `insmod`/`modprobe` 报 `Invalid module format` | 内核不是 `6.8.12-1021-tegra`，或系统已升级；用对应源码树重编 |
| 重启后没有 `/dev/video0..3` | 确认 extlinux 主启动项只有本包 overlay；`dmesg \| grep -Ei 'og02d10\|max96717\|max96712'` |
| 只有部分节点 | 用 dmesg 的 link lock 位确认四条 GMSL 链路；检查模组/线束；不要重载 serdes 驱动 |
| 节点在但取流超时 | 检查是否有其他进程占用（`fuser /dev/videoN`）；看 dmesg 的 CSI/VI 错误 |
| `v4l2-ctl` 报 `File name too long` | 节点名超过 32 字节；确认使用的是本包 `og02d10sgl` 短名驱动 |
| `already at 0x4x, skip remap` | 串行器已处于运行地址，正常；地址以 dmesg 为准 |
| `i2cdetect` 看不到 0x6b/0x43..0x46 | 驱动绑定后属正常；`i2ctransfer` 访问 0x6b 报 `Device or resource busy` 也正常，以 dmesg 为准 |
| 画面全灰/无内容 | 本包验收未装镜头，漫射光下均匀灰底属正常；先以节点、格式、帧率、四路哈希互异判断数据流 |
| 四路同时取流时帧率不足 | 确认使用 `--stream-mmap` 且没有其他进程占用；四路 1920×1280@30 约 4.7 Gbps |
| 板端 `nvcompositor` SIGSEGV | Thor 上合成多路高分辨率视频流的已知平台问题；用四路独立硬编 + 主机侧合成，或单路预览 |

**禁止** `rmmod`/重载 `nv_max96712`、`nv_max9295d`，禁止 sysfs unbind/rebind；
Thor 上可能导致内核卡死或板子重启。相机停帧时重启采集服务或整机。

## 9. 已知风险与禁令

- **不要把本包 overlay 与 ISX031 / 双目 OG02D10 / OG02B10 overlay 同时启用。**
  它们都使用 MAX96712 `0x6b` 和 I2C12，会互相覆盖。一个启动周期只保留一种相机拓扑。
- **本包四个模块必须同批安装。** 新 `serdes_core` 的 ABI 与仓库中其他相机包的
  旧构建 `.ko` 不兼容；混用会报符号 CRC 不一致。切换相机拓扑时，先用本包
  `uninstall.sh` 回滚并重启，再安装对应包。
- 不要把 Orin NX 的 `.ko`/dtbo 拿到 Thor 复用；本包是在 Thor 源码树内重编的版本。
- 本包不含深度、标定、ROS2 或 SDK；不要套用双目 OG02D10 的标定/深度配置。
- 四路自由运行，不保证跨路曝光同步；需要同步相机的应用不要基于本包。
- 模组实际 sensor 地址、link 顺序或载板变化时，需要按实际硬件修改设备树并重编
  dtbo，不要直接改已发布的二进制。
- 发布用 `.ko` 已剥离调试段和内部构建路径；代码/数据/只读数据/模块信息段与
  上板验证版本逐字节一致。

## 10. 验证状态

2026-11-19 在 Jetson AGX Thor Devkit、L4T R39.2.1、内核
`6.8.12-1021-tegra` 上完成：

- 四路 `/dev/video0..3` 均为 1920×1280 YUYV，每帧 4,915,200 字节；
- 四路并发各 300 帧，10.101 s 完成，29.70 fps/路；
- 四路首帧 SHA-256 互不相同，Y 均值 110.2–126.4；
- 四条 GMSL link 全部锁定，串行器位于 0x43..0x46；
- 取流期间无 CSI/VI 错误。

版本与升级约束见 [docs/VERSION.md](docs/VERSION.md)。
