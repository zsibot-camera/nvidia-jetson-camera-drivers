#!/bin/bash
# 交付包环境预检 —— Jetson AGX Thor / JetPack 7.0 (L4T R39.2.1)
#
# 用法：./preflight.sh [--strict]
#   --strict 将 WARN 也视为失败（默认 WARN 不影响退出码）
#
# 退出码：0 = 无致命问题；1 = 存在 FAIL（或 --strict 下的 WARN）

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER_EXPECTED="6.8.12-1021-tegra"
L4T_EXPECTED="R39.2.1"
TRT_EXPECTED="10.16"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

FAIL=0
WARN=0
ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; WARN=$((WARN + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "== 智身科技 Thor 双目 OG02D10 交付包预检 =="
echo "包路径: $ROOT"
echo

# ---------------------------------------------------------------
# 硬件 / 系统
# ---------------------------------------------------------------
echo "[系统]"

ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ]; then
    ok "架构 $ARCH"
else
    fail "架构 $ARCH，本包仅适用于 aarch64（Jetson Thor）"
fi

if [ -r /etc/nv_tegra_release ]; then
    L4T_LINE="$(head -n 1 /etc/nv_tegra_release)"
    case "$L4T_LINE" in
        *"$L4T_EXPECTED"*) ok "L4T $L4T_EXPECTED（$L4T_LINE）" ;;
        *) fail "L4T 版本不符: $L4T_LINE（期望 $L4T_EXPECTED）" ;;
    esac
else
    fail "未找到 /etc/nv_tegra_release，无法确认 L4T 版本"
fi

KREL="$(uname -r)"
if [ "$KREL" = "$KVER_EXPECTED" ]; then
    ok "内核 $KREL"
else
    fail "内核 $KREL，期望 $KVER_EXPECTED（.ko vermagic 不匹配会拒载）"
fi

# ---------------------------------------------------------------
# 软件依赖
# ---------------------------------------------------------------
echo
echo "[软件依赖]"

if [ -f /opt/ros/jazzy/setup.bash ]; then
    ok "ROS2 Jazzy（/opt/ros/jazzy）"
else
    fail "未安装 ROS2 Jazzy（缺少 /opt/ros/jazzy/setup.bash）"
fi

VPI_LIB="/opt/nvidia/vpi4/lib/aarch64-linux-gnu/libnvvpi.so.4"
if [ -e "$VPI_LIB" ]; then
    ok "VPI 4（$VPI_LIB）"
elif [ -d /opt/nvidia/vpi4 ]; then
    warn "已找到 /opt/nvidia/vpi4，但缺少 $VPI_LIB"
else
    fail "未找到 VPI 4（/opt/nvidia/vpi4），JetPack 7.0 应自带"
fi

TRT_VER=""
if command -v dpkg-query >/dev/null 2>&1; then
    TRT_VER="$(dpkg-query -W -f='${Version}' libnvinfer10 2>/dev/null || true)"
    [ -z "$TRT_VER" ] && TRT_VER="$(dpkg-query -W -f='${Version}' nvinfer 2>/dev/null || true)"
    TRT_VER="${TRT_VER%%-*}"
fi
if [ -n "$TRT_VER" ]; then
    case "$TRT_VER" in
        "$TRT_EXPECTED"*) ok "TensorRT $TRT_VER" ;;
        *) warn "TensorRT $TRT_VER，期望 $TRT_EXPECTED.x（engine 可能反序列化失败）" ;;
    esac
else
    warn "未能确定 TensorRT 版本（未找到 libnvinfer10/nvinfer 包记录）"
fi

CUDA_VER=""
if command -v nvcc >/dev/null 2>&1; then
    CUDA_VER="$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' | head -n 1)"
elif [ -r /usr/local/cuda/version.json ]; then
    CUDA_VER="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' /usr/local/cuda/version.json 2>/dev/null \
        | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
if [ -n "$CUDA_VER" ]; then
    case "$CUDA_VER" in
        13.2*) ok "CUDA $CUDA_VER" ;;
        13.*)  warn "CUDA $CUDA_VER，期望 13.2.x" ;;
        *)     warn "CUDA $CUDA_VER，期望 13.2.x" ;;
    esac
else
    warn "未能确定 CUDA 版本（未找到 nvcc 或 /usr/local/cuda/version.json）"
fi

if command -v ldconfig >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -q 'libopencv_core\.so\.408'; then
    ok "OpenCV 4.8 运行库（libopencv_core.so.408）"
else
    fail "缺少 libopencv_core.so.408（libdepth_sdk.so 依赖 OpenCV 4.8）"
fi

# ---------------------------------------------------------------
# 交付包完整性
# ---------------------------------------------------------------
echo
echo "[交付包文件]"

REQUIRED=(
    "driver/install.sh"
    "driver/load_modules.sh"
    "driver/ko/serdes_core.ko"
    "driver/ko/nv_max9295d.ko"
    "driver/ko/nv_max96712.ko"
    "driver/ko/nv_og02d10.ko"
    "driver/dtb/tegra264-p4071-camera-og02d10-dual-overlay.dtbo"
    "sdk/lib/libdepth_sdk.so"
    "sdk/config/depth_sdk_vpi.conf"
    "sdk/config/stereo_calibration.json"
    "sdk/models/las2_m_768x512_thor_fp16.engine"
    "ros2/install/setup.bash"
    "start_depth_ros.sh"
)

MISSING=()
for rel in "${REQUIRED[@]}"; do
    [ -e "$ROOT/$rel" ] || MISSING+=("$rel")
done
if [ "${#MISSING[@]}" -eq 0 ]; then
    ok "全部 ${#REQUIRED[@]} 个必需文件存在"
else
    fail "缺少 ${#MISSING[@]} 个文件: ${MISSING[*]}"
fi

if [ -f "$ROOT/sdk/lib/libdepth_sdk.so" ] && [ "$ARCH" = "aarch64" ]; then
    MISSING_LIBS="$(LD_LIBRARY_PATH="$ROOT/sdk/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        ldd "$ROOT/sdk/lib/libdepth_sdk.so" 2>/dev/null | awk '/not found/ {print $1}' | tr '\n' ' ')"
    if [ -z "$MISSING_LIBS" ]; then
        ok "libdepth_sdk.so 动态依赖全部可解析"
    else
        fail "libdepth_sdk.so 缺少动态库: $MISSING_LIBS"
    fi
fi

# ---------------------------------------------------------------
# 相机设备（安装驱动前不存在是正常的）
# ---------------------------------------------------------------
echo
echo "[相机设备]"

VIDEO_OK=1
for dev in /dev/video0 /dev/video1; do
    if [ -e "$dev" ]; then
        ok "$dev 存在"
    else
        warn "$dev 不存在（若尚未安装驱动/重启，可忽略）"
        VIDEO_OK=0
    fi
done

if [ "$VIDEO_OK" -eq 1 ] && command -v fuser >/dev/null 2>&1; then
    BUSY="$(fuser /dev/video0 /dev/video1 2>&1 | tr -d '\n' | sed 's/^[[:space:]]*//')"
    if [ -n "$BUSY" ]; then
        warn "相机正被进程占用: $BUSY（启动 ROS 节点前需先停止）"
    else
        ok "相机未被其它进程占用"
    fi
fi

# ---------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
    if [ "$WARN" -gt 0 ]; then
        echo "预检通过，$WARN 项警告。"
        if [ "$STRICT" -eq 1 ]; then
            echo "--strict 模式：警告视为失败。"
            exit 1
        fi
    else
        echo "预检通过，未发现问题。"
    fi
    exit 0
else
    echo "预检失败：$FAIL 项不满足，$WARN 项警告。"
    exit 1
fi
