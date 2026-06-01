#!/bin/bash
set -euo pipefail

VER="$1"
MAJOR=${VER:0:1}
ARCHIVE_VER="$VER"
if [[ "$VER" =~ ^([0-9]+\.[0-9]+)\.0$ ]]; then
        ARCHIVE_VER="${BASH_REMATCH[1]}"
fi
URL="https://www.kernel.org/pub/linux/kernel/v$MAJOR.x/linux-$ARCHIVE_VER.tar.xz"

mkdir -p kernels
if [ -d "kernels/linux-$VER" ]; then
        echo "======================== Retrieved kernel version $VER ========================"
        exit 0
fi

extract_tarball() {
        tar -C kernels -xf "$1"
}

normalize_source_dir() {
        local extracted_dir="kernels/linux-$ARCHIVE_VER"
        local expected_dir="kernels/linux-$VER"

        if [ "$ARCHIVE_VER" != "$VER" ] && [ -d "$extracted_dir" ] && [ ! -d "$expected_dir" ]; then
                mv "$extracted_dir" "$expected_dir"
        fi
}

if [ -f "kernels/linux-$VER.tar.xz" ]; then
        if extract_tarball "kernels/linux-$VER.tar.xz"; then
                normalize_source_dir
                echo "======================== Retrieved kernel version $VER ========================"
                exit 0
        fi
        rm -f "kernels/linux-$VER.tar.xz"
fi

echo "======================== Fetching kernel version $VER ========================"
wget -O "kernels/linux-$VER.tar.xz" "$URL"
extract_tarball "kernels/linux-$VER.tar.xz"
normalize_source_dir
echo "======================== Retrieved kernel version $VER ========================"
