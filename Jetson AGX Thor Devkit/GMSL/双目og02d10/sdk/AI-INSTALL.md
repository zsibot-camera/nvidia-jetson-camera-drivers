# depth_sdk 一键安装（给 AI 助手）

> 给 AI 助手：按顺序执行，不要跳步。每一步都有“预期输出”；输出不符时停在原地，
> 按第 6 节排障。不要重载/卸载内核模块，不要 `pkill -f depth_stream_node`，
> 不要改相机驱动，不要自动重启整机。

本包是 **Jetson AGX Thor** 的闭源双目深度 SDK：公开头文件 + `libdepth_sdk.so` +
`demo` + 配置 + 标定 + TensorRT engine。**不含算法源码**，不要把 Orin/其他模组的
engine 或标定拿来用。

---

## 1. 确认平台

```bash
uname -m
head -n1 /etc/nv_tegra_release
dpkg -l libnvinfer10 libnvvpi4 2>/dev/null | tail -n +6
```

预期：

- `uname -m` = `aarch64`
- L4T = `R39.2.1`（Thor / JetPack 7.0）
- TensorRT 10.16、VPI 4.1.4 已安装

任一不符：停止，换对应平台的包；不要强行安装。

## 2. 解包并自检

```bash
tar -xzf depth_sdk-0.1.0-thor-aarch64.tar.gz
cd depth_sdk-0.1.0
./install.sh --check
```

预期最后一行：`结果: 检查通过`。

`--check` 只读：不写 `/opt`、不加载驱动、不启动相机。

## 3. 安装

```bash
sudo ./install.sh
```

默认安装到 `/opt/depth_sdk`。自定义位置：

```bash
sudo ./install.sh --prefix /opt/my_depth_sdk
```

安装脚本会：

1. 复制 `include/ lib/ bin/ config/ models/`；
2. 把配置里的 `rectify.calibration_file`、`model.engine` 改成安装后的绝对路径；
3. 写 `/etc/profile.d/depth-sdk.sh` 与 `/etc/ld.so.conf.d/depth-sdk.conf`；
4. 用 `ldd` 检查 `demo` 没有 `not found`。

预期最后出现 `安装完成` 和 `OK: demo 动态库全部解析`。

## 4. 加载环境变量

当前 shell：

```bash
source /etc/profile.d/depth-sdk.sh
```

新开 shell 会自动加载。验证：

```bash
echo "$DEPTH_SDK_ROOT"
```

预期：`/opt/depth_sdk`（或你自定义的前缀）。

## 5. 冒烟测试

先确认相机没有被占用：

```bash
sudo fuser -v /dev/video0 /dev/video1 2>/dev/null || echo "camera free"
```

如果 `fuser` 列出了进程，先停掉**那个**进程（用准确 PID 或 `systemctl stop <服务名>`），
不要用 `pkill -f depth_stream_node`。

运行：

```bash
sudo /opt/depth_sdk/bin/demo --config /opt/depth_sdk/config/depth_sdk_vpi.conf
```

预期：

- 打开 `/dev/video0`、`/dev/video1`；
- VPI 校正 + TensorRT 推理启动；
- 周期性打印帧率与深度统计（深度约 10 fps，彩色约 30 fps）。

`Ctrl-C` 退出。demo 退出后相机释放。

## 6. 在客户程序中使用

```cmake
cmake_minimum_required(VERSION 3.16)
project(my_depth_app CXX)

find_package(depth_sdk REQUIRED)

add_executable(my_depth_app main.cpp)
target_link_libraries(my_depth_app PRIVATE depth_sdk::depth_sdk)
```

```bash
source /etc/profile.d/depth-sdk.sh
cmake -S . -B build
cmake --build build
```

不要手工写 `-ldepth_sdk` 或只拷贝头文件：`DEPTH_SDK_HAS_VPI` 会影响
`V4L2StereoSource` 的内存布局，必须通过 `find_package(depth_sdk)` 获取编译定义。

## 7. 标定与深度语义

- `config/stereo_calibration.json` 必须替换成**该相机模组随货的标定**。
  用错标定也能出图，但测距不准。
- 深度默认输出 `32FC1` 原始视差（单位：像素），换算：

  ```text
  z[m] = fx * baseline_m / disparity
  ```

- `fx` 取校正域内参（本模组约 203.03），`baseline_m` 为 `calib.baseline_m`
  （本模组约 0.05955 m）。
- 不要把视差当米；`F32_METERS` 不能承载视差语义。

## 8. 排障

| 现象 | 检查 / 处理 |
|---|---|
| `install.sh --check` 报架构错误 | 用了 Orin 或 x86 包；换 `*-thor-aarch64` |
| 缺 `libnvvpi.so` / `libnvinfer.so` | JetPack 不完整；先修 JetPack，不要手装随机版本 |
| `demo: error while loading shared libraries` | `source /etc/profile.d/depth-sdk.sh`；或 `sudo ldconfig` |
| 打不开 `/dev/video0/1` | 驱动未装或相机被占用；先看 `../driver/README.md` 和 `fuser` |
| TensorRT engine 反序列化失败 | engine 与 Thor GPU / TensorRT 10.16 绑定；不要用 Orin engine |
| 深度全 0 / 异常 | 标定不是本模组的；换随货 `stereo_calibration.json` |
| 帧率低 | 订阅端/显示端慢会丢帧；demo 只统计 SDK 输出 |
| 相机停帧 | 重启采集服务或整机；**不要**重载 `nv_max9295d`/`nv_max96712` |

## 9. 卸载

```bash
sudo /opt/depth_sdk/install.sh --uninstall
```

或回到解包目录执行 `sudo ./install.sh --uninstall`。

卸载只删除带 `.depth_sdk_installed` 标记的前缀和本脚本写的两个配置文件；
没有标记的目录会拒绝删除。

## 10. 相关文档

- `../README.md`：驱动、ROS2、完整 Thor 交付包
- `../driver/README.md`：内核驱动安装
- `../ros2/README.md`：ROS2 节点与话题
- `../docs/VERSION.md`：版本矩阵
