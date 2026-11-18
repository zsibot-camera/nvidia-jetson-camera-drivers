# 四目 ISX031 驱动安装说明

本目录是 Jetson AGX Thor Devkit 四目 ISX031 的二进制驱动包。安装内容和脚本行为
与包根目录 [README](../README.md) 一致；本文件补充安装细节和排障命令。

## 1. 文件

```text
driver/
├── ko/
│   ├── nv_isx031.ko
│   └── nv_max96717.ko
├── dtb/
│   └── tegra264-p4071-camera-isx031-quad-overlay.dtbo
├── install.sh
├── load_modules.sh
├── uninstall.sh
└── backup/              # 运行 install.sh 后生成，已加入 .gitignore
```

`install.sh` 只安装上述两个模块和 dtbo。`serdes_core`、`nv_max96712` 使用系统
自带版本，本包不覆盖、不卸载。

## 2. 环境

| 项目 | 要求 |
|---|---|
| 平台 | Jetson AGX Thor Devkit（P4071 + P3834-0008） |
| L4T | R39.2.1（JetPack 7.0） |
| 内核 | `6.8.12-1021-tegra` |
| 架构 | aarch64 |
| 工具 | `python3`、`depmod`、`modinfo`、`v4l2-ctl`（建议） |

## 3. 安装

```sh
sudo ./install.sh --check   # 只检查，不写系统
sudo ./install.sh           # 安装模块、dtbo，并更新 extlinux
sudo reboot
sudo ./load_modules.sh      # 加载并确认 4 个节点
```

安装路径：

```text
/lib/modules/6.8.12-1021-tegra/updates/nv_max96717.ko
/lib/modules/6.8.12-1021-tegra/updates/nv_isx031.ko
/boot/tegra264-p4071-camera-isx031-quad-overlay.dtbo
```

备份路径：

```text
driver/backup/<YYYYmmdd_HHMMSS>/   # 每次安装前的快照（审计/单次回滚）
driver/backup/pre-install/         # 首次安装前快照；uninstall.sh 优先使用
```

### 3.1 启动项修改规则

`install.sh` 默认修改 `/boot/extlinux/extlinux.conf` 的**第一个** `OVERLAYS` 行：

- 移除 `tegra264-p4071-camera-og02d10-dual-overlay.dtbo`；
- 移除 `tegra264-p4071-camera-og02b10-quad-overlay.dtbo`；
- 保证 ISX031 overlay 只出现一次；
- 没有 `OVERLAYS` 行时，在 `FDT` 行后插入。

只改第一个 `OVERLAYS` 行，是为了保留其他启动项（例如备份内核）的原配置。
如果存在多个 `OVERLAYS` 行，脚本会打印警告。若启动项由外部工具管理：

```sh
sudo ./install.sh --no-extlinux
```

然后手工设置主启动项为：

```
OVERLAYS /boot/tegra264-p4071-camera-isx031-quad-overlay.dtbo
```

### 3.2 跳过版本检查

`--force` 会跳过内核/L4T 检查，但**不会**改变模块的 vermagic 绑定。内核不一致时
模块仍然无法加载，只建议在明确知道风险时用于排查。

## 4. 加载与验证

```sh
sudo ./load_modules.sh
```

脚本：

1. 按 `serdes_core → nv_max96712 → nv_max96717 → nv_isx031` 顺序加载缺失模块；
2. 等待最多 15 秒；
3. 统计名称含 `isx031` 的视频节点，少于 4 个时打印 dmesg 并失败；
4. 用 `v4l2-ctl --get-fmt-video` 打印节点格式。

手工检查：

```sh
lsmod | grep -E 'serdes_core|nv_max96712|nv_max96717|nv_isx031'
for d in /dev/video0 /dev/video1 /dev/video2 /dev/video3; do
    v4l2-ctl -d "$d" --get-fmt-video
done
```

期望每路 `1920x1536`、`YUYV`。四路并发采集示例见包根 README。

## 5. 节点映射

| 链路 | 代理地址 | 串行器 | VC | 实测 devnode |
|---|---|---|---|---|
| A | 0x11 | 0x41 | 0 | `/dev/video3` |
| B | 0x12 | 0x42 | 1 | `/dev/video2` |
| C | 0x13 | 0x43 | 2 | `/dev/video1` |
| D | 0x14 | 0x44 | 3 | `/dev/video0` |

映射随载板、线束和 overlay 变化。需要固定映射时，以 `media-ctl -p` 或 dmesg 的
`vc=N` 为准。

## 6. 回滚

```sh
sudo ./uninstall.sh
sudo reboot
```

脚本优先恢复 `backup/pre-install/`（首次安装前快照），没有时恢复最近一次
`backup/<时间戳>/`，都没有时删除本包文件并从 `OVERLAYS` 行移除 ISX031。
不会卸载或重载 `nv_max96712`、`nv_max9295d`。

## 7. 故障排查

### 7.1 模块无法加载

```sh
uname -r
modinfo ./ko/nv_isx031.ko | grep -E 'vermagic|depends'
```

- 内核不是 `6.8.12-1021-tegra`：用目标版本的 Thor L4T 源码树重编。
- `depends` 含 `serdes_core`：确认 `modinfo serdes_core` 可用。
- `Invalid module format`：不要用 `--force` 硬装，vermagic 不匹配无法解决。

### 7.2 没有节点或少于 4 路

```sh
sudo ./load_modules.sh
dmesg | grep -Ei 'isx031|max96717|max96712|nvcsi|vi capture' | tail -n 80
media-ctl -p
```

检查：

- `extlinux.conf` 主启动项只有 ISX031 overlay；
- 四条 GMSL link 是否锁定（MAX96712 `0x001a/0x000a/0x000b/0x000c` bit3）；
- 模组供电、同轴线、接插件是否可靠；
- 是否有其他进程占用节点：`fuser /dev/video0 /dev/video1 /dev/video2 /dev/video3`。

**不要**通过 `rmmod`/重载 `nv_max96712`、`nv_max9295d` 或 sysfs unbind/rebind
来排查；Thor 上可能导致内核卡死或重启。

### 7.3 冷启动 I2C `-121`

验证中遇到过一次冷启动后首次取流瞬时失败：

```text
sensor i2c write ... failed: -121
```

同一启动内重试取流恢复，之后 100+ 次取流未复现。遇到时重新发起取流，不要重载驱动。

### 7.4 启动 WARNING

`v4l2_subdev_has_pad_interdep`（`v4l2-subdev.c`）每次启动可能打印一次，发生在
STREAMON 期间，不影响取流，属于该平台 sensor 驱动的共性日志噪声。

## 8. 兼容性

| 项目 | 值 |
|---|---|
| 内核 | 6.8.12-1021-tegra（vermagic 含 `SMP preempt mod_unload modversions aarch64`） |
| 模块依赖 | `nv_isx031`：`v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode`；`nv_max96717`：`serdes_core` |
| dtbo compatible | `nvidia,p4071-0000+p3834-0008`、`nvidia,p4071-0008+p3834-0008` |
| 冲突 overlay | OG02D10 dual、OG02B10 quad（同一 MAX96712/I2C12） |

内核、L4T 或载板变更后必须重新编译并重新验证，不能跨版本复用二进制。
