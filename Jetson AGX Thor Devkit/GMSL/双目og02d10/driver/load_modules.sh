#!/bin/bash
# 加载双 OG02D10 相机驱动并检查视频节点。
# 通常在 install.sh 之后、重启完成时执行一次即可；系统 udev 也会按设备树
# compatible 自动加载这些模块，本脚本用于手动确认/排障。
set -e

MODULES=(serdes_core nv_max9295d nv_max96712 nv_og02d10)

for m in "${MODULES[@]}"; do
  if ! modprobe "$m"; then
    echo "[load] modprobe $m 失败，请检查：dmesg | tail -50" >&2
    exit 1
  fi
done

# 等待 ISP/VI 节点就绪（最多 10 秒）
for _ in $(seq 1 10); do
  if [ -e /dev/video0 ] && [ -e /dev/video1 ]; then
    break
  fi
  sleep 1
done

echo "已加载模块："
lsmod | grep -E '^(serdes_core|nv_max9295d|nv_max96712|nv_og02d10)[[:space:]]' || true
echo
echo "视频节点："
for f in /sys/class/video4linux/video*/name; do
  [ -e "$f" ] || continue
  dev="/dev/$(basename "$(dirname "$f")")"
  echo "  $dev: $(cat "$f")"
done

echo
if [ -e /dev/video0 ] && [ -e /dev/video1 ]; then
  echo "相机节点已就绪：/dev/video0 (12-0030, VC1) / /dev/video1 (12-0020, VC0)"
  exit 0
fi
echo "未检测到 /dev/video0 与 /dev/video1，请检查硬件连接与 dmesg。" >&2
exit 1
