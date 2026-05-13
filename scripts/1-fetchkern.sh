#!/bin/bash
set -euo pipefail

VER="$1"
MAJOR=${VER:0:1}
URL="https://www.kernel.org/pub/linux/kernel/v$MAJOR.x/linux-$VER.tar.xz"

mkdir -p kernels
if [ -d "kernels/linux-$VER" ]; then
        echo "======================== Retrieved kernel version $VER ========================"
        exit 0
fi

if [ -d "kernels/linux-$VER.tar.xz" ]; then
        tar -C kernels -xf "kernels/linux-$VER.tar.xz"
        echo "======================== Retrieved kernel version $VER ========================"
        exit 0
fi

echo "======================== Fetching kernel version $VER ========================"
wget -O "kernels/linux-$VER.tar.xz" "$URL"
tar -C kernels -xf "kernels/linux-$VER.tar.xz"
echo "======================== Retrieved kernel version $VER ========================"
