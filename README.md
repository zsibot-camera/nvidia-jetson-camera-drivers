# NVIDIA Jetson 相机驱动

智身科技（GENISOM AI）视觉传感器团队面向 NVIDIA Jetson 平台的相机驱动、SDK 与
上位机工具发布仓库。

> 客户侧 AI 助手：直接阅读 [README-AI.md](README-AI.md)，按里面的命令校验并一键安装。
> 人类用户按下面的“交付包下载 / 快速开始”操作即可。

## 交付包下载

| 交付物 | 下载 | 适用 |
| --- | --- | --- |
| Thor 深度 SDK 0.1.0 | [depth_sdk-0.1.0-thor-aarch64.tar.gz](https://github.com/zsibot-camera/nvidia-jetson-camera-drivers/releases/download/thor-depth-sdk-v0.1.0/depth_sdk-0.1.0-thor-aarch64.tar.gz) | Thor 板端 C++ 集成 |
| ZSViewer 2.1.0 | [ZSViewer 独立交付仓库](https://github.com/zsibot-camera/ZSViewer-delivery/releases/tag/v2.1.0) | Linux / Windows 上位机 |
| 驱动 + SDK + ROS2 | [双目 OG02D10 交付包](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/) | Thor 板端完整链路 |

每个 Release 附带 `SHA256SUMS`，下载后先校验：

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

## 内容

| 平台 | 接口 | 相机模组 | 说明 |
| --- | --- | --- | --- |
| Jetson AGX Thor Devkit | GMSL | 双目 OG02D10 | [深度相机交付包](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/) |
| 上位机 Linux / Windows | — | 通用 | [ZSViewer](https://github.com/zsibot-camera/ZSViewer-delivery) RGB-D 查看 / 点云 / 抓图 / 录像（独立仓库） |
| Thor 板端 | — | 通用 | depth_sdk 0.1.0（头文件 + 动态库 + engine） |

其他平台与模组目录（Jetson AGX Orin Devkit、RLINK、单目 ISX031 / OG02B10）暂未发布。

## 交付形式

以二进制交付为主：内核驱动（`.ko` / `.dtbo`）、安装脚本、预编译 SDK（头文件 + 动态库 +
TensorRT engine）、ROS2 节点，不包含算法与 C++ 源码。上位机 ZSViewer 在独立的
[ZSViewer-delivery](https://github.com/zsibot-camera/ZSViewer-delivery) 仓库交付。

---

## 快速开始：Thor GMSL 双目 OG02D10

以下流程在 Jetson AGX Thor Devkit（P4071 + P3834-0008）上实测通过。

### 0. 系统要求

| 项 | 版本 |
|---|---|
| 平台 | Jetson AGX Thor Devkit（P4071 + P3834-0008） |
| JetPack | 7.0（L4T **R39.2.1**） |
| 内核 | 6.8.12-1021-tegra |
| ROS2 | **Jazzy**（Ubuntu 24.04 Noble） |
| VPI | 4.1.4（`/opt/nvidia/vpi4`，JetPack 自带） |
| TensorRT | 10.16.2（JetPack 自带） |
| CUDA | 13.2（JetPack 自带） |
| OpenCV | 4.8（`libopencv_core.so.408`） |

> 版本不匹配会导致 `.ko` 拒载或 TensorRT engine 反序列化失败。逐项版本矩阵见
> [`docs/VERSION.md`](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/docs/VERSION.md)。

ROS2 Jazzy 未安装时，按官方文档安装：

<https://docs.ros.org/en/jazzy/Installation.html>

### 1. 获取代码

```bash
git clone https://github.com/zsibot-camera/nvidia-jetson-camera-drivers.git
cd "nvidia-jetson-camera-drivers/Jetson AGX Thor Devkit/GMSL/双目og02d10"
```

整个 `双目og02d10/` 目录可以放在任意路径，启动脚本会自动处理配置里的绝对路径。

### 2. 环境预检

```bash
chmod +x start_depth_ros.sh preflight.sh
./preflight.sh
```

预检会检查内核、L4T、ROS2、VPI、TensorRT、CUDA、OpenCV、交付包完整性与相机设备。
安装驱动前 `/dev/video0`、`/dev/video1` 不存在属于正常情况，只报 WARN。

### 3. 安装相机驱动

```bash
cd driver
sudo ./install.sh --check   # 只检查，不落盘
sudo ./install.sh           # 安装 4 个 .ko + dtbo，并更新 extlinux OVERLAYS
sudo reboot
```

重启后加载模块并确认设备节点：

```bash
cd "nvidia-jetson-camera-drivers/Jetson AGX Thor Devkit/GMSL/双目og02d10/driver"
sudo ./load_modules.sh
ls -l /dev/video0 /dev/video1
```

应看到 `/dev/video0`（12-0030，VC1）与 `/dev/video1`（12-0020，VC0）。详见
[`driver/README.md`](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/driver/README.md)。

### 4. 放入本模组的标定文件

`sdk/config/stereo_calibration.json` 是**按相机模组个体标定**的，随货提供。
拿到本模组对应的标定文件后覆盖默认文件：

```bash
cp <本模组标定>/stereo_calibration.json sdk/config/stereo_calibration.json
```

用错标定也能出深度图，但测距精度不保证。

### 5. 启动 ROS2 深度节点

```bash
# 相机是独占设备，先确认没有 uvdp_streamer / ZSViewer / demo 等进程占用
sudo fuser -v /dev/video0 /dev/video1

./start_depth_ros.sh
```

`start_depth_ros.sh` 会：

1. 按当前目录生成一份临时配置，把 `rectify.calibration_file` 与 `model.engine`
   改写到交付包内的实际路径（不再依赖 `/home/nvidia/depth_sdk`）；
2. 设置 `DEPTH_SDK_CONFIG` 与 `LD_LIBRARY_PATH`；
3. source ROS2 Jazzy 与预编译节点的 `setup.bash`，再启动 `depth_stream.launch.py`。

也可以用 `DEPTH_SDK_CONFIG=/path/to/your.conf ./start_depth_ros.sh` 指定自己的配置
（此时不再自动改写）。

### 6. 验证

```bash
# 深度 10 fps、校正彩色 30 fps
ros2 topic hz /depth_stream_node/depth/image_raw
ros2 topic hz /depth_stream_node/color/image_rect

# 内参（校正域，fx 取 K[0]）
ros2 topic echo /depth_stream_node/depth/camera_info --once

# 时间戳（单调、与系统时钟同域）
ros2 topic echo /depth_stream_node/depth/image_raw --once --field header.stamp
```

节点发布的话题：

| 话题 | 类型 | 格式 | 帧率 |
|---|---|---|---|
| `~/color/image_raw` | `sensor_msgs/Image` | rgb8 1920×1280 | 30 fps |
| `~/color/right/image_raw` | `sensor_msgs/Image` | rgb8 1920×1280 | 30 fps |
| `~/color/image_rect` | `sensor_msgs/Image` | rgb8 768×512（已校正） | 30 fps |
| `~/color/right/image_rect` | `sensor_msgs/Image` | rgb8 768×512（已校正） | 30 fps |
| `~/depth/image_raw` | `sensor_msgs/Image` | **32FC1 768×512 视差** | 10 fps |
| `~/color/camera_info` | `sensor_msgs/CameraInfo` | 1920×1280 源内参 | 30 fps |
| `~/depth/camera_info` | `sensor_msgs/CameraInfo` | 768×512 校正内参 | 10 fps |
| `~/color_rect/camera_info` | `sensor_msgs/CameraInfo` | 768×512 校正内参 | 30 fps |
| `~/color/right_rect/camera_info` | `sensor_msgs/CameraInfo` | 768×512 校正内参 | 30 fps |

`~/` 即 `/depth_stream_node/`。所有图像话题使用 `SensorDataQoS`（Best Effort、
Volatile、KeepLast depth=1），订阅端处理慢时会丢帧。

### 7. 深度数据语义

默认输出 `32FC1`，每个像素是**原始视差（像素）**，不是米：

```
z[m] = fx * baseline / disparity
```

- `fx`：`/depth_stream_node/depth/camera_info` 的 `K[0]`（当前配置 203.03）
- `baseline`：0.05955 m，写在 `sdk/config/depth_sdk_vpi.conf` 的 `calib.baseline_m`
- 无效值/无穷远通常为 0 或负值

需要 SDK 直接输出毫米深度（`16UC1`）时，把
`ros2/install/depth_sdk_ros/share/depth_sdk_ros/config/params.yaml` 里的
`depth_encoding` 改为 `16UC1`。

### 8. 在 C++ 程序中集成 SDK

```cmake
find_package(depth_sdk REQUIRED)
target_link_libraries(your_target PRIVATE depth_sdk::depth_sdk)
```

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/双目og02d10/sdk
```

运行时让动态库可被找到：

```bash
export LD_LIBRARY_PATH=/path/to/双目og02d10/sdk/lib:$LD_LIBRARY_PATH
```

完整说明见 [`sdk/README.md`](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/sdk/README.md)
与 [`ros2/README.md`](Jetson%20AGX%20Thor%20Devkit/GMSL/双目og02d10/ros2/README.md)。

---

## 常见问题

| 现象 | 处理 |
|---|---|
| `preflight.sh` 报内核 / L4T 不匹配 | 本包与 JetPack 7.0（L4T R39.2.1）绑定，升级 JetPack 后需重新获取对应版本 |
| 无 `/dev/video0/1` | 执行 `driver/install.sh` 后重启，再 `load_modules.sh` |
| `install.sh` 拒绝执行 | 先跑 `sudo ./install.sh --check` 看具体哪项版本不符 |
| `libdepth_sdk.so: cannot open shared object file` | 用 `start_depth_ros.sh` 启动，或手动 `export LD_LIBRARY_PATH=$PWD/sdk/lib` |
| `config_file` / 标定 / engine 找不到 | 用 `start_depth_ros.sh` 启动，脚本会自动改写路径 |
| TensorRT engine 反序列化失败 | engine 与 GPU/TensorRT 版本绑定，确认是 Thor + TensorRT 10.16 |
| 深度全 0 / 异常 | 确认 `stereo_calibration.json` 是本模组的；用 `sdk/bin/demo` 检查视差 |
| `ros2 topic hz` 低于 30/10 | Best Effort + depth=1 会丢帧，用 `--window 30` 多测几秒 |
| 相机打不开 | `/dev/video0/1` 被其它进程占用，先停 `uvdp_streamer`、`ZSViewer`、`demo` |

## 相关仓库

- [ZSViewer-delivery](https://github.com/zsibot-camera/ZSViewer-delivery) — 上位机 ZSViewer 独立交付仓库（Linux / Windows）
- [d-robotics-camera-drivers](https://github.com/zsibot-camera/d-robotics-camera-drivers) — D-Robotics RDK S600 / S100P 平台
- [.github](https://github.com/zsibot-camera/.github) — 组织展示页
