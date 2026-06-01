#!/usr/bin/env bash
set -euo pipefail

VER="$1"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SRC="kernels/linux-$VER"
OUT="build/linux-$VER"

select_docker_image() {
        local major minor
        IFS=. read -r major minor _ <<<"$VER"

        case "$major" in
                5)
                        echo "kbuild-v5:local"
                        ;;
                6)
                        echo "kbuild-v6:local"
                        ;;
                7)
                        echo "kbuild-v7:local"
                        ;;
                *)
                        echo "unsupported kernel major version: $major" >&2
                        exit 1
                        ;;
        esac
}

select_compiler() {
        local major
        IFS=. read -r major _ <<<"$VER"

        case "$major" in
                5) echo "gcc-9" ;;
                6) echo "gcc-12" ;;
                7) echo "gcc-12" ;;
                *)
                        echo "unsupported kernel major version: $major" >&2
                        exit 1
                        ;;
        esac
}

build_flag_args() {
        local major
        IFS=. read -r major _ <<<"$VER"

        case "$major" in
                5)
                        printf '%s\n' \
                                'KCFLAGS=-fcf-protection=none' \
                                'HOSTCFLAGS=-fcf-protection=none' \
                                'HOSTCXXFLAGS=-fcf-protection=none'
                        ;;
        esac
}

ensure_docker_image() {
        local image=$1
        local dockerfile=$2

        if ! docker image inspect "$image" >/dev/null 2>&1; then
                echo "======================== Building Docker image $image ========================"
                docker build -t "$image" -f "$dockerfile" "$REPO_ROOT"
        fi
}

if [[ "${INSIDE_DOCKER_BUILD:-0}" != "1" ]]; then
        image=$(select_docker_image)
        dockerfile="$SCRIPT_DIR/docker/${image%%:*}.Dockerfile"
        compiler=$(select_compiler)

        [[ -f "$dockerfile" ]] || {
                echo "missing Dockerfile: $dockerfile" >&2
                exit 1
        }

        ensure_docker_image "$image" "$dockerfile"

        echo "======================== Building kernel version $VER inside $image ========================"
        exec docker run --rm \
                --user "$(id -u):$(id -g)" \
                -e INSIDE_DOCKER_BUILD=1 \
                -e BUILD_CC="$compiler" \
                -v "$REPO_ROOT:/work" \
                -w /work/scripts \
                "$image" \
                bash -lc "./2-buildkern.sh '$VER'"
fi

rm -rf "$OUT"
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
make_args=(
        "CC=${BUILD_CC:-gcc}"
        "HOSTCC=${BUILD_CC:-gcc}"
        "O=../../$OUT"
        "-j$(nproc)"
        "bzImage"
)

while IFS= read -r flag; do
        [[ -n "$flag" ]] || continue
        make_args+=("$flag")
done < <(build_flag_args)

make "${make_args[@]}"
