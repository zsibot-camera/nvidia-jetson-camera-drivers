# AI 一键安装指南（Thor 相机 / 深度 SDK / ZSViewer）

> **给 AI 助手**：这是本仓库的机器可读入口。按顺序执行；每一步都有“预期输出”。
> 输出不符时停在原地，按第 6 节排障，不要猜、不要跳步、不要自动重启整机。
>
> 硬性禁止：
> - 不要重载 / 卸载 `nv_max9295d`、`nv_max96712`，不要 sysfs unbind/rebind；
> - 不要 `pkill -f depth_stream_node`（会误杀 bridge）；用准确 PID 或 systemd 服务名；
> - 不要跨平台混用 Orin / Thor 的包、TensorRT engine、标定；
> - 不要在日志/命令里写入密码、token；
> - 需要 `sudo reboot` 时先告诉用户，让用户确认。

本仓库面向 **Jetson AGX Thor Devkit + GMSL 双目 OG02D10**。
其他平台（Orin、RV1126B）请使用对应仓库/交付包。

---

## 1. 先选场景

| 你要做什么 | 目标机 | 用哪个包 |
|---|---|---|
| 在 Thor 上跑深度 SDK / 写 C++ | Thor 板端 | `depth_sdk-0.1.0-thor-aarch64.tar.gz` |
| 在 Thor 上跑 ROS2 深度节点 | Thor 板端 | 直接 clone 本仓库，按 `双目og02d10/README.md` 装 driver + ROS |
| 在 Linux 上位机看图像/点云/录像 | Ubuntu 22.04+ x86_64 | `ZSViewer-2.1.0-amd64.deb` 或 AppImage（独立仓库） |
| 在 Windows 上位机看图像/点云/录像 | Windows 10/11 x64 | `ZSViewer-2.1.0-windows-x64-setup.exe`（独立仓库） |
| 只想快速验证相机出流 | Thor 板端 | `depth_sdk-0.1.0-thor-aarch64.tar.gz` 里的 `demo` |

下载页：

- SDK：<https://github.com/zsibot-camera/nvidia-jetson-camera-drivers/releases/tag/thor-depth-sdk-v0.1.0>
- ZSViewer（独立交付仓库）：<https://github.com/zsibot-camera/ZSViewer-delivery/releases/tag/v2.1.0>

## 2. 确认目标机

```bash
uname -m
head -n1 /etc/nv_tegra_release 2>/dev/null || true
cat /etc/os-release | head -n3
```

预期：

| 目标 | `uname -m` | 系统 |
|---|---|---|
| Thor 板端 | `aarch64` | L4T `R39.2.1` / Ubuntu 24.04 |
| Linux 上位机 | `x86_64` | Ubuntu 22.04+ |
| Windows 上位机 | — | Windows 10/11 x64 |

架构不符时停止，不要继续安装。

## 3. 下载并校验

以 SDK 为例（版本号按实际资产替换）：

```bash
mkdir -p ~/zs-download && cd ~/zs-download
BASE=https://github.com/zsibot-camera/nvidia-jetson-camera-drivers/releases/download
curl -fLO "$BASE/thor-depth-sdk-v0.1.0/depth_sdk-0.1.0-thor-aarch64.tar.gz"
curl -fLO "$BASE/thor-depth-sdk-v0.1.0/SHA256SUMS"
sha256sum -c SHA256SUMS
```

预期：`depth_sdk-0.1.0-thor-aarch64.tar.gz: OK`。

ZSViewer 使用独立交付仓库：

```bash
BASE=https://github.com/zsibot-camera/ZSViewer-delivery/releases/download/v2.1.0
curl -fLO "$BASE/ZSViewer-2.1.0-amd64.deb"
curl -fLO "$BASE/SHA256SUMS"
sha256sum -c SHA256SUMS --ignore-missing
```

也可以直接运行该仓库的 `install.sh` 自动检测系统、下载、校验并安装依赖。

## 4. 安装

### 4.1 Thor 深度 SDK

```bash
tar -xzf depth_sdk-0.1.0-thor-aarch64.tar.gz
cd depth_sdk-0.1.0
./install.sh --check          # 只检查，不写盘
sudo ./install.sh             # 安装到 /opt/depth_sdk
source /etc/profile.d/depth-sdk.sh
```

预期：

- 自检最后一行 `结果: 检查通过`；
- 安装最后出现 `安装完成` 与 `OK: demo 动态库全部解析`。

详细步骤（含标定、CMake 集成、深度语义）见包内 `AI-INSTALL.md`。

### 4.2 Linux 上位机 ZSViewer

Debian/Ubuntu（推荐，自动装依赖）：

```bash
sudo apt install ./ZSViewer-2.1.0-amd64.deb
zsviewer-cli --version
```

预期：`ZSViewer 2.1.0`。

AppImage（免安装）：

```bash
chmod +x ZSViewer-2.1.0-linux-x86_64.AppImage
./ZSViewer-2.1.0-linux-x86_64.AppImage --version
```

如果提示 FUSE 不可用：

```bash
./ZSViewer-2.1.0-linux-x86_64.AppImage --appimage-extract-and-run
```

tar.gz（绿色部署）：

```bash
tar -xzf ZSViewer-2.1.0-linux-x86_64.tar.gz
./ZSViewer/ZSViewer --install-desktop   # 可选：装到 ~/.local/bin + 桌面菜单
./ZSViewer/ZSViewer
```

### 4.3 Windows 上位机 ZSViewer

安装版：双击 `ZSViewer-2.1.0-windows-x64-setup.exe`，按向导完成（普通用户权限即可）。

便携版：解压 `ZSViewer-2.1.0-windows-x64-portable.zip`，运行 `ZSViewer\ZSViewer.exe`。
数据写在 exe 旁 `data\`，不写系统目录。

命令行验证：

```powershell
.\ZSViewer\zsviewer-cli.exe --version
```

预期：`ZSViewer 2.1.0`。

### 4.4 Thor 驱动 + ROS2（可选）

需要内核驱动和 ROS2 节点时，不要用 SDK 压缩包，直接 clone 本仓库：

```bash
git clone https://github.com/zsibot-camera/nvidia-jetson-camera-drivers.git
cd "nvidia-jetson-camera-drivers/Jetson AGX Thor Devkit/GMSL/双目og02d10"
chmod +x preflight.sh start_depth_ros.sh
./preflight.sh
cd driver && sudo ./install.sh --check && sudo ./install.sh
```

`driver/install.sh` 会提示是否需要重启；**由用户决定并执行重启**。
重启后：

```bash
cd .. && sudo driver/load_modules.sh
ls -l /dev/video0 /dev/video1
./start_depth_ros.sh
```

预期：`/dev/video0`、`/dev/video1` 存在；ROS2 节点发布
`~/color/image_rect`（1920×1280，板端 VIC 校正）与 `~/depth/image_raw`
（768×512，32FC1 视差，约 10 fps）。

## 5. 连接与验证

### 5.1 ZSViewer 连接 Thor

Thor 默认地址 `192.168.55.1`（USB/网络按现场实际）：

```bash
zsviewer --src auto --host 192.168.55.1
# 或 AppImage / tar.gz 的可执行文件
```

预期界面出现：

- 彩色：1920×1280，已由板端 VIC 校正（工具不做二次去畸变）；
- 深度：768×512；
- 点云、帧率、时间戳正常刷新。

无界面冒烟（可选）：

```bash
zsviewer-cli --src auto --host 192.168.55.1 --no-gui --snapshot /tmp/zs.png
```

### 5.2 SDK demo

```bash
sudo fuser -v /dev/video0 /dev/video1 2>/dev/null || echo "camera free"
sudo /opt/depth_sdk/bin/demo --config /opt/depth_sdk/config/depth_sdk_vpi.conf
```

预期：打印彩色/深度帧率与深度统计；`Ctrl-C` 退出。

### 5.3 ROS2

```bash
source /opt/ros/jazzy/setup.bash
ros2 topic hz /depth_stream_node/color/image_rect
ros2 topic hz /depth_stream_node/depth/image_raw
```

预期：彩色约 30 Hz，深度约 10 Hz。

## 6. 排障

| 现象 | 先检查 | 处理 |
|---|---|---|
| `sha256sum -c` 失败 | 下载是否完整 | 删除重下；不要使用校验失败的包 |
| SDK 自检报架构错误 | `uname -m` | 换 Thor aarch64 包；Orin/x86 包不能混用 |
| 缺 `libnvvpi.so` / `libnvinfer.so` | `dpkg -l libnvvpi4 libnvinfer10` | JetPack 不完整；先修 JetPack，不要手装随机版本 |
| `demo` 报 `error while loading shared libraries` | `ldd /opt/depth_sdk/bin/demo` | `source /etc/profile.d/depth-sdk.sh`；`sudo ldconfig` |
| 打不开 `/dev/video0/1` | `fuser -v /dev/video0 /dev/video1` | 相机被占用：用准确 PID 停掉占用进程，或停 systemd 服务 |
| 单路相机停帧 | 服务日志 | 重启采集服务/整机；**不要**重载 serdes 驱动 |
| TensorRT engine 反序列化失败 | engine 来源 | 必须用 Thor + TensorRT 10.16 的 engine；Orin engine 不可用 |
| 深度全 0 / 尺度不对 | 标定文件来源 | 换成本模组随货 `stereo_calibration.json`；确认 `baseline_m`≈0.05955 |
| ZSViewer 黑屏/图像不动 | 板端是否出流 | 先看板端帧计数/ROS 话题；不要为此改板端 VPI 后端 |
| ZSViewer 连不上 | IP/端口 | 默认 UVDP TCP 9600；确认板和上位机同网段、防火墙放行 |
| 深度值像“米”但差 10 倍 | 单位 | `F32_DISPARITY` 是像素视差；`z = fx * baseline / disparity` |

## 7. 版本与兼容

| 组件 | 版本 |
|---|---|
| Thor 交付包 | JetPack 7.0 / L4T R39.2.1 / TensorRT 10.16 / VPI 4.1.4 |
| depth_sdk | 0.1.0 |
| ZSViewer | 2.1.0 |
| UVDP | v2（TCP 9600） |

升级 JetPack 后，`.ko`、TensorRT engine、SDK 二进制都要重新出对应版本；
不要只升级系统而保留旧驱动/engine。

## 8. 机器可读清单

- `delivery-manifest.json`：包名、平台、下载地址、SHA256、安装入口。
- `Jetson AGX Thor Devkit/GMSL/双目og02d10/sdk/AI-INSTALL.md`：SDK 详细安装。
- `Jetson AGX Thor Devkit/GMSL/双目og02d10/README.md`：驱动 + SDK + ROS2 完整流程。
- ZSViewer 的机器可读说明与 `install.sh` 在独立仓库
  [ZSViewer-delivery](https://github.com/zsibot-camera/ZSViewer-delivery)。
