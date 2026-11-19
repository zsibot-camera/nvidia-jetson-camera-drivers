#!/usr/bin/env bash
# 回滚四目 OG02D10 驱动安装。
#
# 优先使用 install.sh 留下的 backup/pre-install/ 或 backup/<timestamp>/ 快照恢复
# serdes_core、nv_max96712、nv_max96717、nv_og02d10_single、dtbo 和 extlinux.conf；
# 没有快照时删除本包安装的文件，并从 OVERLAYS 行移除本包 overlay。
# 不加载/卸载任何模块。
#
# 恢复旧 serdes_core 后，依赖旧 ABI 的相机包（ISX031 / OG02B10 / 双目 OG02D10）
# 在重启后重新可用。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KVER_EXPECTED="6.8.12-1021-tegra"
DTBO_NAME="tegra264-p4071-camera-og02d10-quad-overlay.dtbo"
KOS=(serdes_core nv_max96712 nv_max96717 nv_og02d10_single)

MODDIR="/lib/modules/${KVER_EXPECTED}/updates"
MODDIR_I2C="${MODDIR}/drivers/media/i2c"
BOOT_DTBO="/boot/${DTBO_NAME}"
EXTLINUX="/boot/extlinux/extlinux.conf"

mod_path() {
    case "$1" in
        serdes_core | nv_max96712) echo "${MODDIR_I2C}/$1.ko" ;;
        *)                         echo "${MODDIR}/$1.ko" ;;
    esac
}

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "请用 sudo 运行"

BACKUP_ROOT="$SCRIPT_DIR/backup"
PRE_INSTALL_DIR="$BACKUP_ROOT/pre-install"
LATEST=""
if [ -f "$PRE_INSTALL_DIR/.snapshot" ]; then
    LATEST="$PRE_INSTALL_DIR"
elif [ -d "$BACKUP_ROOT" ]; then
    LATEST="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d |
        sort | tail -n 1 || true)"
fi

strip_overlay() {
    [ -f "$EXTLINUX" ] || {
        warn "找不到 $EXTLINUX，跳过启动项清理"
        return 0
    }

    python3 - "$EXTLINUX" "$DTBO_NAME" <<'PY'
import os
import sys

conf_path, dtbo_name = sys.argv[1:]
changed = False

with open(conf_path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

for i, line in enumerate(lines):
    stripped = line.strip()
    if not stripped.startswith("OVERLAYS "):
        continue
    tokens = stripped.split()
    kept = [
        token
        for token in tokens[1:]
        if token.rsplit("/", 1)[-1] != dtbo_name
    ]
    if len(kept) != len(tokens) - 1:
        changed = True
        if kept:
            indent = line[: len(line) - len(line.lstrip())]
            lines[i] = indent + "OVERLAYS " + " ".join(kept) + "\n"
        else:
            lines[i] = ""

if changed:
    tmp = conf_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.writelines(lines)
    os.replace(tmp, conf_path)
    print("[INFO] 已从 %s 移除 %s" % (conf_path, dtbo_name))
else:
    print("[INFO] %s 中未发现 %s" % (conf_path, dtbo_name))
PY
}

if [ -n "$LATEST" ]; then
    info "使用备份恢复: $LATEST"

    install -d "$MODDIR" "$MODDIR_I2C"
    for ko in "${KOS[@]}"; do
        dest="$(mod_path "$ko")"
        if [ -f "$LATEST/${ko}.ko" ]; then
            install -m 0644 "$LATEST/${ko}.ko" "$dest"
            info "恢复 $dest"
        else
            rm -f "$dest"
            info "删除 $dest（安装前不存在）"
        fi
    done

    if [ -f "$LATEST/${DTBO_NAME}" ]; then
        install -m 0644 "$LATEST/${DTBO_NAME}" "$BOOT_DTBO"
        info "恢复 $BOOT_DTBO"
    else
        rm -f "$BOOT_DTBO"
        info "删除 $BOOT_DTBO（安装前不存在）"
    fi

    if [ -f "$LATEST/extlinux.conf" ]; then
        install -D -m 0644 "$LATEST/extlinux.conf" "$EXTLINUX"
        info "恢复 $EXTLINUX"
    else
        strip_overlay
    fi
else
    warn "未找到 install.sh 备份，按默认路径删除；如改装过其他版本，请手工核对"
    for ko in "${KOS[@]}"; do
        dest="$(mod_path "$ko")"
        rm -f "$dest"
        info "删除 $dest"
    done
    rm -f "$BOOT_DTBO"
    info "删除 $BOOT_DTBO"
    strip_overlay
fi

depmod -a "$KVER_EXPECTED"
info "已执行 depmod -a ${KVER_EXPECTED}"

cat <<EOF

回滚完成。重启后生效：

  sudo reboot

注意：
  - 本脚本不会 rmmod/重载 nv_max96712、nv_max9295d，也不会触碰 serdes 驱动。
  - 若没有 pre-install 备份，serdes_core/nv_max96712 会被删除；需要换用其他
    相机包时请重新安装对应交付包。
EOF
