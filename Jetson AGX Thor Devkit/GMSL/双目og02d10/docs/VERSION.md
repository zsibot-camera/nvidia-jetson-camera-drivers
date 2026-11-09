# 版本矩阵与兼容性

本交付包为**二进制包**，所有产物与下列环境严格绑定。

## 目标平台

| 项 | 值 |
|---|---|
| 硬件 | Jetson AGX Thor Devkit |
| 模块型号 | P4071-0000 + P3834-0008 |
| 载板 | 双 OG02D10 GMSL2（J20 接口） |
| 机型串 | `3834-400-0008-H.1-1-1-jetson-agx-thor-devkit` |

## 软件版本

| 组件 | 版本 | 检查命令 |
|---|---|---|
| JetPack | 7.0 | — |
| L4T | **R39.2.1**（`39.2.1-20260806224157`） | `dpkg -l nvidia-l4t-core` |
| 内核 | **6.8.12-1021-tegra** | `uname -r` |
| Ubuntu | 24.04 Noble | `lsb_release -a` |
| CUDA | 13.2 | `nvcc --version` |
| TensorRT | 10.16.2.10 | `dpkg -l libnvinfer10` |
| VPI | 4.1.4（`/opt/nvidia/vpi4`） | `dpkg -l libnvvpi4` |
| OpenCV | 4.8（`libopencv_*.so.408`） | `dpkg -l libopencv-core408` |
| ROS2 | Jazzy | `/opt/ros/jazzy/setup.bash` |

## 二进制产物与绑定关系

| 产物 | 绑定对象 | 不匹配的后果 |
|---|---|---|
| `driver/ko/*.ko` | 内核 `6.8.12-1021-tegra` + `modversions` | `Invalid module format`，模块拒载 |
| `driver/dtb/*.dtbo` | L4T R39.2.1 的 `kernel_tegra264-p4071-0000+p3834-0008-nv.dtb` | 启动无相机节点，或 dtbo 应用失败 |
| `sdk/lib/libdepth_sdk.so` | VPI 4.1.4、TensorRT 10.16、CUDA 13.2、OpenCV 4.8 | 加载失败或运行时符号错误 |
| `sdk/models/*.engine` | Thor GPU + TensorRT 10.16 | engine 反序列化失败 |
| `ros2/install/...` | ROS2 Jazzy + 上面的 `.so` | 节点起不来 / 找不到库 |

## 交付内容校验

```bash
sha256sum -c checksums.txt
```

## 依赖包（客户机应已由 JetPack 提供）

```
libnvvpi4, vpi4-dev
libnvinfer10, libnvinfer-dev
libopencv-core408, libopencv-imgproc408, libopencv-calib3d408
nvidia-l4t-camera, nvidia-l4t-core
ros-jazzy-ros-base（客户自行安装 ROS2 Jazzy）
```

ROS2 Jazzy 安装（Ubuntu 24.04）：

```bash
sudo apt install software-properties-common
sudo add-apt-repository universe
sudo apt update && sudo apt install curl -y
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu noble main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt update
sudo apt install ros-jazzy-ros-base
```

## 升级约束

1. **不要只升级内核或 JetPack 而保留旧驱动**：`.ko` 的 vermagic 会不匹配。
2. **不要跨机型使用 `las2_m_768x512_thor_fp16.engine`**：TensorRT plan 与 GPU
   型号绑定，Orin 上的 plan 不能拿到 Thor 用（反之亦然）。
3. 换用新的相机模组时，必须更新该模组的 `stereo_calibration.json`。
4. 若客户需要自定义分辨率/帧率，优先改 `sdk/config/depth_sdk_vpi.conf`，
   不改二进制。
