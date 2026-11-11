#!/usr/bin/env bash
# depth_sdk 一键安装 / 自检 / 卸载（Jetson AGX Thor，aarch64）。
#
#   sudo ./install.sh                    # 安装到 /opt/depth_sdk
#   sudo ./install.sh --prefix /opt/foo  # 自定义安装前缀
#   ./install.sh --check                 # 只检查环境，不写盘
#   sudo ./install.sh --uninstall        # 卸载
#
# 安装内容：头文件、libdepth_sdk.so、demo、配置、标定、TensorRT engine。
# 不修改内核、不加载/卸载任何驱动、不重启系统。
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/opt/depth_sdk"
MODE="install"

usage() {
    cat <<EOF
用法: $0 [--prefix DIR] [--check|--uninstall]

  --prefix DIR   安装目录，默认 /opt/depth_sdk
  --check        只做平台/依赖/包完整性检查，不写盘
  --uninstall    删除本脚本安装的前缀（只删除带安装标记的目录）
  -h, --help     显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="${2:?--prefix 需要参数}"; shift 2 ;;
        --check) MODE="check"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: 未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ "$PREFIX" = /* && "$PREFIX" != "/" ]] || {
    echo "ERROR: --prefix 必须是绝对路径且不能是 /" >&2
    exit 2
}
[[ "$PREFIX" != *" "* && "$PREFIX" != *"#"* && "$PREFIX" != *"&"* && "$PREFIX" != *"\\"* ]] || {
    echo "ERROR: --prefix 不能包含空格、#、& 或反斜杠" >&2
    exit 2
}

check_platform() {
    local errors=0
    echo "== 1. 平台 =="
    local arch
    arch="$(uname -m)"
    echo "架构: $arch"
    if [[ "$arch" == "aarch64" ]]; then
        echo "OK: aarch64"
    else
        echo "ERROR: 本包只支持 aarch64（Jetson AGX Thor），当前为 $arch"
        errors=$((errors + 1))
    fi

    if [[ -r /etc/nv_tegra_release ]]; then
        echo "L4T: $(head -n1 /etc/nv_tegra_release)"
        if grep -q 'R39' /etc/nv_tegra_release; then
            echo "OK: L4T R39.x（Thor）"
        else
            echo "WARN: 本包按 L4T R39.2.1 / JetPack 7.0 构建，当前 L4T 版本不同"
        fi
    else
        echo "WARN: 未找到 /etc/nv_tegra_release，请确认这是 Thor 板端"
    fi

    echo "== 2. 运行库 =="
    local lib
    for lib in libnvvpi.so libnvinfer.so libopencv_core.so; do
        if ldconfig -p 2>/dev/null | grep -q "$lib"; then
            echo "OK: $lib"
        else
            echo "ERROR: 未找到 $lib（需由 JetPack 提供）"
            errors=$((errors + 1))
        fi
    done

    echo "== 3. 包完整性 =="
    local path
    for path in \
        bin/demo \
        lib/libdepth_sdk.so \
        config/depth_sdk_vpi.conf \
        config/stereo_calibration.json \
        models/las2_m_768x512_thor_fp16.engine \
        include/depth_sdk/depth_sdk.hpp; do
        if [[ -e "$PKG_DIR/$path" ]]; then
            echo "OK: $path"
        else
            echo "ERROR: 缺少 $path"
            errors=$((errors + 1))
        fi
    done

    echo "== 4. 相机设备 =="
    local dev
    for dev in /dev/video0 /dev/video1; do
        if [[ -e "$dev" ]]; then
            echo "OK: $dev"
        else
            echo "WARN: $dev 不存在；先安装驱动并重启（见 ../driver/README.md）"
        fi
    done

    return "$errors"
}

if [[ "$MODE" == "check" ]]; then
    if check_platform; then
        echo "结果: 检查通过"
        exit 0
    fi
    echo "结果: 检查未通过，见上面的 ERROR" >&2
    exit 1
fi

if [[ "$MODE" == "uninstall" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: 卸载需要 root（sudo）" >&2
        exit 1
    fi
    if [[ ! -f "$PREFIX/.depth_sdk_installed" ]]; then
        echo "ERROR: $PREFIX 不是本脚本安装的目录（缺少 .depth_sdk_installed 标记），拒绝删除" >&2
        exit 1
    fi
    rm -rf -- "$PREFIX"
    rm -f /etc/profile.d/depth-sdk.sh /etc/ld.so.conf.d/depth-sdk.conf
    ldconfig
    echo "已卸载: $PREFIX"
    exit 0
fi

# ---- install ----
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: 安装需要 root（请用 sudo ./install.sh）" >&2
    exit 1
fi

if ! check_platform; then
    echo "ERROR: 环境检查未通过，中止安装；修好后重试，或先运行 --check 查看详情" >&2
    exit 1
fi

echo "== 5. 安装到 $PREFIX =="
install -d "$PREFIX"
for dir in include lib bin config models; do
    [[ -d "$PKG_DIR/$dir" ]] && cp -a "$PKG_DIR/$dir" "$PREFIX/"
done
[[ -d "$PKG_DIR/docs" ]] && cp -a "$PKG_DIR/docs" "$PREFIX/"
install -m 0644 "$PKG_DIR/README.md" "$PKG_DIR/AI-INSTALL.md" "$PREFIX/"
install -m 0755 "$PKG_DIR/install.sh" "$PREFIX/install.sh"

CONF="$PREFIX/config/depth_sdk_vpi.conf"
sed -i \
    -e "s#^rectify\.calibration_file *=.*#rectify.calibration_file = $PREFIX/config/stereo_calibration.json#" \
    -e "s#^model\.engine *=.*#model.engine = $PREFIX/models/las2_m_768x512_thor_fp16.engine#" \
    "$CONF"

cat > /etc/profile.d/depth-sdk.sh <<EOF
# depth_sdk (Jetson AGX Thor) —— 由 sdk/install.sh 生成
export DEPTH_SDK_ROOT="$PREFIX"
export LD_LIBRARY_PATH="\$DEPTH_SDK_ROOT/lib:\${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="\$DEPTH_SDK_ROOT:\${CMAKE_PREFIX_PATH:-}"
EOF
chmod 0644 /etc/profile.d/depth-sdk.sh

echo "$PREFIX/lib" > /etc/ld.so.conf.d/depth-sdk.conf
chmod 0644 /etc/ld.so.conf.d/depth-sdk.conf
ldconfig
touch "$PREFIX/.depth_sdk_installed"

echo "== 6. 动态库自检 =="
if LD_LIBRARY_PATH="$PREFIX/lib" ldd "$PREFIX/bin/demo" | grep -q 'not found'; then
    echo "ERROR: demo 仍有未解析的动态库：" >&2
    LD_LIBRARY_PATH="$PREFIX/lib" ldd "$PREFIX/bin/demo" | grep 'not found' >&2 || true
    exit 1
fi
echo "OK: demo 动态库全部解析"

cat <<EOF

安装完成。
  前缀:       $PREFIX
  配置:       $PREFIX/config/depth_sdk_vpi.conf
  标定:       $PREFIX/config/stereo_calibration.json（必须换成该模组随货标定）
  环境变量:   source /etc/profile.d/depth-sdk.sh
  冒烟测试:   sudo $PREFIX/bin/demo --config $PREFIX/config/depth_sdk_vpi.conf
  自检:       $PKG_DIR/install.sh --check

注意：/dev/video0、/dev/video1 是独占设备。运行 demo 前先停掉
uvdp_streamer、ROS 节点、ZSViewer 等占用相机的程序。
EOF
