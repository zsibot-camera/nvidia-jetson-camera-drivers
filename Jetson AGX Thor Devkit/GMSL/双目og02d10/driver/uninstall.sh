#!/bin/bash
# ============================================================================
# 双 OG02D10 相机驱动卸载脚本
#   - 若 install.sh 留下了 backup/<时间戳>/，从最近一次备份恢复原文件
#   - 否则删除安装的 .ko / .dtbo，并从 extlinux OVERLAYS 中移除对应条目
# 用法：sudo ./uninstall.sh
# ============================================================================
set -euo pipefail

DTBO_NAME="tegra264-p4071-camera-og02d10-dual-overlay.dtbo"
KOS=(serdes_core nv_max9295d nv_max96712 nv_og02d10)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="$(uname -r)"
MODDIR="/lib/modules/${KVER}/updates/drivers/media/i2c"
BOOT_DTBO="/boot/${DTBO_NAME}"
EXTLINUX="/boot/extlinux/extlinux.conf"

say()  { echo "[uninstall] $*"; }
fail() { echo "[uninstall] 错误: $*" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  fail "请用 sudo 运行"
fi

# 尽力卸载模块（相机进程占用时可能失败，重启后自然失效）
for m in nv_og02d10 nv_max96712 nv_max9295d serdes_core; do
  modprobe -r "$m" 2>/dev/null || true
done

BACKUP_DIR="$(ls -d "$SCRIPT_DIR"/backup/*/ 2>/dev/null | sort | tail -n 1 || true)"

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
  for k in "${KOS[@]}"; do
    if [ -f "$BACKUP_DIR/$k.ko" ]; then
      install -m 644 "$BACKUP_DIR/$k.ko" "$MODDIR/"
    fi
  done
  if [ -f "$BACKUP_DIR/$DTBO_NAME" ]; then
    install -m 644 "$BACKUP_DIR/$DTBO_NAME" "$BOOT_DTBO"
  fi
  if [ -f "$BACKUP_DIR/extlinux.conf" ]; then
    cp -a "$BACKUP_DIR/extlinux.conf" "$EXTLINUX"
  fi
  say "已从 $BACKUP_DIR 恢复原文件"
else
  say "未找到备份，删除已安装文件"
  rm -f "$MODDIR/serdes_core.ko" "$MODDIR/nv_max9295d.ko" \
        "$MODDIR/nv_max96712.ko" "$MODDIR/nv_og02d10.ko"
  rm -f "$BOOT_DTBO"

  python3 - "$EXTLINUX" "/boot/$DTBO_NAME" <<'PY'
import sys

conf, dtbo = sys.argv[1], sys.argv[2]
lines = open(conf).read().splitlines()
out = []
changed = False
for l in lines:
    if l.strip().startswith('OVERLAYS ') and dtbo in l.split():
        toks = [t for t in l.split() if t != dtbo]
        changed = True
        if len(toks) > 1:
            indent = l[:len(l) - len(l.lstrip())]
            out.append(indent + ' '.join(toks))
        # 只剩 OVERLAYS 关键字时整行删除
    else:
        out.append(l)
if changed:
    open(conf, 'w').write('\n'.join(out) + '\n')
    print('[uninstall] 已从 extlinux OVERLAYS 移除该条目')
else:
    print('[uninstall] extlinux 中没有该 overlay，跳过')
PY
fi

depmod -a "$KVER"
say "depmod 完成，重启后生效"
