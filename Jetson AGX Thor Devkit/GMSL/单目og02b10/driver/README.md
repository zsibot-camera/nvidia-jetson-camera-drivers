# 四目 OG02B10 驱动安装说明

本目录是 Jetson AGX Thor Devkit 四目 OG02B10 的二进制驱动包。安装内容和脚本行为
与包根目录 [README](../README.md) 一致；本文件补充安装细节和排障命令。

## 1. 文件

```text
driver/
├── ko/
│   ├── nv_og02b10.ko
│   └── nv_max96717.ko
├── dtb/
│   └── tegra264-p4071-camera-og02b10-quad-overlay.dtbo
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
| L4T | R39.2.1（JetPack 7.2.1） |
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
/lib/modules/6.8.12-1021-tegra/updates/nv_og02b10.ko
/boot/tegra264-p4071-camera-og02b10-quad-overlay.dtbo
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
- 保证 OG02B10 overlay 只出现一次；
- 没有 `OVERLAYS` 行时，在 `FDT` 行后插入。

只改第一个 `OVERLAYS` 行，是为了保留其他启动项（例如备份内核）的原配置。
如果存在多个 `OVERLAYS` 行，脚本会打印警告。若启动项由外部工具管理：

```sh
sudo ./install.sh --no-extlinux
```

然后手工设置主启动项为：

```
OVERLAYS /boot/tegra264-p4071-camera-og02b10-quad-overlay.dtbo
```

### 3.2 跳过版本检查

`--force` 会跳过内核/L4T 检查，但**不会**改变模块的 vermagic 绑定。内核不一致时
模块仍然无法加载，只建议在明确知道风险时用于排查。

## 4. 加载与验证

```sh
sudo ./load_modules.sh
```

脚本：

1. 按 `serdes_core → nv_max96712 → nv_max96717 → nv_og02b10` 顺序加载缺失模块；
2. 等待最多 15 秒；
3. 统计名称含 `og02b10` 的视频节点，少于 4 个时打印 dmesg 并失败；
4. 用 `v4l2-ctl --get-fmt-video` 打印节点格式。

手工检查：

```sh
lsmod | grep -E 'serdes_core|nv_max96712|nv_max96717|nv_og02b10'
for d in /dev/video0 /dev/video1 /dev/video2 /dev/video3; do
    v4l2-ctl -d "$d" --get-fmt-video
done
```

期望每路 `1600x1301`、`YUYV`、`Bytes per Line 3200`、`Size Image 4163200`。
四路并发采集示例见包根 README。

## 5. 节点映射

| 链路 | 代理地址 | 串行器运行地址 | VC | 实测 devnode |
|---|---|---|---|---|
| A | 0x11 | 0x43 | 0 | `/dev/video3` |
| B | 0x12 | 0x44 | 1 | `/dev/video2` |
| C | 0x13 | 0x45 | 2 | `/dev/video1` |
| D | 0x14 | 0x46 | 3 | `/dev/video0` |

传感器真实地址为 `0x20`，四颗共用；驱动通过串行器地址翻译使用 `0x11..0x14`
代理。串行器上电地址为 `0x42`，probe 后重映射到 `0x43..0x46`。

映射随载板、线束和 overlay 变化。需要固定映射时，以 `media-ctl -p` 或 dmesg 的
`vc=N` 为准。

## 6. 回滚

```sh
sudo ./uninstall.sh
sudo reboot
```

脚本优先恢复 `backup/pre-install/`（首次安装前快照），没有时恢复最近一次
`backup/<时间戳>/`，都没有时删除本包文件并从 `OVERLAYS` 行移除 OG02B10。
不会卸载或重载 `nv_max96712`、`nv_max9295d`。

## 7. 故障排查

### 7.1 模块无法加载

```sh
uname -r
modinfo ./ko/nv_og02b10.ko | grep -E 'vermagic|depends'
```

- 内核不是 `6.8.12-1021-tegra`：用目标版本的 Thor L4T 源码树重编。
- `depends` 含 `serdes_core`、`tegra-camera` 等：确认系统模块可用。
- `Invalid module format`：不要用 `--force` 硬装，vermagic 不匹配无法解决。

### 7.2 没有节点或少于 4 路

```sh
sudo ./load_modules.sh
dmesg | grep -Ei 'og02b10|max96717|max96712|nvcsi|vi capture' | tail -n 80
media-ctl -p
```

检查：

- `extlinux.conf` 主启动项只有 OG02B10 overlay；
- 四条 GMSL link 是否锁定（dmesg 的 `link 0x1/0x2/0x4/0x8 locked`）；
- 模组供电、同轴线、接插件是否可靠；
- 是否有其他进程占用节点：`fuser /dev/video0 /dev/video1 /dev/video2 /dev/video3`。

**不要**通过 `rmmod`/重载 `nv_max96712`、`nv_max9295d` 或 sysfs unbind/rebind
来排查；Thor 上可能导致内核卡死或重启。

### 7.3 串行器 probe 打印 `max96717_read_reg ... reg=0x0000`

这是驱动先按运行地址探测失败、随后用 `set_address` 把串行器从 `0x42`
重映射到 `0x43..0x46` 的正常回退。只要随后出现 remap 成功和 link lock，就不是故障。

### 7.4 `i2cdetect` 看不到 0x6b/0x43..0x46

驱动绑定后，`i2ctransfer` 访问 `0x6b` 会返回 `Device or resource busy`，
`i2cdetect -y 12` 也可能不直接显示这些地址。以 dmesg 的
`nv_max96712 12-006b`、`max96717 12-0043..0046` 和 link lock 为准，不要据此
判定链路失败。

### 7.5 画面上下颠倒

验证样机上 `video0/video1` 相对 `video2/video3` 旋转 180°，属模组安装朝向。
驱动不写 sensor 寄存器，本包不做软件翻转；需要正像时在应用端旋转或调整模组装配，
不要改驱动/overlay 的翻转字段。

### 7.6 板端 `nvcompositor` 崩溃

在 Thor 上 `nvcompositor` 合成四路 1600×1301 会 SIGSEGV（ISX031 验证中同样出现）。
演示视频使用四路独立 `nvv4l2h264enc` 硬编、主机侧 ffmpeg 合成；不要把
`nvcompositor` 当作稳定路径。

## 8. 兼容性

| 项目 | 值 |
|---|---|
| 内核 | 6.8.12-1021-tegra（vermagic 含 `SMP preempt mod_unload modversions aarch64`） |
| 模块依赖 | `nv_og02b10`：`v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode`；`nv_max96717`：`serdes_core` |
| dtbo compatible | `nvidia,p4071-0000+p3834-0008`、`nvidia,p4071-0008+p3834-0008` |
| 冲突 overlay | ISX031 quad、OG02D10 dual（同一 MAX96712/I2C12） |

内核、L4T 或载板变更后必须重新编译并重新验证，不能跨版本复用二进制。
