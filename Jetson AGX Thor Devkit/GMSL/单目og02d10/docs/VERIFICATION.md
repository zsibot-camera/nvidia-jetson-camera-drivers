# 上板验证记录

- 日期：2026-11-19
- 平台：Jetson AGX Thor Devkit（P4071 + P3834-0008）
- 系统：JetPack 7.2.1 / L4T R39.2.1
- 内核：`6.8.12-1021-tegra`
- 相机：1× MAX96712 + 4× MAX96717F + 4× OG02D10
- 模式：OG02D10 自由运行（free-run），不订阅 FSYNC，无外部触发
- 验证口径：数据流（节点、格式、帧率、四路内容互异）。本次未安装镜头，
  图像内容不作为判据

## 1. 驱动与节点

加载的相机相关模块：

```text
serdes_core
nv_max96712
nv_max96717
nv_og02d10_single
```

`lsmod` 关键行：

```text
nv_max96712            20480  0
nv_og02d10_single      16384  4
nv_max96717            16384  0
serdes_core            12288  3 nv_max96717,nv_og02d10_single,nv_max96712
```

磁盘上还保留其他相机包的 `nv_og02d10.ko`（旧双目）和 `nv_og02b10.ko`，
但未加载；本启动周期只使用本包拓扑。

四个 V4L2 节点名称与格式：

```text
/dev/video0 = vi-output, og02d10sgl 12-0013   (VC2)
/dev/video1 = vi-output, og02d10sgl 12-0012   (VC1)
/dev/video2 = vi-output, og02d10sgl 12-0011   (VC0)
/dev/video3 = vi-output, og02d10sgl 12-0014   (VC3)
```

驱动 probe 记录了链路、pipe 与 VC 的对应关系：

```text
og02d10_single 12-0011: probe end, 1920x1280, data_type=0x1e, lane_num=2,
                       pipe=0, csi_port=0, link=0, stream_id=0
og02d10_single 12-0012: probe end, 1920x1280, data_type=0x1e, lane_num=2,
                       pipe=1, csi_port=0, link=1, stream_id=0
og02d10_single 12-0013: probe end, 1920x1280, data_type=0x1e, lane_num=2,
                       pipe=2, csi_port=0, link=2, stream_id=0
og02d10_single 12-0014: probe end, 1920x1280, data_type=0x1e, lane_num=2,
                       pipe=3, csi_port=0, link=3, stream_id=0
```

`v4l2-ctl --get-fmt-video`（四路一致）：

```text
Width/Height      : 1920/1280
Pixel Format      : 'YUYV' (YUYV 4:2:2)
Field             : None
Bytes per Line    : 3840
Size Image        : 4915200
Colorspace        : sRGB
YCbCr/HSV Encoding: Default (maps to ITU-R 601)
Quantization      : Default (maps to Limited Range)
```

单帧大小 4,915,200 字节（1920 × 1280 × 2）。

## 2. GMSL 链路与串行器地址

四条 GMSL link 全部锁定：

```text
[   11.236752] nv_max96712 12-006b: link 0x4 locked, lock time 0ms
[   12.220739] nv_max96712 12-006b: link 0x2 locked, lock time 0ms
[   13.211071] nv_max96712 12-006b: link 0x1 locked, lock time 0ms
[   14.203754] nv_max96712 12-006b: link 0x8 locked, lock time 0ms
```

解串器初始化：

```text
[   11.128861] nv_max96712 12-006b: frame sync from the internal generator, 25000000 Hz
[   11.140441] nv_max96712 12-006b: phy_type=dphy, phy_speed=2500
[   11.158385] nv_max96712 12-006b: init done (phy_type=dphy, phy_speed=2500)
```

本次启动周期中模组未断电，串行器已处于运行地址 `0x43..0x46`，驱动跳过重映射：

```text
max96717 12-0043: max96717_map_addr serializer already at 0x43, skip remap
max96717 12-0044: max96717_map_addr serializer already at 0x44, skip remap
max96717 12-0045: max96717_map_addr serializer already at 0x45, skip remap
max96717 12-0046: max96717_map_addr serializer already at 0x46, skip remap
```

冷启动或模组重新上电后，串行器回到 `0x42`，驱动会执行 `set_address` 重映射；
两种日志都属正常，以 link lock 为准。

每 link 独立 pipe，汇成 4-lane CSI 并按 VC 区分：

```text
port0 pipe0, data_type 0x1e, src_vc0, dst_vc0
port1 pipe1, data_type 0x1e, src_vc0, dst_vc1
port2 pipe2, data_type 0x1e, src_vc0, dst_vc2
port3 pipe3, data_type 0x1e, src_vc0, dst_vc3
```

## 3. 出流模式

OG02D10 模组自带 30 fps 时序，驱动不写 sensor 寄存器，也不订阅 MAX96712
FSYNC trigger。对 dmesg 的 `trigger` / `fsync` 过滤后只有内部发生器初始化：

```text
[   11.128861] nv_max96712 12-006b: frame sync from the internal generator, 25000000 Hz
```

没有 `deser FSYNC period ...` / `trigger on`，也没有串行器
`mfp_cfg ... GPIO_RX_GMSL` 记录。这是本包与 OG02B10 包的关键差异：
OG02B10 请求 FSYNC 外部触发，OG02D10 自由运行。

模组上电的 MFP5/MFP7/MFP8/MFP0 时序按厂商 ini
`max9296_96717f_OG02D10_YUV_1920x1280_30fps_2lane.ini` 在驱动中通过
`serdes_regval` 表逐行写入串行器；ini 中 `0xfff8,0x90` 之后的 MAX9296A EVB
配置块不适用于本板，驱动未使用。

## 4. 四路并发取流

四路各取 1 帧并计算 SHA-256：

| 节点 | 大小（字节） | 首帧 SHA-256 |
|---|---|---|
| `/dev/video0` | 4,915,200 | `e111938070f50e1a671981ab672c19d67cef1329648a731a93cc20b322f01e12` |
| `/dev/video1` | 4,915,200 | `9cf96cff87608a5836480c681a1f667268445c51d9e59fa8e81ac3c1932d8188` |
| `/dev/video2` | 4,915,200 | `e86a4cda87673f46c17f623fbdd2338bc1ffcd0c2d7e1bac19313515e3e93771` |
| `/dev/video3` | 4,915,200 | `4091381942084eefc016582a00eaa15424f55ad8142aa0703ee676c31a1fd219` |

四路 SHA-256 互不相同，确认不是同一路数据重复输出。

Y 平面统计（未装镜头，漫射光）：

| 节点 | Y 均值 | Y 标准差 |
|---|---|---|
| `/dev/video0` | 113.7 | 4.36 |
| `/dev/video1` | 126.4 | 1.92 |
| `/dev/video2` | 112.7 | 3.61 |
| `/dev/video3` | 110.2 | 4.22 |

四路并发、每路 300 帧：

```sh
for i in 0 1 2 3; do
    v4l2-ctl -d "/dev/video$i" \
        --set-fmt-video=width=1920,height=1280,pixelformat=YUYV \
        --stream-mmap --stream-count=300 --stream-to=/dev/null &
done
wait
```

结果：四路全部完成，墙钟 10.101 s，即每路 29.70 fps。

## 5. 帧率

单路连续 60 帧的墙钟时间：

| 节点 | 60 帧耗时 | 含首帧延迟的统计帧率 |
|---|---|---|
| `/dev/video0` | 2078 ms | 28.87 fps |
| `/dev/video1` | 2080 ms | 28.85 fps |
| `/dev/video2` | 2056 ms | 29.18 fps |
| `/dev/video3` | 2092 ms | 28.68 fps |

60 帧包含首帧启动延迟；四路并发 300 帧的稳态结果为 29.70 fps/路。取流无超时、
无 VI/CSI 错误、无节点丢失。

## 6. 跨路同步

本包**不提供跨路曝光同步**。OG02D10 为自由运行模组，驱动不订阅 FSYNC，
四路时间戳相互独立。本次验证只确认四路各自稳定出流，不宣称路间同步指标。
需要硬件同步相机时，应改用支持外部触发、由 FSYNC 驱动的模组/固件。

## 7. 图像内容

- 本次验证未安装镜头，四路画面为漫射光下的均匀灰底；
- Y 均值 110.2–126.4、标准差 1.9–4.4，四路内容互异；
- 按验证口径，图像内容不作为判据；需要图像质量验收时，装镜头后重新测试。

## 8. 已知现象

### 8.1 串行器 `already at 0x4x, skip remap`

本次启动周期模组未断电，串行器保留运行地址，驱动跳过重映射。冷启动时会出现
`set_address` 重映射；只要 link lock 置位、4 个节点出现，就不是故障。

### 8.2 `i2cdetect` / `i2ctransfer` 表现

驱动绑定后 I2C 地址由驱动占用：`i2cdetect` 可能看不到 `0x6b/0x43..0x46`，
`i2ctransfer` 访问 `0x6b` 返回 `Device or resource busy`。不要据此判定链路失败，
以 dmesg 为准。

### 8.3 `v4l2-ctl` 的 32 字节节点名限制

`tegra_channel_querycap()` 用 `strscpy` 把节点名拷进 32 字节的
`v4l2_capability.card`，超长返回 `-ENAMETOOLONG`，表现为
`Failed to open ...: File name too long`。本驱动使用短 subdev 名 `og02d10sgl`，
节点名 30 字节；这是必须在交付二进制中保留的修复。

### 8.4 `nvcompositor` SIGSEGV

Thor 上 `nvcompositor` 合成多路高分辨率视频流会出现 SIGSEGV（平台已知问题）。
本包未使用该路径；建议单路预览，或四路独立硬编后在主机侧合成。

### 8.5 未安装镜头

本阶段只验证数据流；装镜头后需重新确认图像内容、颜色和曝光。

## 9. 发布二进制校验

上板验证使用未剥离的构建产物。发布前对四个 `.ko` 执行：

```sh
aarch64-linux-gnu-strip --strip-debug <module>.ko
```

并在主机复核：

| 模块 | 原始大小 | 剥离后大小 | 剥离后 SHA256 |
|---|---|---|---|
| `serdes_core.ko` | 31,024 B | 6,536 B | `a56d8631d15a6448ff11d528ee9450ff65f16e9b7c662e04d71ee858dc701408` |
| `nv_max96712.ko` | 106,440 B | 30,744 B | `c396e15d9549b658ce47161b33f3758998fbe054a1e9af6b37b16d9d887471f9` |
| `nv_max96717.ko` | 80,552 B | 22,616 B | `b588496b5d16504f1ca4b6f7f35063ca97774baef1527c605d82c0f472aa07f4` |
| `nv_og02d10_single.ko` | 68,600 B | 22,824 B | `480df533bde33bc97d5376ccdeef3e0decfb0c8351aa5858078d6bf4c4b0d9a4` |

dtbo 未剥离，`15,502 B`，SHA256
`1afc6c6271971e1db98c22ad7e3edc156ed29cd18263ad5ad9773ec9c5f03154`。

校验结果：

- 剥离产物与 `objcopy --strip-debug` 的原件**逐字节相同**（四个模块均通过 `cmp`）；
- `.text`、`.data`、`.rodata`、`.modinfo` 段哈希一致；
- 无 `.debug_*` 段（`readelf -S` 统计为 0）；
- 无内部构建路径（`strings` 未命中源码树路径、主机用户名等）；
- `modinfo` 的 vermagic 和依赖关系不变：

```text
vermagic: 6.8.12-1021-tegra SMP preempt mod_unload modversions aarch64
serdes_core:        （无）
nv_max96712:        serdes_core
nv_max96717:        serdes_core
nv_og02d10_single:  v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode
```

板上运行的非剥离模块 SHA256 与本包剥离前的构建产物一致，说明交付包来自
同一构建；剥离只删除调试信息。

## 10. 交付包校验范围

本交付目录在主机完成：

- `sha256sum -c checksums.txt` 全量校验；
- `bash -n` 语法检查（`preflight.sh`、`driver/install.sh`、`driver/uninstall.sh`、
  `driver/load_modules.sh`）；
- 二进制剥离等价性检查（见第 9 节）；
- 包内无源码、内部头文件、测试、构建脚本、调试符号和主机路径。

上板验证使用同一构建产物；本目录未重复在板上安装。如需在板端做只读复检：

```sh
sha256sum -c checksums.txt
./preflight.sh
sudo ./driver/install.sh --check
```

这三条命令不会修改板端配置。
