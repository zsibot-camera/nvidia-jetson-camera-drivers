# depth_sdk — 双目深度算法 SDK

本目录提供**闭源二进制 SDK**：C++ 头文件 + 动态库 + TensorRT engine。
不含算法源码。

## 目录

```
sdk/
├── include/depth_sdk/       # 公共 API 头文件
├── lib/libdepth_sdk.so      # 动态库（VPI 4.1.4 构建）
├── lib/cmake/depth_sdk/     # find_package 配置
├── config/
│   ├── depth_sdk_vpi.conf   # 运行时配置（相机/标定/模型）
│   └── stereo_calibration.json  # 本模组标定（随货）
├── models/
│   └── las2_m_768x512_thor_fp16.engine  # Thor 专用 TensorRT plan
└── bin/demo                 # 命令行冒烟测试
```

## 依赖

| 组件 | 要求 |
|---|---|
| L4T / JetPack | R39.2.1 / 7.0 |
| VPI | 4.1.4（`/opt/nvidia/vpi4`，apt `libnvvpi4`/`vpi4-dev`） |
| TensorRT | 10.16（apt `libnvinfer10`） |
| CUDA | 13.2 |
| OpenCV | 4.8（core/imgproc/calib3d/imgcodecs） |

## 在自己的 CMake 项目中使用

```cmake
cmake_minimum_required(VERSION 3.16)
project(my_depth_app CXX)

find_package(depth_sdk REQUIRED)

add_executable(my_depth_app main.cpp)
target_link_libraries(my_depth_app PRIVATE depth_sdk::depth_sdk)
```

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/双目og02d10/sdk
cmake --build build
```

`find_package(depth_sdk)` 会自动导出：

- 头文件路径 `include/`
- `DEPTH_SDK_HAS_VPI=1` 编译定义
- 链接依赖（OpenCV、VPI、TensorRT、CUDA、NvBufSurface）

> **不要手工写 `-ldepth_sdk` 或只拷贝头文件**：`DEPTH_SDK_HAS_VPI` 决定
> `V4L2StereoSource` 类的内存布局，漏掉会导致堆损坏（`setVpiRectification`
> 崩溃）。必须走 `find_package`。

运行：

```bash
export LD_LIBRARY_PATH=/path/to/双目og02d10/sdk/lib:$LD_LIBRARY_PATH
```

## 头文件概览

| 头文件 | 内容 |
|---|---|
| `depth_sdk.hpp` | 顶层入口（创建 source / engine / stream） |
| `depth_stream.hpp` | `DepthStream` 状态机、回调、帧发布 |
| `depth_engine.hpp` | 深度引擎抽象（Stub / TensorRT） |
| `las_depth_engine.hpp` | LAS2-M TensorRT 引擎 |
| `v4l2_stereo_source.hpp` | V4L2 双目源 + VPI 校正 |
| `image_stereo_source.hpp` | 磁盘图片回放源 |
| `rectified_stereo_source.hpp` | 校正源包装 |
| `stereo_calibration.hpp` | 标定加载（内参/畸变/极线） |
| `config_file.hpp` | `key = value` 运行时配置解析 |
| `frame.hpp` / `buffer.hpp` / `types.hpp` | 帧/缓冲/基础类型 |

具体 API 以头文件注释为准。

## demo 冒烟测试

```bash
cd sdk
LD_LIBRARY_PATH=$PWD/lib ./bin/demo --config config/depth_sdk_vpi.conf
```

demo 会打开 `/dev/video0`、`/dev/video1`，跑 VPI 校正 + TensorRT 推理，并打印
帧率与深度统计。运行前确认没有其它进程占用相机。

## 运行时配置

`config/depth_sdk_vpi.conf`（`key = value` 格式）：

```ini
camera.uri            = v4l2:///dev/video0,/dev/video1
camera.width          = 1920
camera.height         = 1280
camera.fps            = 30
calib.fx              = 507.979
calib.fy              = 507.979
calib.cx              = 930.528
calib.cy              = 649.949
calib.baseline_m      = 0.05955
rectify.enabled       = true
rectify.backend       = vpi
rectify.output_width  = 768
rectify.output_height = 512
model.engine          = .../las2_m_768x512_thor_fp16.engine
model.max_fps         = 10
color.publish_rectified = true
```

- 修改后重启程序生效，无需重新编译。
- `calib.*` 按**源分辨率**（1920×1280）填写，输出尺寸的换算由 SDK 自动完成。
- `model.max_fps = 10` 是推荐值；写成 30 会与相机帧率同频抖动，实测掉到约 20fps。

## 深度输出

- 默认 `32FC1` 原始视差（像素），`z = fx * baseline / disparity`。
- `fx` 取对应帧的 `camera_info.K[0]`（校正域 203.03），`baseline` 为
  `calib.baseline_m`（0.05955 m）。
- 兼容的 `16UC1` 毫米深度由 SDK 内部换算（需帧内携带 fx/baseline）。
