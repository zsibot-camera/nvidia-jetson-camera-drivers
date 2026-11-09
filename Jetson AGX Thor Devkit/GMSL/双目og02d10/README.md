# Thor 双 OG02D10 深度相机 SDK

Jetson AGX Thor 上的双目深度相机交付包：相机驱动（二进制）、深度 SDK
（头文件 + 动态库 + TensorRT 模型）、ROS2 预编译节点。

不含任何算法/C++ 源码。ROS2 节点以可执行文件形式提供。

## 目录结构

```
双目og02d10/
├── driver/                  # 相机驱动（二进制 .ko + .dtbo + 安装脚本）
├── sdk/                     # 深度 SDK
│   ├── include/depth_sdk/   # C++ API 头文件
│   ├── lib/libdepth_sdk.so  # 动态库
│   ├── lib/cmake/depth_sdk/ # find_package(depth_sdk) 配置
│   ├── config/              # 运行时配置 + 标定
│   ├── models/              # TensorRT engine（Thor 专用）
│   └── bin/demo             # 命令行冒烟测试程序
├── ros2/                    # ROS2 预编译节点
├── start_depth_ros.sh       # 一键启动 ROS2 深度节点
├── docs/VERSION.md          # 版本矩阵与依赖
└── checksums.txt            # 文件校验和
```

## 系统要求

| 项 | 版本 |
|---|---|
| 平台 | Jetson AGX Thor Devkit（P4071 + P3834-0008） |
| JetPack | 7.0（L4T **R39.2.1**） |
| 内核 | 6.8.12-1021-tegra |
| ROS2 | **Jazzy**（Ubuntu 24.04 Noble） |
| VPI | 4.1.4（`/opt/nvidia/vpi4`，JetPack 自带） |
| TensorRT | 10.16.2（JetPack 自带） |
| CUDA | 13.2（JetPack 自带） |

> 版本不匹配会导致 `.ko` 拒载或 TensorRT engine 反序列化失败，详见
> `docs/VERSION.md`。

## 快速开始

### 1. 安装相机驱动

```bash
cd driver
sudo ./install.sh          # 先 sudo ./install.sh --check 预检
sudo reboot
sudo ./load_modules.sh     # 应看到 /dev/video0、/dev/video1
```

详见 `driver/README.md`。

### 2. 放入本模组的标定文件

`stereo_calibration.json` **按相机模组个体标定**，随货提供。请用本机模组对应的
文件覆盖：

```bash
cp <本模组标定>/stereo_calibration.json sdk/config/stereo_calibration.json
```

如果拿错标定，深度仍能出图，但测距精度不保证。

### 3. 启动 ROS2 深度节点

```bash
# 确保没有其他进程占用相机
sudo fuser -v /dev/video0 /dev/video1

./start_depth_ros.sh
```

节点启动后发布：

| 话题 | 类型 | 格式 | 帧率 |
|---|---|---|---|
| `/depth_stream_node/color/image_raw` | `sensor_msgs/Image` | rgb8 1920×1280 | 30 fps |
| `/depth_stream_node/color/right/image_raw` | `sensor_msgs/Image` | rgb8 1920×1280 | 30 fps |
| `/depth_stream_node/color/image_rect` | `sensor_msgs/Image` | rgb8 768×512（已校正） | 30 fps |
| `/depth_stream_node/color/right/image_rect` | `sensor_msgs/Image` | rgb8 768×512（已校正） | 30 fps |
| `/depth_stream_node/depth/image_raw` | `sensor_msgs/Image` | **32FC1 768×512 视差** | 10 fps |
| `/depth_stream_node/color/camera_info` | `sensor_msgs/CameraInfo` | 1920×1280 源内参 | 30 fps |
| `/depth_stream_node/depth/camera_info` | `sensor_msgs/CameraInfo` | 768×512 校正内参 | 10 fps |
| `/depth_stream_node/color_rect/camera_info` | `sensor_msgs/CameraInfo` | 768×512 校正内参 | 30 fps |
| `/depth_stream_node/color/right_rect/camera_info` | `sensor_msgs/CameraInfo` | 768×512 校正内参 | 30 fps |

所有图像话题使用 `SensorDataQoS`（Best Effort、Volatile、KeepLast depth=1）。
订阅端处理慢时会丢帧，这是设计行为；后端应保证回调足够快，或用独立线程。

### 4. 验证

```bash
# 帧率
ros2 topic hz /depth_stream_node/depth/image_raw
ros2 topic hz /depth_stream_node/color/image_rect

# 时间戳（单调、与系统时钟同域）
ros2 topic echo /depth_stream_node/depth/image_raw --once --field header.stamp

# 内参
ros2 topic echo /depth_stream_node/depth/camera_info --once
```

## 深度数据语义（重要）

默认输出 `32FC1`，每个像素是**原始视差（像素）**，不是米：

```
z[m] = fx * baseline / disparity
```

- `fx`：取 `/depth_stream_node/depth/camera_info` 的 `K[0]`（当前配置为 203.03）
- `baseline`：0.05955 m（写在 `sdk/config/depth_sdk_vpi.conf` 的
  `calib.baseline_m`；`camera_info` 的 `P` 矩阵不含 baseline）
- `disparity`：深度图像素值；无效值/无穷远通常为 0 或负值

如果需要 SDK 直接输出毫米深度（`16UC1`），把
`ros2/install/depth_sdk_ros/share/depth_sdk_ros/config/params.yaml` 里的
`depth_encoding` 改为 `16UC1`。

相机内参有两套，别混用：

| 话题 | 分辨率 | 说明 |
|---|---|---|
| `~/color/camera_info` | 1920×1280 | 源分辨率，含鱼眼畸变 `D` |
| `~/color_rect/camera_info` | 768×512 | 去畸变 + 极线校正后，与 depth 同域 |
| `~/depth/camera_info` | 768×512 | 模型输入域，与 `depth/image_raw` 配套 |

## 在 C++ 程序中集成 SDK

```cmake
find_package(depth_sdk REQUIRED)
target_link_libraries(your_target PRIVATE depth_sdk::depth_sdk)
```

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/双目og02d10/sdk
```

`DEPTH_SDK_HAS_VPI=1` 由 CMake 配置自动导出，不要手工 `-ldepth_sdk`——静态库
与 VPI 版本必须使用同一套编译定义，否则类布局不一致会导致堆损坏。

运行时需要能找到动态库：

```bash
export LD_LIBRARY_PATH=/path/to/双目og02d10/sdk/lib:$LD_LIBRARY_PATH
```

简单冒烟测试：

```bash
cd sdk
LD_LIBRARY_PATH=$PWD/lib ./bin/demo --config config/depth_sdk_vpi.conf
```

## 配置

`sdk/config/depth_sdk_vpi.conf` 是相机/标定/模型的唯一配置源（demo 与 ROS 节点共用）：

```ini
camera.uri           = v4l2:///dev/video0,/dev/video1
camera.width         = 1920
camera.height        = 1280
camera.fps           = 30
calib.fx             = 507.979
calib.baseline_m     = 0.05955
rectify.backend      = vpi
rectify.output_width = 768
rectify.output_height= 512
model.engine         = .../las2_m_768x512_thor_fp16.engine
model.max_fps        = 10
color.publish_rectified = true
```

修改后重启节点即可生效，不需要重新编译。

## 相机独占

`/dev/video0`、`/dev/video1` 不能被两个进程同时打开。运行 ROS 节点前，先停掉
`uvdp_streamer`、`demo`、`ZSViewer` 等其它采集程序；反之亦然。

## 常见问题

| 现象 | 处理 |
|---|---|
| `start_depth_ros.sh` 报 `config_file` 找不到 | 用脚本启动（脚本会设置 `DEPTH_SDK_CONFIG` 指向 `sdk/config/depth_sdk_vpi.conf`） |
| 无 `/dev/video0/1` | 先按 `driver/README.md` 安装驱动并重启 |
| `libdepth_sdk.so: cannot open shared object file` | 用 `start_depth_ros.sh`，或手动 `export LD_LIBRARY_PATH=$PWD/sdk/lib` |
| TensorRT 报 engine 反序列化失败 | engine 与 GPU/TensorRT 版本绑定，确认是 Thor + TensorRT 10.16 |
| `ros2 topic hz` 低于 30/10 | 订阅端慢导致 Best Effort 丢帧；用 `--window 30` 多测几秒 |
| 深度全 0/异常 | 检查标定文件是否为本模组；用 `demo` 看视差是否正常 |

## 版本与升级

- 本包所有二进制与 **L4T R39.2.1 / JetPack 7.0** 绑定。
- 客户升级 JetPack 后，`.ko`（vermagic）与 TensorRT engine 都需要重新提供，
  请联系供应商获取对应版本。
- 详细版本见 `docs/VERSION.md`。
