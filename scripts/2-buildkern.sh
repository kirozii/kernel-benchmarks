#!/usr/bin/env bash
set -euo pipefail

VER="$1"
SRC="kernels/linux-$VER"
OUT="build/linux-$VER"

mkdir -p "$OUT"
cd "$SRC"
make O="../../$OUT" defconfig

# qemu opts thanks to mr gpt
scripts/config --file "../../$OUT/.config" \
        -e VIRTIO_PCI \
        -e VIRTIO_BLK \
        -e VIRTIO_NET \
        -e 9P_FS \
        -e NET_9P \
        -e NET_9P_VIRTIO \
        -e DEVTMPFS \
        -e DEVTMPFS_MOUNT \
        -e SERIAL_8250 \
        -e SERIAL_8250_CONSOLE

make O="../../$OUT" olddefconfig
make CC=gcc-11 HOSTCC=gcc-11 \
        O="../../$OUT" \
        -j"$(nproc)" \
        bzImage
