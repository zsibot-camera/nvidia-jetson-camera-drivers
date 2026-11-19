#!/usr/bin/env bash
# 四目 OG02B10 驱动包预检（只读，不修改系统）。
#
# 用法:
#   ./preflight.sh           普通预检，WARN 不影响退出码
#   ./preflight.sh --strict  WARN 也视为失败
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$SCRIPT_DIR"

KVER_EXPECTED="6.8.12-1021-tegra"
L4T_EXPECTED="39.2.1"
DTBO_NAME="tegra264-p4071-camera-og02b10-quad-overlay.dtbo"
KOS=(nv_og02b10 nv_max96717)
EXTLINUX="/boot/extlinux/extlinux.conf"

FAILED=0
WARNED=0
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

pass() { echo "  [PASS] $*"; }
warn() { echo "  [WARN] $*"; }
fail() { echo "  [FAIL] $*"; FAILED=$((FAILED + 1)); }

echo "=== 平台 ==="
if [ "$(uname -m)" = "aarch64" ]; then
    pass "架构 aarch64"
else
    fail "架构不是 aarch64（当前 $(uname -m)）"
fi

if [ "$(uname -r)" = "$KVER_EXPECTED" ]; then
    pass "内核 $KVER_EXPECTED"
else
    fail "内核 $(uname -r) != $KVER_EXPECTED"
fi

L4T_VER="$(dpkg-query -W -f='${Version}' nvidia-l4t-core 2>/dev/null |
    cut -d- -f1 || true)"
if [ -z "$L4T_VER" ]; then
    warn "无法读取 nvidia-l4t-core 版本"
elif [ "$L4T_VER" = "$L4T_EXPECTED" ] || [[ "$L4T_VER" == "$L4T_EXPECTED".* ]]; then
    pass "L4T R$L4T_VER"
else
    fail "L4T $L4T_VER != $L4T_EXPECTED"
fi

echo
echo "=== 包文件 ==="
for ko in "${KOS[@]}"; do
    f="$PKG_DIR/driver/ko/${ko}.ko"
    if [ -f "$f" ]; then
        pass "存在 driver/ko/${ko}.ko"
    else
        fail "缺少 driver/ko/${ko}.ko"
    fi
done
if [ -f "$PKG_DIR/driver/dtb/$DTBO_NAME" ]; then
    pass "存在 driver/dtb/$DTBO_NAME"
else
    fail "缺少 driver/dtb/$DTBO_NAME"
fi

echo
echo "=== 内核模块绑定 ==="
if command -v modinfo >/dev/null 2>&1; then
    for ko in "${KOS[@]}"; do
        f="$PKG_DIR/driver/ko/${ko}.ko"
        [ -f "$f" ] || continue
        vm="$(modinfo -F vermagic "$f" 2>/dev/null || true)"
        case "$vm" in
            "$KVER_EXPECTED "*) pass "${ko}.ko vermagic 匹配" ;;
            "") warn "无法读取 ${ko}.ko vermagic" ;;
            *) fail "${ko}.ko vermagic 不匹配: $vm" ;;
        esac
    done
else
    warn "缺少 modinfo，跳过 vermagic 检查"
fi

echo
echo "=== 依赖模块 ==="
if command -v modinfo >/dev/null 2>&1; then
    for dep in serdes_core nv_max96712; do
        if modinfo "$dep" >/dev/null 2>&1; then
            pass "依赖 $dep 可用"
        else
            fail "缺少依赖 $dep（本包不附带）"
        fi
    done
else
    warn "缺少 modinfo，跳过依赖检查"
fi

echo
echo "=== 启动项 ==="
if [ -f "$EXTLINUX" ]; then
    if grep -q "isx031-quad-overlay\|og02d10-dual-overlay" "$EXTLINUX"; then
        warn "extlinux.conf 仍含 ISX031/OG02D10 相机 overlay；install.sh 会替换"
    else
        pass "未发现其他相机 overlay"
    fi
    if grep -q "$DTBO_NAME" "$EXTLINUX"; then
        pass "extlinux.conf 已启用 OG02B10 overlay"
    else
        warn "extlinux.conf 尚未启用 OG02B10 overlay（安装并重启后生效）"
    fi
else
    warn "找不到 $EXTLINUX"
fi

echo
echo "=== 运行态（可选） ==="
if [ -e /dev/video0 ]; then
    COUNT=0
    for name_file in /sys/class/video4linux/video*/name; do
        [ -e "$name_file" ] || continue
        if grep -q "og02b10" "$name_file"; then
            COUNT=$((COUNT + 1))
        fi
    done
    if [ "$COUNT" -ge 4 ]; then
        pass "发现 $COUNT 个 og02b10 视频节点"
    else
        warn "只发现 $COUNT 个 og02b10 视频节点（需要 4 个）"
    fi

    if command -v v4l2-ctl >/dev/null 2>&1; then
        fmt="$(v4l2-ctl -d /dev/video0 --get-fmt-video 2>/dev/null || true)"
        if [[ "$fmt" == *"1600"* && "$fmt" == *"1301"* && "$fmt" == *"YUYV"* ]]; then
            pass "/dev/video0 格式 1600x1301 YUYV"
        else
            warn "/dev/video0 格式不是预期的 1600x1301 YUYV"
        fi
    fi

    if command -v fuser >/dev/null 2>&1; then
        busy="$(fuser /dev/video0 /dev/video1 /dev/video2 /dev/video3 2>/dev/null || true)"
        if [ -n "$busy" ]; then
            warn "视频节点被占用（PID: $busy），取流前请先释放"
        else
            pass "视频节点未被占用"
        fi
    fi
else
    warn "尚无 /dev/video0；若尚未安装/重启，属正常"
fi

if lsmod 2>/dev/null | grep -Eq '^nv_isx031|^nv_og02d10'; then
    warn "已加载 ISX031/OG02D10 模块；重启后应只保留 OG02B10 拓扑"
fi

echo
if [ "$FAILED" -gt 0 ]; then
    echo "预检失败: $FAILED 项 FAIL, $WARNED 项 WARN"
    exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$WARNED" -gt 0 ]; then
    echo "严格模式失败: $WARNED 项 WARN"
    exit 1
fi
echo "预检通过: 0 项 FAIL, $WARNED 项 WARN"
exit 0
