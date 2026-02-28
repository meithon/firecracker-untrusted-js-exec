#!/bin/sh
set -eu
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev 2>/dev/null || true
# Wait briefly for the secondary virtio block device to appear.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -b /dev/vdb ] && break
  sleep 0.1
done
mount -t ext4 -o ro /dev/vdb /mnt/app
node /mnt/app/index.js
# PID 1 must not exit; keep the VM alive after the one-shot command.
while :; do
  sleep 3600
done
