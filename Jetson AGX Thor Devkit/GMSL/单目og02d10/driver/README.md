# 四目 OG02D10 驱动安装说明

本目录是 Jetson AGX Thor Devkit 四目 OG02D10（MAX96712 + MAX96717F）的二进制
驱动包。安装内容和脚本行为与包根目录 [README](../README.md) 一致；本文件补充
安装细节和排障命令。

## 1. 文件

```text
driver/
├── ko/
│   ├── serdes_core.ko
│   ├── nv_max96712.ko
│   ├── nv_max96717.ko
│   └── nv_og02d10_single.ko
├── dtb/
│   └── tegra264-p4071-camera-og02d10-quad-overlay.dtbo
├── install.sh
├── load_modules.sh
├── uninstall.sh
└── backup/              # 运行 install.sh 后生成，已加入 .gitignore
```

与 OG02B10 / ISX031 包不同，本包**自带并安装** `serdes_core` 和 `nv_max96712`：
本版本的 `serdes_ctx` 新增了 `stream_id`，`serdes_core` 与三个相机模块做符号
CRC 绑定，四个模块必须同批安装，不能只换其中一个。

## 2. 环境

| 项目 | 要求 |
|---|---|
| 平台 | Jetson AGX Thor Devkit（P4071 + P3834-0008） |
| L4T | R39.2.1（JetPack 7.2.1） |
| 内核 | `6.8.12-1021-tegra` |
| 架构 | aarch64 |
| 工具 | `python3`、`depmod`、`modinfo`、`v4l2-ctl`（建议） |

## 3. 安装

```sh
sudo ./install.sh --check   # 只检查，不写系统
sudo ./install.sh           # 安装四个模块、dtbo，并更新 extlinux
sudo reboot
sudo ./load_modules.sh      # 加载并确认 4 个节点
```

安装路径（与板上既有布局一致，避免同一模块出现两份）：

```text
/lib/modules/6.8.12-1021-tegra/updates/drivers/media/i2c/serdes_core.ko
/lib/modules/6.8.12-1021-tegra/updates/drivers/media/i2c/nv_max96712.ko
/lib/modules/6.8.12-1021-tegra/updates/nv_max96717.ko
/lib/modules/6.8.12-1021-tegra/updates/nv_og02d10_single.ko
/boot/tegra264-p4071-camera-og02d10-quad-overlay.dtbo
```

备份路径：

```text
driver/backup/<YYYYmmdd_HHMMSS>/   # 每次安装前的快照（审计/单次回滚）
driver/backup/pre-install/         # 首次安装前快照；uninstall.sh 优先使用
```

### 3.1 启动项修改规则

`install.sh` 默认修改 `/boot/extlinux/extlinux.conf` 的**第一个** `OVERLAYS` 行：

- 移除 `tegra264-p4071-camera-isx031-quad-overlay.dtbo`；
- 移除 `tegra264-p4071-camera-og02d10-dual-overlay.dtbo`；
- 移除 `tegra264-p4071-camera-og02b10-quad-overlay.dtbo`；
- 移除旧开发版本的 `tegra264-p4071-camera-og02d10-quad-max9296a-overlay.dtbo`（如有）；
- 保证本包 overlay 只出现一次；
- 没有 `OVERLAYS` 行时，在 `FDT` 行后插入。

只改第一个 `OVERLAYS` 行，是为了保留其他启动项（例如备份内核）的原配置。
如果存在多个 `OVERLAYS` 行，脚本会打印警告。若启动项由外部工具管理：

```sh
sudo ./install.sh --no-extlinux
```

然后手工设置主启动项为：

```
OVERLAYS /boot/tegra264-p4071-camera-og02d10-quad-overlay.dtbo
```

### 3.2 跳过版本检查

`--force` 会跳过内核/L4T 检查，但**不会**改变模块的 vermagic 绑定。内核不一致时
模块仍然无法加载，只建议在明确知道风险时用于排查。

## 4. 加载与验证

```sh
sudo ./load_modules.sh
```

脚本：

1. 按 `serdes_core → nv_max96712 → nv_max96717 → nv_og02d10_single` 顺序
   加载缺失模块；
2. 检查 dmesg 中是否有 `disagrees about version of symbol serdes_`；
3. 等待最多 15 秒；
4. 统计名称含 `og02d10sgl` 的视频节点，少于 4 个时打印 dmesg 并失败；
5. 用 `v4l2-ctl --get-fmt-video` 打印节点格式。

手工检查：

```sh
lsmod | grep -E 'serdes_core|nv_max96712|nv_max96717|nv_og02d10_single'
for d in /dev/video0 /dev/video1 /dev/video2 /dev/video3; do
    v4l2-ctl -d "$d" --get-fmt-video
done
```

期望每路 `1920x1280`、`YUYV`、`Bytes per Line 3840`、`Size Image 4915200`。
四路并发采集示例见包根 README。

## 5. 节点映射

| 链路 | 代理地址 | 串行器运行地址 | VC | 实测 devnode |
|---|---|---|---|---|
| A | 0x11 | 0x43 | 0 | `/dev/video2` |
| B | 0x12 | 0x44 | 1 | `/dev/video1` |
| C | 0x13 | 0x45 | 2 | `/dev/video0` |
| D | 0x14 | 0x46 | 3 | `/dev/video3` |

传感器真实地址为 `0x20`，四颗共用；驱动通过串行器地址翻译使用 `0x11..0x14`
代理。串行器上电地址为 `0x42`，probe 后重映射到 `0x43..0x46`；本次验证的启动
周期中模块未断电，dmesg 为 `already at 0x4x, skip remap`，冷启动时会出现
`set_address` 重映射日志。

映射随载板、线束和 overlay 变化。需要固定映射时，以 `media-ctl -p` 或 dmesg 的
`vc=N` 为准。

## 6. 回滚

```sh
sudo ./uninstall.sh
sudo reboot
```

脚本优先恢复 `backup/pre-install/`（首次安装前快照），没有时恢复最近一次
`backup/<时间戳>/`，都没有时删除本包文件并从 `OVERLAYS` 行移除本包 overlay。

本包替换了 `serdes_core`、`nv_max96712`、`nv_max96717`，回滚会一并恢复旧版本；
重启后依赖旧 ABI 的相机包（ISX031 / OG02B10 / 双目 OG02D10）重新可用。

不会卸载或重载 `nv_max96712`、`nv_max9295d`。

## 7. 故障排查

### 7.1 模块无法加载

```sh
uname -r
modinfo ./ko/nv_og02d10_single.ko | grep -E 'vermagic|depends'
dmesg | grep -i "disagrees about version"
```

- 内核不是 `6.8.12-1021-tegra`：用目标版本的 Thor L4T 源码树重编。
- `disagrees about version of symbol serdes_`：四个模块不是同批构建；用本包
  `install.sh` 四件一起重装并重启。
- `Invalid module format`：不要用 `--force` 硬装，vermagic 不匹配无法解决。

### 7.2 没有节点或少于 4 路

```sh
sudo ./load_modules.sh
dmesg | grep -Ei 'og02d10|max96717|max96712|nvcsi|vi capture' | tail -n 80
media-ctl -p
```

检查：

- `extlinux.conf` 主启动项只有本包 overlay；
- 四条 GMSL link 是否锁定（dmesg 的 `link 0x1/0x2/0x4/0x8 locked`）；
- 模组供电、同轴线、接插件是否可靠；
- 是否有其他进程占用节点：`fuser /dev/video0 /dev/video1 /dev/video2 /dev/video3`。

**不要**通过 `rmmod`/重载 `nv_max96712`、`nv_max9295d` 或 sysfs unbind/rebind
来排查；Thor 上可能导致内核卡死或重启。

### 7.3 `v4l2-ctl` 报 `File name too long`

Tegra VI 的 `VIDIOC_QUERYCAP` 把节点名拷进 32 字节的 `v4l2_capability.card`。
默认 subdev 名 `og02d10_single 12-0013` 会超长并返回 `-ENAMETOOLONG`。本包驱动
使用短名 `og02d10sgl`，节点名为 `vi-output, og02d10sgl 12-00xx`（30 字节）。
若看到长名节点，说明装错了驱动二进制。

### 7.4 串行器 probe 日志 `already at 0x4x, skip remap`

说明串行器已处于运行地址（模块未断电），属正常。冷启动时若串行器回到 `0x42`，
驱动会执行 `set_address` 重映射。以 dmesg 为准。

### 7.5 `i2cdetect` 看不到 0x6b/0x43..0x46

驱动绑定后，`i2ctransfer` 访问 `0x6b` 会返回 `Device or resource busy`，
`i2cdetect -y 12` 也可能不直接显示这些地址。以 dmesg 的
`nv_max96712 12-006b`、`max96717 12-0043..0046` 和 link lock 为准，不要据此
判定链路失败。

### 7.6 画面全灰

本包验收未装镜头，漫射光下输出均匀灰底属正常。数据流是否正常以节点、格式、
帧率、四路首帧 SHA-256 互异判断；图像内容不作为本阶段判据。

### 7.7 四路不同步

OG02D10 为自由运行模组，本包不订阅 MAX96712 FSYNC，四路曝光独立，**不保证
跨路同步**。dmesg 只有 `frame sync from the internal generator, 25000000 Hz`，
没有 `deser FSYNC period` / `trigger on` 属预期。需要同步的应用应改用支持外部
触发且由 FSYNC 驱动的模组/固件。

### 7.8 板端 `nvcompositor` 崩溃

Thor 上 `nvcompositor` 合成多路高分辨率视频流会出现 SIGSEGV（平台已知问题）。
不要把 `nvcompositor` 当作稳定路径；建议单路预览，或使用四路独立
`nvv4l2h264enc` 硬编后在主机侧合成。

## 8. 兼容性

| 项目 | 值 |
|---|---|
| 内核 | 6.8.12-1021-tegra（vermagic 含 `SMP preempt mod_unload modversions aarch64`） |
| 模块依赖 | `serdes_core`：无；`nv_max96712`、`nv_max96717`：`serdes_core`；`nv_og02d10_single`：`v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode` |
| dtbo compatible | `nvidia,p4071-0000+p3834-0008`、`nvidia,p4071-0008+p3834-0008` |
| 冲突 overlay | ISX031 quad、双目 OG02D10、四目 OG02B10（同一 MAX96712/I2C12） |
| 跨包兼容 | 本包 `serdes_core` 为新 ABI；与其他相机包的旧构建 `.ko` 混用会报符号 CRC 不一致 |

内核、L4T 或载板变更后必须重新编译并重新验证，不能跨版本复用二进制。
