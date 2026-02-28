prepare-rootfs:
  sudo touch rootfs/etc/resolv.conf
  sudo mount --bind /etc/resolv.conf rootfs/etc/resolv.conf
  sudo install -m 755 ./init.sh rootfs/init
  sudo mkdir -p rootfs/mnt/app
  sudo umount rootfs/etc/resolv.conf
  scripts/make-app-disk.sh --index-js index.js --output ./app.ext4
  truncate -s 1G rootfs.ext4
  sudo mkfs.ext4 -d rootfs -F rootfs.ext4

run:
  scripts/create-microvm.sh \
    --kernel ./vmlinux \
    --rootfs ./rootfs.ext4 \
    --app-drive ./app.ext4 \
    --init /init


download:
  #!/bin/env bash
  ARCH="$(uname -m)"
  LIBC=glibc  # or musl

  # vmlinux を取得（xzで配布→展開して vmlinux にする）
  wget -q -O - "https://packages.bell-sw.com/alpaquita/${LIBC}/stream/releases/${ARCH}/alpaquita-microvm-vmlinux-stream-latest-${LIBC}-${ARCH}.xz" \
    | unxz > vmlinux

  # （ついでに rootfs も “latest” がある）
  mkdir -p rootfs
  wget -q -O - "https://packages.bell-sw.com/alpaquita/${LIBC}/stream/releases/${ARCH}/alpaquita-microvm-rootfs-stream-latest-${LIBC}-${ARCH}.tar.gz" \
    | sudo tar -C rootfs -xz
