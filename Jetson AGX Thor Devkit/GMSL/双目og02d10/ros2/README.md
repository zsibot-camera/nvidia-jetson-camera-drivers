# depth_sdk_ros — 预编译 ROS2 节点

本目录是 `depth_sdk_ros` 的**预编译安装树**（可执行 + launch + 参数），
不包含 ROS 包装层源码。

## 启动

推荐从包根目录启动（会同时设置动态库路径和配置文件路径）：

```bash
cd ..
./start_depth_ros.sh
```

`start_depth_ros.sh` 做的事：

```bash
source /opt/ros/jazzy/setup.bash
source <包根>/ros2/install/setup.bash
export DEPTH_SDK_CONFIG=<包根>/sdk/config/depth_sdk_vpi.conf
export LD_LIBRARY_PATH=<包根>/sdk/lib:$LD_LIBRARY_PATH
ros2 launch depth_sdk_ros depth_stream.launch.py
```

手动启动：

```bash
source /opt/ros/jazzy/setup.bash
source ros2/install/setup.bash
export DEPTH_SDK_CONFIG=$PWD/sdk/config/depth_sdk_vpi.conf
export LD_LIBRARY_PATH=$PWD/sdk/lib:$LD_LIBRARY_PATH
ros2 launch depth_sdk_ros depth_stream.launch.py
```

## 参数

参数文件：

```
ros2/install/depth_sdk_ros/share/depth_sdk_ros/config/params.yaml
```

关键参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `config_file` | `/home/nvidia/depth_sdk/config/depth_sdk_vpi.conf` | 运行时配置；被 `DEPTH_SDK_CONFIG` 覆盖 |
| `color_encoding` | `rgb8` | 必须与图像实际格式一致 |
| `depth_encoding` | `32FC1` | `32FC1` 视差 / `16UC1` 毫米 |
| `frame_id` | `camera` | 所有消息的 frame_id |
| `color_topic` / `depth_topic` | `~/color/image_raw`、`~/depth/image_raw` | 话题名（`~` 展开为 `/depth_stream_node`） |

`drop_while_busy`、`frame_queue_depth` 不是 ROS 参数，它们在
`sdk/config/depth_sdk_vpi.conf` 的 `stream.*` 段里。

命令行覆盖参数时直接运行节点（launch 文件没有声明 launch 参数）：

```bash
source /opt/ros/jazzy/setup.bash
source ros2/install/setup.bash
export LD_LIBRARY_PATH=$PWD/sdk/lib:$LD_LIBRARY_PATH
ros2 run depth_sdk_ros depth_stream_node --ros-args \
  --params-file ros2/install/depth_sdk_ros/share/depth_sdk_ros/config/params.yaml \
  -p config_file:=$PWD/sdk/config/depth_sdk_vpi.conf \
  -p depth_encoding:=16UC1
```

日常使用建议直接改 `params.yaml`，然后仍用 `start_depth_ros.sh` 启动。

> 注意：节点名固定为 `depth_stream_node`，所以话题前缀固定为
> `/depth_stream_node/...`。

## 话题

完整话题与帧率见包根 `README.md` 的表格。所有图像/内参使用 `SensorDataQoS`
（Best Effort、Volatile、KeepLast depth=1）。

`camera_info` 与图像必须成对使用：

- `color/image_raw` ↔ `color/camera_info`（1920×1280，含鱼眼畸变）
- `color/image_rect` ↔ `color_rect/camera_info`（768×512，已校正）
- `depth/image_raw` ↔ `depth/camera_info`（768×512，视差）

## 停止

前台运行按 `Ctrl-C`。后台运行时：

```bash
pkill -f "lib/depth_sdk_ros/depth_stream_nod[e]"
```

不要用 `pkill -f depth_stream_node`（可能匹配到命令行自身）。

## 注意

- 节点独占 `/dev/video0`、`/dev/video1`；启动前停掉 `uvdp_streamer`、`demo`
  等采集程序。
- 节点动态链接 `<包根>/sdk/lib/libdepth_sdk.so`，可执行里已写入相对 RPATH；
  用启动脚本最省事。
- 客户机需要 ROS2 Jazzy；JetPack 不自带，安装方法见 `docs/VERSION.md`。
