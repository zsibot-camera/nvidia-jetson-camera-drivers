#!/usr/bin/env bash
# 四目 ISX031 驱动安装脚本（Jetson AGX Thor Devkit）
#
# 安装内容：
#   - nv_max96717.ko / nv_isx031.ko  -> /lib/modules/<kver>/updates
#   - tegra264-p4071-camera-isx031-quad-overlay.dtbo -> /boot
#   - 将 ISX031 overlay 写入 /boot/extlinux/extlinux.conf 第一个 OVERLAYS 行
#
# 本脚本不会加载/卸载任何模块，也不会修改内核或系统自带 serdes_core、
# nv_max96712。安装完成后必须重启使 overlay 生效。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KVER_EXPECTED="6.8.12-1021-tegra"
L4T_EXPECTED="39.2.1"
DTBO_NAME="tegra264-p4071-camera-isx031-quad-overlay.dtbo"
KOS=(nv_max96717 nv_isx031)
CONFLICT_DTBOS=(
    "tegra264-p4071-camera-og02d10-dual-overlay.dtbo"
    "tegra264-p4071-camera-og02b10-quad-overlay.dtbo"
)

MODDIR="/lib/modules/${KVER_EXPECTED}/updates"
BOOT_DTBO="/boot/${DTBO_NAME}"
EXTLINUX="/boot/extlinux/extlinux.conf"

CHECK_ONLY=0
FORCE=0
EDIT_EXTLINUX=1
BACKUP_ROOT="$SCRIPT_DIR/backup"
PRE_INSTALL_DIR="$BACKUP_ROOT/pre-install"
BACKUP_DIR=""

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

usage() {
    cat <<EOF
用法: sudo $0 [选项]

  --check         只做环境、文件和依赖检查，不安装
  --force         跳过内核/L4T 版本检查（不推荐；模块仍与 ${KVER_EXPECTED} 绑定）
  --no-extlinux   只安装模块和 dtbo，不修改 extlinux.conf
  -h, --help      显示本帮助
EOF
}

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --force) FORCE=1 ;;
        --no-extlinux) EDIT_EXTLINUX=0 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "未知参数: $arg（--help 查看用法）" ;;
    esac
done

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "请用 sudo 运行"
}

check_files() {
    local ko
    for ko in "${KOS[@]}"; do
        [ -f "$SCRIPT_DIR/ko/${ko}.ko" ] || fail "缺少 driver/ko/${ko}.ko"
    done
    [ -f "$SCRIPT_DIR/dtb/${DTBO_NAME}" ] || fail "缺少 driver/dtb/${DTBO_NAME}"
    command -v depmod >/dev/null 2>&1 || fail "缺少 depmod"
    command -v modinfo >/dev/null 2>&1 || fail "缺少 modinfo"
    if [ "$EDIT_EXTLINUX" -eq 1 ]; then
        command -v python3 >/dev/null 2>&1 || fail "缺少 python3（用于修改 extlinux.conf）"
    fi
}

check_platform() {
    [ "$(uname -m)" = "aarch64" ] || fail "本包只支持 aarch64（当前 $(uname -m)）"

    if [ "$FORCE" -eq 1 ]; then
        warn "--force：跳过内核/L4T 版本检查"
        return 0
    fi

    [ "$(uname -r)" = "$KVER_EXPECTED" ] ||
        fail "内核不匹配：当前 $(uname -r)，需要 ${KVER_EXPECTED}（确认后可用 --force）"

    local l4t_ver
    l4t_ver="$(dpkg-query -W -f='${Version}' nvidia-l4t-core 2>/dev/null |
        cut -d- -f1 || true)"
    if [ -z "$l4t_ver" ]; then
        warn "无法读取 nvidia-l4t-core 版本，跳过 L4T 检查"
    else
        case "$l4t_ver" in
            "$L4T_EXPECTED"|"$L4T_EXPECTED".*) ;;
            *) fail "L4T 版本不匹配：当前 ${l4t_ver}，需要 ${L4T_EXPECTED}" ;;
        esac
    fi
}

check_deps() {
    local dep
    for dep in serdes_core nv_max96712; do
        modinfo "$dep" >/dev/null 2>&1 ||
            fail "缺少依赖模块 ${dep}；本包不覆盖系统自带 serdes_core/nv_max96712"
    done
}

backup_existing() {
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    local first=0
    if [ ! -e "$PRE_INSTALL_DIR/.snapshot" ]; then
        first=1
        mkdir -p "$PRE_INSTALL_DIR"
    fi

    local f
    for f in "$MODDIR/nv_isx031.ko" "$MODDIR/nv_max96717.ko" \
             "$BOOT_DTBO" "$EXTLINUX"; do
        if [ -e "$f" ]; then
            cp -a "$f" "$BACKUP_DIR/"
            if [ "$first" -eq 1 ]; then
                cp -a "$f" "$PRE_INSTALL_DIR/"
            fi
        fi
    done

    if [ "$first" -eq 1 ]; then
        touch "$PRE_INSTALL_DIR/.snapshot"
        info "首次安装前快照: $PRE_INSTALL_DIR"
    fi
    info "本次安装前备份: $BACKUP_DIR"
}

warn_duplicate_modules() {
    local ko p
    for ko in "${KOS[@]}"; do
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            [ "$p" = "$MODDIR/${ko}.ko" ] && continue
            warn "发现另一份 ${ko}.ko: $p（可能与新装模块重名，depmod 会告警）"
        done < <(find "/lib/modules/${KVER_EXPECTED}" -name "${ko}.ko" 2>/dev/null || true)
    done
}

install_files() {
    install -d "$MODDIR"
    local ko
    for ko in "${KOS[@]}"; do
        install -m 0644 "$SCRIPT_DIR/ko/${ko}.ko" "$MODDIR/${ko}.ko"
        info "已安装 $MODDIR/${ko}.ko"
    done
    install -m 0644 "$SCRIPT_DIR/dtb/${DTBO_NAME}" "$BOOT_DTBO"
    info "已安装 $BOOT_DTBO"
    depmod -a "$KVER_EXPECTED"
    info "已执行 depmod -a ${KVER_EXPECTED}"
}

edit_extlinux() {
    [ -f "$EXTLINUX" ] || fail "找不到 $EXTLINUX；如由外部管理启动项，请用 --no-extlinux"

    python3 - "$EXTLINUX" "$DTBO_NAME" "${CONFLICT_DTBOS[@]}" <<'PY'
import os
import sys

conf_path, dtbo_name, *conflicts = sys.argv[1:]
dtbo_path = "/boot/" + dtbo_name
target = dtbo_name
conflict_names = set(conflicts)

with open(conf_path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()


def basename(token):
    return token.rsplit("/", 1)[-1]


def indent_of(line):
    return line[: len(line) - len(line.lstrip())]


overlay_idx = [
    i for i, line in enumerate(lines) if line.strip().startswith("OVERLAYS ")
]
removed = []

if not overlay_idx:
    fdt_idx = next(
        (i for i, line in enumerate(lines) if line.strip().startswith("FDT ")), None
    )
    if fdt_idx is None:
        sys.exit("extlinux.conf 中没有 OVERLAYS 或 FDT 行，拒绝修改")
    lines.insert(fdt_idx + 1, "      OVERLAYS %s\n" % dtbo_path)
    changed = True
else:
    first = overlay_idx[0]
    line = lines[first]
    tokens = line.strip().split()
    kept = [tokens[0]]
    for token in tokens[1:]:
        name = basename(token)
        if name == target:
            continue
        if name in conflict_names:
            removed.append(token)
            continue
        kept.append(token)
    kept.append(dtbo_path)
    # 去重但保持顺序
    deduped = []
    for token in kept:
        if token not in deduped:
            deduped.append(token)
    lines[first] = indent_of(line) + " ".join(deduped) + "\n"
    changed = True
    if len(overlay_idx) > 1:
        print("[WARN] extlinux.conf 有多个 OVERLAYS 行，仅修改第一个（主启动项）")

if not changed:
    sys.exit("未修改 extlinux.conf")

tmp = conf_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.writelines(lines)
os.replace(tmp, conf_path)

for token in removed:
    print("[INFO] 已从主启动项移除冲突 overlay: %s" % token)
print("[INFO] 已写入 ISX031 overlay: %s" % dtbo_path)
PY
}

check_files
check_platform
check_deps

if [ "$CHECK_ONLY" -eq 1 ]; then
    info "检查通过：平台、文件、依赖均满足安装条件"
    info "未做任何修改。执行 sudo $0 进行安装。"
    exit 0
fi

require_root
backup_existing
warn_duplicate_modules
install_files

if [ "$EDIT_EXTLINUX" -eq 1 ]; then
    edit_extlinux
    info "已更新 $EXTLINUX（第一个 OVERLAYS 行）"
else
    cat <<EOF
[INFO] 未修改 extlinux.conf。请手工确认主启动项包含且仅包含：
      OVERLAYS /boot/${DTBO_NAME}
[INFO] 并移除 OG02D10/OG02B10 等使用同一 MAX96712 的相机 overlay。
EOF
fi

cat <<EOF

安装完成。overlay 需要重启后生效：

  sudo reboot

重启后加载并检查四路节点：

  sudo ${SCRIPT_DIR}/load_modules.sh

回滚：

  sudo ${SCRIPT_DIR}/uninstall.sh

注意：不要 rmmod/重载 nv_max96712 或 nv_max9295d，也不要 sysfs unbind/rebind。
EOF
