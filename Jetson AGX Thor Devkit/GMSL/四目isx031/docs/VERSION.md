# 版本矩阵与兼容性

本交付包为**二进制驱动包**，产物与下列环境严格绑定。

首版发布：2026-11-18。

## 目标平台

| 项 | 值 |
|---|---|
| 硬件 | Jetson AGX Thor Devkit |
| 模块型号 | P4071-0000 + P3834-0008 |
| 相机拓扑 | 1× MAX96712 + 4× MAX96717 + 4× ISX031 |
| 输出 | 4× 1920×1536 YUYV422 @ 30 fps |
| 同步 | MAX96712 内部 FSYNC 30 Hz（GPIO ID 8），无外部触发引脚 |

## 软件版本

| 组件 | 版本 | 检查命令 |
|---|---|---|
| JetPack | 7.0 | — |
| L4T | **R39.2.1**（`39.2.1-20260806224157`） | `dpkg -l nvidia-l4t-core` |
| 内核 | **6.8.12-1021-tegra** | `uname -r` |
| 架构 | aarch64 | `uname -m` |
| Ubuntu | 24.04 Noble | `lsb_release -a` |

## 二进制产物与绑定关系

| 产物 | 绑定对象 | 不匹配的后果 |
|---|---|---|
| `driver/ko/nv_isx031.ko` | 内核 `6.8.12-1021-tegra` + `modversions` | `Invalid module format`，模块拒载 |
| `driver/ko/nv_max96717.ko` | 内核 `6.8.12-1021-tegra` + `modversions` | 同上 |
| `driver/dtb/tegra264-p4071-camera-isx031-quad-overlay.dtbo` | L4T R39.2.1 的 `kernel_tegra264-p4071-0000+p3834-0008-nv.dtb` | 启动无相机节点或 dtbo 应用失败 |

模块 vermagic：

```text
6.8.12-1021-tegra SMP preempt mod_unload modversions aarch64
```

模块依赖：

```text
nv_isx031:   v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode
nv_max96717: serdes_core
```

`serdes_core` 和 `nv_max96712` 由系统自带，本包不安装、不覆盖。缺失时
`install.sh --check` 会直接失败。

## 设备树 compatible

```text
nvidia,p4071-0000+p3834-0008
nvidia,p4071-0008+p3834-0008
```

overlay 只适用于上述 Thor Devkit 组合；换载板或模组需要按实际硬件重编。

## 交付内容校验

```bash
sha256sum -c checksums.txt
```

## 依赖包（客户机应已由 JetPack 提供）

```text
nvidia-l4t-camera
nvidia-l4t-core
```

安装/检查脚本还依赖：

```text
python3, kmod (modinfo/depmod), v4l2-utils (v4l2-ctl, 建议)
```

## 冲突与共存

| 项目 | 说明 |
|---|---|
| OG02D10 dual overlay | 与 ISX031 共用 MAX96712 `0x6b` / I2C12，不能同时启用 |
| OG02B10 quad overlay | 同上 |
| 其他使用 I2C12 `0x6b` 的相机 overlay | 安装前确认，避免启动时争用 |

`install.sh` 会从主启动项的 `OVERLAYS` 行移除 OG02D10/OG02B10 overlay，保证
一个启动周期只有一种相机拓扑。

## 升级约束

1. **不要只升级内核或 JetPack 而保留旧驱动**：`.ko` vermagic 会不匹配。
2. 内核、L4T 或载板变化后，必须在目标版本的 Thor 源码树内重编 `nv_isx031`、
   `nv_max96717` 和 dtbo，并重新上板验证。
3. **不要把 Orin NX 的 `.ko`/dtbo 拿到 Thor 使用**，反之亦然。
4. 更换模组或改变 GMSL link 顺序时，需要按实际硬件调整设备树并重编 dtbo。
5. 本包不含 SDK、深度算法、标定和 ROS2；不要套用 OG02D10 的标定/深度配置。
6. 已发布的 `nv_isx031.ko` / `nv_max96717.ko` 已剥离 `.debug_*` 段和内部构建路径；
   不要用未剥离的构建产物替换发布包。

## 相关文档

- [包根 README](../README.md)
- [驱动安装说明](../driver/README.md)
- [上板验证记录](VERIFICATION.md)
