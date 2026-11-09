#!/bin/bash
# ============================================================================
# Jetson AGX Thor · 双 OG02D10 (GMSL2) 相机驱动安装脚本
#
# 适用环境：L4T R39.2.1 (JetPack 7.0)，内核 6.8.12-1021-tegra
# 用法：sudo ./install.sh [--check] [--force]
#   --check   只做版本/文件检查，不写入任何文件
#   --force   跳过 L4T/内核版本检查（不建议）
# ============================================================================
set -euo pipefail

KVER_EXPECTED="6.8.12-1021-tegra"
L4T_EXPECTED="39.2.1"
DTBO_NAME="tegra264-p4071-camera-og02d10-dual-overlay.dtbo"
KOS=(serdes_core nv_max9295d nv_max96712 nv_og02d10)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="$(uname -r)"
MODDIR="/lib/modules/${KVER}/updates/drivers/media/i2c"
BOOT_DTBO="/boot/${DTBO_NAME}"
EXTLINUX="/boot/extlinux/extlinux.conf"

CHECK_ONLY=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

say()  { echo "[install] $*"; }
fail() { echo "[install] 错误: $*" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  fail "请用 sudo 运行"
fi

if [ "$FORCE" -eq 0 ]; then
  if [ "$KVER" != "$KVER_EXPECTED" ]; then
    fail "内核版本不匹配：当前 $KVER，需要 $KVER_EXPECTED（L4T R39.2.1）。"
  fi
  L4T_VER="$(dpkg-query -W -f='${Version}' nvidia-l4t-core 2>/dev/null | cut -d- -f1 || true)"
  if [ "$L4T_VER" != "$L4T_EXPECTED" ]; then
    fail "L4T 版本不匹配：当前 ${L4T_VER:-未知}，需要 $L4T_EXPECTED。"
  fi
else
  say "已加 --force，跳过版本检查"
fi

# ---------- 文件检查 ----------
for k in "${KOS[@]}"; do
  [ -f "$SCRIPT_DIR/ko/$k.ko" ] || fail "缺少驱动文件 ko/$k.ko"
done
[ -f "$SCRIPT_DIR/dtb/$DTBO_NAME" ] || fail "缺少设备树 dtb/$DTBO_NAME"
[ -f "$EXTLINUX" ] || fail "找不到 $EXTLINUX（不是标准 L4T 启动方式？）"

if [ "$CHECK_ONLY" -eq 1 ]; then
  say "检查通过：内核 $KVER，L4T ${L4T_VER:-未知}，驱动文件齐全"
  exit 0
fi

# ---------- 备份 ----------
BACKUP_DIR="$SCRIPT_DIR/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for k in "${KOS[@]}"; do
  if [ -f "$MODDIR/$k.ko" ]; then
    cp -a "$MODDIR/$k.ko" "$BACKUP_DIR/"
  fi
done
if [ -f "$BOOT_DTBO" ]; then
  cp -a "$BOOT_DTBO" "$BACKUP_DIR/"
fi
cp -a "$EXTLINUX" "$BACKUP_DIR/extlinux.conf"
say "原文件已备份到 $BACKUP_DIR"

# ---------- 安装内核模块 ----------
install -d "$MODDIR"
install -m 644 "$SCRIPT_DIR"/ko/*.ko "$MODDIR/"
say "已安装 4 个内核模块到 $MODDIR"

# ---------- 安装设备树 ----------
install -m 644 "$SCRIPT_DIR/dtb/$DTBO_NAME" "$BOOT_DTBO"
say "已安装设备树 $BOOT_DTBO"

# ---------- 更新 extlinux OVERLAYS（幂等） ----------
python3 - "$EXTLINUX" "/boot/$DTBO_NAME" <<'PY'
import sys

conf, dtbo = sys.argv[1], sys.argv[2]
lines = open(conf).read().splitlines()
overlays = [(i, l) for i, l in enumerate(lines) if l.strip().startswith('OVERLAYS ')]

if any(dtbo in l for _, l in overlays):
    print('[install] extlinux 已包含该 overlay，跳过')
elif overlays:
    i = overlays[0][0]
    lines[i] = lines[i].rstrip() + ' ' + dtbo
    open(conf, 'w').write('\n'.join(lines) + '\n')
    print('[install] 已把 overlay 追加到现有 OVERLAYS 行')
else:
    for i, l in enumerate(lines):
        if l.strip().startswith('FDT '):
            lines.insert(i + 1, '      OVERLAYS ' + dtbo)
            open(conf, 'w').write('\n'.join(lines) + '\n')
            print('[install] 已在 FDT 行后插入 OVERLAYS')
            break
    else:
        sys.exit('找不到 FDT 行，无法写入 OVERLAYS')
PY

depmod -a "$KVER"
say "depmod 完成"

echo
echo "安装完成。请执行 sudo reboot 重启，然后运行："
echo "  sudo ./load_modules.sh"
echo "确认 /dev/video0、/dev/video1 出现。"
echo
echo "回滚：sudo ./uninstall.sh"
