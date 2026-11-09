#!/bin/bash
# depth_sdk ROS2 节点启动脚本（Thor / ROS2 Jazzy）
#
# 交付包里的 sdk/config/depth_sdk_vpi.conf 默认用 /home/nvidia/depth_sdk/...
# 的绝对路径。本脚本按当前包所在位置生成一份临时配置，改写标定文件与
# TensorRT engine 的路径，因此整个目录可以解压/克隆到任意位置运行。
#
# 用法：./start_depth_ros.sh [launch 参数...]
# 高级用法：DEPTH_SDK_CONFIG=/path/to/your.conf ./start_depth_ros.sh
#           （外部指定的配置原样使用，不再改写）
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 路径里若含 sed 的替换特殊字符（& | \），先转义
sed_escape() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

TMP_CONF=""
cleanup() {
    if [ -n "$TMP_CONF" ]; then
        rm -f "$TMP_CONF"
    fi
}
trap cleanup EXIT INT TERM

if [ -n "${DEPTH_SDK_CONFIG:-}" ]; then
    CONF="$DEPTH_SDK_CONFIG"
    if [ ! -r "$CONF" ]; then
        echo "DEPTH_SDK_CONFIG 指向的配置不存在或不可读: $CONF" >&2
        exit 1
    fi
else
    SRC_CONF="$ROOT/sdk/config/depth_sdk_vpi.conf"
    CALIB="$ROOT/sdk/config/stereo_calibration.json"
    ENGINE="$ROOT/sdk/models/las2_m_768x512_thor_fp16.engine"

    for f in "$SRC_CONF" "$CALIB" "$ENGINE"; do
        if [ ! -r "$f" ]; then
            echo "缺少交付包文件: $f" >&2
            echo "请确认在完整的 双目og02d10 目录下运行本脚本。" >&2
            exit 1
        fi
    done

    TMP_CONF="$(mktemp /tmp/depth_sdk_vpi.XXXXXX.conf)"
    sed -e "s|^[[:space:]]*rectify\.calibration_file[[:space:]]*=.*$|rectify.calibration_file = $(sed_escape "$CALIB")|" \
        -e "s|^[[:space:]]*model\.engine[[:space:]]*=.*$|model.engine = $(sed_escape "$ENGINE")|" \
        "$SRC_CONF" > "$TMP_CONF"

    CONF="$TMP_CONF"
fi

export DEPTH_SDK_CONFIG="$CONF"
export LD_LIBRARY_PATH="$ROOT/sdk/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# shellcheck disable=SC1091
source /opt/ros/jazzy/setup.bash
# shellcheck disable=SC1091
source "$ROOT/ros2/install/setup.bash"

# 不用 exec，保证退出时 trap 能清理临时配置
ros2 launch depth_sdk_ros depth_stream.launch.py "$@"
