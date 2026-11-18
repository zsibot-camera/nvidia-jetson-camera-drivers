# 上板验证记录

- 日期：2026-11-18
- 平台：Jetson AGX Thor Devkit（P4071 + P3834-0008）
- 系统：JetPack 7.0 / L4T R39.2.1（`39.2.1-20260806224157`）
- 内核：`6.8.12-1021-tegra`
- 相机：1× MAX96712 + 4× MAX96717 + 4× ISX031
- 同步：MAX96712 内部 FSYNC 30 Hz（GPIO ID 8），无外部触发

## 1. 驱动与节点

加载的相机相关模块：

```text
serdes_core
nv_max96712
nv_max96717
nv_isx031
```

`media-ctl -p` 可见 4 个 `isx031 12-0011..0014` subdev 和 4 个 `vi-output` 节点。
四个 V4L2 节点格式一致：

```text
/dev/video0..3
Width/Height      : 1920/1536
Pixel Format      : 'YUYV' (YUYV 4:2:2)
Field             : None
Bytes per Line    : 3840
Size Image        : 5898240
```

单帧大小 5,898,240 字节（1920 × 1536 × 2）。

## 2. 四路并发取流

四路同时各取 30 帧做快速验证：

```sh
for i in 0 1 2 3; do
    v4l2-ctl -d "/dev/video$i" \
        --set-fmt-video=width=1920,height=1536,pixelformat=YUYV \
        --stream-mmap --stream-count=30 --stream-to="/tmp/cam$i.yuv" &
done
wait
```

结果：

| 节点 | 帧数 | 文件大小（字节） |
|---|---|---|
| `/dev/video0` | 30 | 176,947,200 |
| `/dev/video1` | 30 | 176,947,200 |
| `/dev/video2` | 30 | 176,947,200 |
| `/dev/video3` | 30 | 176,947,200 |

四路文件逐帧哈希不同，确认不是同一路数据重复输出。

## 3. 帧率

每路连续取 240 帧：

| 指标 | 结果 |
|---|---|
| 完成帧数 | 240/240（四路均完成） |
| 帧率 | 29.99–30.00 fps |
| 帧间隔中位 | 33,334 µs |

## 4. 四路并发与同步

四路同时各取 90 帧，全部完成；四路图像内容互不相同。

时间戳使用 `v4l2-ctl --verbose` 的 `ts-monotonic, ts-src-eof`，对四路最近时间戳
做两两差值：

| 指标 | 结果 |
|---|---|
| 两两时间戳差中位 | 4–11 µs |
| 两两时间戳差最大 | 42 µs |
| 验收门限 | 1 ms |

同步由解串器内部 FSYNC 产生，dmesg 证据：

```text
nv_max96712 12-006b: deser FSYNC period 33333000 ns (833325 xtal cycles), GPIO ID 8
nv_max96712 12-006b: deser FSYNC trigger on (1 user(s))
```

串行器引脚未改动；模组保持 `SG_MODE=1`（外部脉冲同步）。

## 5. 压力测试

20 轮 × 4 路 × 4 帧：

```text
80/80 通过
```

测试期间未出现取流超时、VI 错误或节点丢失。

## 6. 物理链路映射

本机实测：

| 链路 | 代理地址 | 串行器 | VC | devnode |
|---|---|---|---|---|
| A | 0x11 | 0x41 | 0 | `/dev/video3` |
| B | 0x12 | 0x42 | 1 | `/dev/video2` |
| C | 0x13 | 0x43 | 2 | `/dev/video1` |
| D | 0x14 | 0x44 | 3 | `/dev/video0` |

映射由 Linux 枚举决定，换载板/线束后需重新确认。

## 7. 已知现象

### 7.1 冷启动首次取流 I2C `-121`

一次冷启动后约 30 秒首次取流出现：

```text
sensor i2c write addr 0x11 len 3 failed: -121
```

`stream-on` 失败，VI 随后超时。同一启动内重试取流恢复；此后 100+ 次取流
（含四路并发、80/80 压力测试）未复现。处理方式：重新发起取流，不重载驱动。

### 7.2 `v4l2_subdev_has_pad_interdep` WARNING

每次启动可能打印一次：

```text
WARNING: ... v4l2_subdev_has_pad_interdep ...
```

发生在 STREAMON 期间，不影响取流。OG02D10 的 pad ops 同构，属于该平台
sensor 驱动的共性日志噪声，不是 ISX031 移植引入的回归。

## 8. 发布二进制说明

上板验证使用未剥离的构建产物。发布前对两个 `.ko` 执行：

```sh
aarch64-linux-gnu-strip --strip-debug nv_isx031.ko nv_max96717.ko
```

并确认：

- 无 `.debug_*` 段；
- 无 `/home/...` 等内部构建路径；
- `.text`、`.data`、`.rodata`、`.modinfo` 与上板验证版本逐字节一致；
- `modinfo` 的 vermagic 和依赖关系不变。

因此发布包与验证版本在可执行代码和数据上等价，仅移除了调试信息。

## 9. 发布包复检（2026-11-18）

发布包拷到 Thor 后做只读复检：

```text
sha256sum -c checksums.txt        全部 OK
./preflight.sh                    0 项 FAIL，0 项 WARN
./driver/install.sh --check       检查通过
```

`preflight.sh` 覆盖架构、内核、L4T、两个 `.ko` 的 vermagic、`serdes_core` /
`nv_max96712` 依赖、extlinux overlay、4 个 `isx031` 节点、1920×1536 YUYV 格式
和节点占用检查。复检未修改板端配置。
