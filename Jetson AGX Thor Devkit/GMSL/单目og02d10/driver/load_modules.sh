#!/usr/bin/env bash
# 加载四目 OG02D10 相机栈并检查节点。
#
# 只 modprobe 缺失的模块；不会卸载任何模块，也不会触碰 serdes 驱动。
set -euo pipefail

MODULES=(serdes_core nv_max96712 nv_max96717 nv_og02d10_single)
WAIT_SECONDS=15
NODE_MATCH="og02d10sgl"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "请用 sudo 运行"

for mod in "${MODULES[@]}"; do
    if lsmod | awk '{print $1}' | grep -qx "$mod"; then
        info "已加载: $mod"
    else
        info "加载: $mod"
        modprobe "$mod" || fail "modprobe $mod 失败"
    fi
done

if dmesg 2>/dev/null | grep -q "disagrees about version of symbol serdes_"; then
    fail "serdes_core 与相机模块 CRC 不一致：用本包 install.sh 四件同批重装后重启"
fi

for other in nv_og02d10 nv_og02b10 nv_isx031; do
    if lsmod | awk '{print $1}' | grep -qx "$other"; then
        warn "$other 已加载：与本包共用 MAX96712，需重启并只保留一种相机 overlay"
    fi
done

deadline=$((SECONDS + WAIT_SECONDS))
count=0
while [ "$SECONDS" -lt "$deadline" ]; do
    count=0
    for name_file in /sys/class/video4linux/video*/name; do
        [ -e "$name_file" ] || continue
        if grep -q "$NODE_MATCH" "$name_file"; then
            count=$((count + 1))
        fi
    done
    [ "$count" -ge 4 ] && break
    sleep 0.5
done

echo
info "video4linux 节点:"
ls -l /dev/video* 2>/dev/null || true

echo
info "节点名称:"
for name_file in /sys/class/video4linux/video*/name; do
    [ -e "$name_file" ] || continue
    printf '  %s: %s\n' "${name_file%/name}" "$(cat "$name_file")"
done

if [ "$count" -lt 4 ]; then
    echo
    echo "最近相机内核日志:"
    dmesg 2>/dev/null |
        grep -Ei 'og02d10|max96717|max96712|nvcsi|vi capture|camera' |
        tail -n 40 || true
    fail "只找到 ${count} 个 ${NODE_MATCH} 视频节点（需要 4 个）。检查 overlay、GMSL 链路和模组供电"
fi

info "找到 ${count} 个 ${NODE_MATCH} 视频节点"

if command -v v4l2-ctl >/dev/null 2>&1; then
    echo
    info "视频格式:"
    for dev in /dev/video0 /dev/video1 /dev/video2 /dev/video3; do
        [ -e "$dev" ] || continue
        echo "--- $dev ---"
        v4l2-ctl -d "$dev" --get-fmt-video 2>&1 | sed -n '1,12p'
    done
else
    warn "未安装 v4l2-ctl，跳过格式检查"
fi

echo
info "四路节点就绪。节点映射以 media-ctl -p / dmesg 的 vc=N 为准，不要按节点编号假定相机字母。"
