# 上板验证记录

- 日期：2026-11-19
- 平台：Jetson AGX Thor Devkit（P4071 + P3834-0008）
- 系统：JetPack 7.2.1 / L4T R39.2.1
- 内核：`6.8.12-1021-tegra`
- 相机：1× MAX96712 + 4× MAX96717 + 4× OG02B10
- 同步：MAX96712 内部 FSYNC 30 Hz（GPIO ID 8），无外部触发

## 1. 驱动与节点

加载的相机相关模块：

```text
serdes_core
nv_max96712
nv_max96717
nv_og02b10
```

`media-ctl -p` 可见 4 个 `og02b10 12-0011..0014` subdev 和 4 个 `vi-output`
节点。四个 V4L2 节点名称与格式一致：

```text
/dev/video0 = vi-output, og02b10 12-0014   (VC3)
/dev/video1 = vi-output, og02b10 12-0013   (VC2)
/dev/video2 = vi-output, og02b10 12-0012   (VC1)
/dev/video3 = vi-output, og02b10 12-0011   (VC0)
```

```text
Width/Height      : 1600/1301
Pixel Format      : 'YUYV' (YUYV 4:2:2)
Field             : None
Bytes per Line    : 3200
Size Image        : 4163200
```

单帧大小 4,163,200 字节（1600 × 1301 × 2）。高度是 1301，不是 1300；
VI 配置 `frame configuration: 1600x1301` 与 V4L2 一致，无高度不匹配或首帧超时。

## 2. GMSL 链路与串行器地址

四条 GMSL link 全部锁定：

```text
link 0x1 locked, lock time 0ms
link 0x2 locked, lock time 0ms
link 0x4 locked, lock time 0ms
link 0x8 locked, lock time 0ms
```

串行器上电地址为 `0x42`，probe 后重映射到 `0x43..0x46`：

```text
max96717 12-0043
max96717 12-0044
max96717 12-0045
max96717 12-0046
```

probe 阶段会出现一次按运行地址探测失败：

```text
max96717_read_reg ... reg=0x0000
```

随后 `set_address` 成功，属正常地址回退，不是链路故障。

驱动绑定后：

- `i2cdetect -y 12` 实测不会直接显示 `0x6b` 或 `0x43..0x46`；
- `i2ctransfer` 访问 `0x6b` 会返回 `Device or resource busy`。

这是驱动占用 I2C 地址后的正常现象；地址和链路状态以 dmesg 的
`nv_max96712 12-006b`、`max96717 12-0043..0046` 和 link lock 为准。

## 3. FSYNC 同步

解串器内部 FSYNC 配置：

```text
nv_max96712 12-006b: deser FSYNC period 33333000 ns (833325 xtal cycles), GPIO ID 8
nv_max96712 12-006b: deser FSYNC trigger on (1 user(s))
```

四个串行器各有一条 MFP7 接收配置：

```text
mfp_cfg gpio_index:7, gpio_id:8, GPIO_RX_GMSL
```

解串器发送端同样是 `gpio_id8`。两端 GPIO ID 一致，周期 33,333,000 ns
（30 Hz）。串行器复位使用 MFP5；驱动不写 sensor 寄存器。

## 4. 四路并发取流

四路同时各取 30 帧：

```sh
for i in 0 1 2 3; do
    v4l2-ctl -d "/dev/video$i" \
        --set-fmt-video=width=1600,height=1301,pixelformat=YUYV \
        --stream-mmap --stream-count=30 --stream-to="/tmp/cam$i.yuv" &
done
wait
```

结果：

| 节点 | 帧数 | 文件大小（字节） |
|---|---|---|
| `/dev/video0` | 30 | 124,896,000 |
| `/dev/video1` | 30 | 124,896,000 |
| `/dev/video2` | 30 | 124,896,000 |
| `/dev/video3` | 30 | 124,896,000 |

四路首帧 SHA-256 互不相同，确认不是同一路数据重复输出。四路首帧 Y 平面
均值范围 116.6–122.1，画面亮度一致但内容不同。

## 5. 帧率

每路连续取 300 帧和 1800 帧各做一组：

| 采集 | 帧数 | 采集窗口 | 统计帧率 |
|---|---|---|---|
| 快速验证 | 300 | 9.967 s | 30.00 fps |
| 长稳验证 | 1800 | 59.968 s | 30.00 fps |

两组四路均完成，无取流超时、VI 错误或节点丢失。

## 6. 四路同步

时间戳使用 `v4l2-ctl --stream-mmap --verbose` 的
`ts-monotonic, ts-src-eof`，对四路最近时间戳做两两差值和逐帧 spread：

| 指标 | 300 帧组 | 1800 帧组 |
|---|---|---|
| 两两时间戳差中位 | 3–9 µs | 3–9 µs |
| 两两时间戳差最大 | 10 µs | 10 µs |
| 四路逐帧 spread 中位 | 9 µs | 9 µs |
| 四路逐帧 spread p95/max | 10 µs | 10 µs |
| 验收门限 | 1 ms | 1 ms |

两组结果一致，远低于 1 ms 门限。同步由解串器内部 FSYNC 产生，不依赖外部
触发引脚。

## 7. 图像内容与颜色

- 四路画面真实且互不相同；
- 颜色顺序正确：蓝色水桶、绿色出口指示灯均显示正常；
- 取流期间 dmesg 无 VI/CSI 错误；
- 测试样机上 `video0/video1` 相对 `video2/video3` 旋转 180°，属模组安装朝向，
  驱动不做翻转；
- 四路 1600×1301@30 总带宽约 4.0 Gbps，低于 ISX031 四路的 5.66 Gbps；
  `2500 Mbps/lane` 配置实测无 CSI/VI 错误。

验证时生成的材料：

| 材料 | 说明 |
|---|---|
| `demo/mosaic.png` | 同帧号（第 15 帧）四路 2×2 彩色拼图 |
| `demo/og02b10_quad_demo.mp4` | 4.000 s、120 帧、1600×1300@30 的 2×2 视频 |

演示视频由四路独立 `nvv4l2h264enc` 硬编、主机侧 ffmpeg `xstack` 合成。
板端 `nvcompositor` 合成四路 1600×1301 会 SIGSEGV，不作为稳定路径。

## 8. 已知现象

### 8.1 串行器 probe `read_reg ... reg=0x0000`

驱动先按运行地址探测串行器失败，随后通过 `set_address` 从 `0x42` 重映射到
`0x43..0x46`。只要 remap 成功且 link lock 置位，就不是故障。

### 8.2 `i2cdetect` / `i2ctransfer` 表现

驱动绑定后 I2C 地址由驱动占用：`i2cdetect` 可能看不到 `0x6b/0x43..0x46`，
`i2ctransfer` 访问 `0x6b` 返回 `Device or resource busy`。不要据此判定链路失败，
以 dmesg 为准。

### 8.3 安装朝向

样机 `video0/video1` 画面相对 `video2/video3` 倒置 180°。驱动不写 sensor
寄存器，画面方向由模组安装决定；需要正像时在应用端旋转或调整模组装配，不要改
驱动/overlay 的翻转字段。

### 8.4 `nvcompositor` SIGSEGV

Thor 上 `nvcompositor` 合成四路 1600×1301 会崩溃（ISX031 验证中同样出现）。
演示改用四路独立硬编 + 主机侧合成；客户侧建议单路预览或自行合成。

### 8.5 冷启动

本次冷启动（安装 dtbo 后重启）未出现 ISX031 那种首流瞬时 I2C `-121`。
后续若出现，先确认四条 link 是否锁定，再按包根 README 第 8 节排查。

## 9. 发布二进制校验

上板验证使用未剥离的构建产物。发布前对两个 `.ko` 执行：

```sh
aarch64-linux-gnu-strip --strip-debug nv_og02b10.ko nv_max96717.ko
```

并在主机复核：

| 模块 | 原始大小 | 剥离后大小 | 剥离后 SHA256 |
|---|---|---|---|
| `nv_og02b10.ko` | 74,488 B | 25,920 B | `03a41eb54809e816656b43de7cf5a185bacf9162116b4c48dc4e62aaeed5be1d` |
| `nv_max96717.ko` | 78,512 B | 21,704 B | `f9cc69e8667484d2f61485b48030675813dd20553ae61205834f0b484732ac59` |

校验结果：

- 剥离产物与 `objcopy --strip-debug` 的原件**逐字节相同**（两个模块均通过
  `cmp`）；
- `.text`、`.data`、`.rodata`、`.modinfo` 段哈希一致；
- 无 `.debug_*` 段；
- 无内部构建路径（如 `/home/...`）；
- `modinfo` 的 vermagic 和依赖关系不变：

```text
vermagic: 6.8.12-1021-tegra SMP preempt mod_unload modversions aarch64
nv_og02b10:   depends v4l2-async,tegra-camera,serdes_core,videodev,mc,v4l2-fwnode
nv_max96717:  depends serdes_core
```

`nv_max96717.ko` 的 SHA256 与 ISX031 交付包中的同名二进制一致，说明两个包
使用的是同一份 Thor 源码树构建产物。

## 10. 交付包校验范围

本交付目录在主机完成：

- `sha256sum -c checksums.txt` 全量校验；
- 三个脚本 `bash -n` 语法检查；
- 二进制剥离等价性检查（见第 9 节）；
- 包内无源码、内部头文件、测试、构建脚本、调试符号和主机路径。

上板验证使用同一构建产物；本目录未重复在板上安装（板上运行的就是该构建）。
如需按 ISX031 流程做板上只读复检，在板端执行：

```sh
sha256sum -c checksums.txt
./preflight.sh
sudo ./driver/install.sh --check
```

两条只读命令不会修改板端配置。
