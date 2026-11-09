#!/bin/bash
# depth_sdk ROS2 节点启动脚本（Thor / ROS2 Jazzy）
# 用法：./start_depth_ros.sh [launch 参数...]
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /opt/ros/jazzy/setup.bash
source "$ROOT/ros2/install/setup.bash"
export DEPTH_SDK_CONFIG="${DEPTH_SDK_CONFIG:-$ROOT/sdk/config/depth_sdk_vpi.conf}"
export LD_LIBRARY_PATH="$ROOT/sdk/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec ros2 launch depth_sdk_ros depth_stream.launch.py "$@"
