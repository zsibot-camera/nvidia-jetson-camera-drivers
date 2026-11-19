# 版本矩阵与兼容性

本交付包为**二进制驱动包**，产物与下列环境严格绑定。

首版发布：2026-11-19。

## 目标平台

| 项 | 值 |
|---|---|
| 硬件 | Jetson AGX Thor Devkit |
| 模块型号 | P4071-0000 + P3834-0008 |
| 相机拓扑 | 1× MAX96712 + 4× MAX96717F + 4× OG02D10 |
| 输出 | 4× 1920×1280 YUYV422 @ 30 fps |
| 出流模式 | 模组自由运行（free-run），不订阅 FSYNC，无外部触发引脚 |
| 跨路同步 | 不提供（四路曝光独立） |

## 软件版本

| 组件 | 版本 | 检查命令 |
|---|---|---|
| JetPack | 7.2.1 | — |
| L4T | **R39.2.1** | `dpkg -l nvidia-l4t-core` |
| 内核 | **6.8.12-1021-tegra** | `uname -r` |
| 架构 | aarch64 | `uname -m` |
| Ubuntu | 24.04 Noble | `lsb_release -a` |

## 二进制产物与绑定关系

| 产物 | 绑定对象 | 不匹配的后果 |
|---|---|---|
| `driver/ko/serdes_core.ko` | 内核 `6.8.12-1021-tegra` + `modversions` | `Invalid module format` 或符号 CRC 不一致 |
| `driver/ko/nv_max96712.ko` | 内核 + 本包 `serdes_core` | 符号 CRC 不一致，模块拒载 |
| `driver/ko/nv_max96717.ko` | 内核 + 本包 `serdes_core` | 同上 |
| `driver/ko/nv_og02d10_single.ko` | 内核 + 本包 `serdes_core` | 同上 |
| `driver/dtb/tegra264-p4071-camera-og02d10-quad-overlay.dtbo` | L4T R39.2.1 的 `kernel_tegra264-p4071-0000+p3834-0008-nv.dtb` | 启动无相机节点或 dtbo 应用失败 |

模块 vermagic：

```text
6.8.12-1021-tegra SMP preempt mod_unload modversions aarch64
```

模块依赖：

```text
serdes_core:        （无）
nv_max96712:        serdes_core
nv_max96717:        serdes_core
nv_og02d10_single:  v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode
```

四个模块与 `serdes_ctx` 结构做符号 CRC 绑定，**必须同批安装**。本包自带全部
四个模块，不依赖系统预装版本。

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

关键二进制 SHA256（发布用已剥离调试段）：

```text
a56d8631d15a6448ff11d528ee9450ff65f16e9b7c662e04d71ee858dc701408  driver/ko/serdes_core.ko
c396e15d9549b658ce47161b33f3758998fbe054a1e9af6b37b16d9d887471f9  driver/ko/nv_max96712.ko
b588496b5d16504f1ca4b6f7f35063ca97774baef1527c605d82c0f472aa07f4  driver/ko/nv_max96717.ko
480df533bde33bc97d5376ccdeef3e0decfb0c8351aa5858078d6bf4c4b0d9a4  driver/ko/nv_og02d10_single.ko
1afc6c6271971e1db98c22ad7e3edc156ed29cd18263ad5ad9773ec9c5f03154  driver/dtb/tegra264-p4071-camera-og02d10-quad-overlay.dtbo
```

本包与仓库中其他相机包（ISX031、OG02B10、双目 OG02D10）**不共用**
`serdes_core` / `nv_max96712` / `nv_max96717` 二进制：本版本新增了
`serdes_ctx.stream_id` 和 `write_regs` 表操作。

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
| ISX031 quad overlay | 与本包共用 MAX96712 `0x6b` / I2C12，不能同时启用 |
| 双目 OG02D10 overlay | 同上 |
| OG02B10 quad overlay | 同上 |
| 其他使用 I2C12 `0x6b` 的相机 overlay | 安装前确认，避免启动时争用 |
| 旧 ABI 相机模块 | 本包 `serdes_core` 为新 ABI；旧构建 `.ko` 混用会报符号 CRC 不一致 |

`install.sh` 会从主启动项的 `OVERLAYS` 行移除其他相机 overlay，保证一个启动
周期只有一种相机拓扑。

切换到其他相机包时：

1. 先执行本包 `driver/uninstall.sh` 回滚并重启（恢复旧 `serdes_core`）；
2. 再安装目标相机包；
3. 或使用与本包 `serdes_core` 同批重建的目标包。

## 升级约束

1. **不要只升级内核或 JetPack 而保留旧驱动**：`.ko` vermagic 会不匹配。
2. 内核、L4T 或载板变化后，必须在目标版本的 Thor 源码树内重编四个模块和
   dtbo，并重新上板验证。
3. **不要把 Orin NX 的 `.ko`/dtbo 拿到 Thor 使用**，反之亦然。
4. 更换模组或改变 GMSL link 顺序时，需要按实际硬件调整设备树并重编 dtbo。
5. 本包不含 SDK、深度算法、标定和 ROS2；不要套用双目 OG02D10 的标定/深度配置。
6. 已发布的 `.ko` 已剥离 `.debug_*` 段和内部构建路径；不要用未剥离的构建产物
   替换发布包。
7. OG02D10 输出高度为 1280；不要按其他模组的高度修改 V4L2 格式或应用侧缓冲大小。
8. 四路自由运行，不提供跨路曝光同步；需要同步的应用不要使用本包。

## 相关文档

- [包根 README](../README.md)
- [驱动安装说明](../driver/README.md)
- [上板验证记录](VERIFICATION.md)
