#!/usr/bin/env bash
set -euo pipefail

usage() {
        cat <<EOF
usage: $0 <kernel-version>

Creates a fresh qcow overlay for vm469, boots QEMU with the specified kernel,
runs LEBench over the serial console, copies the CSV result to the host, then
shuts the VM down and deletes the overlay.
EOF
}

if (( $# != 1 )); then
        usage
        exit 1
fi

VER="$1"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

KERNEL_IMAGE="$SCRIPT_DIR/build/linux-$VER/arch/x86/boot/bzImage"
BASE_IMAGE="$REPO_ROOT/rootfs/vm469.qcow2"
RUN_DIR="$REPO_ROOT/run/$VER"
RESULTS_DIR="$REPO_ROOT/results"
OVERLAY_IMAGE="$RUN_DIR/vm469-$VER.qcow2"
SERIAL_SOCKET="/tmp/kernel-bench-$VER-$$.sock"
SERIAL_LOG="$RUN_DIR/serial.log"
QEMU_LOG="$RUN_DIR/qemu.log"
RESULT_FILE="$RESULTS_DIR/output.$VER.csv"

LOGIN_USER="user469"
LOGIN_PASSWORD_PRIMARY="password"
LOGIN_PASSWORD_USED=""
VM_HOSTNAME="csc469-vm"
SHELL_MARKER="${LOGIN_USER}@${VM_HOSTNAME}:"
ROOT_SHELL_MARKER='root@.*:/#'

BOOT_TIMEOUT_SECS=240
LOGIN_TIMEOUT_SECS=60
BENCH_TIMEOUT_SECS=2400
SHUTDOWN_TIMEOUT_SECS=120

mkdir -p "$RUN_DIR" "$RESULTS_DIR"
rm -f "$SERIAL_LOG" "$QEMU_LOG" "$OVERLAY_IMAGE" "$SERIAL_SOCKET"

if [[ ! -f "$KERNEL_IMAGE" ]]; then
        echo "missing kernel image: $KERNEL_IMAGE" >&2
        exit 1
fi

if [[ ! -f "$BASE_IMAGE" ]]; then
        echo "missing base image: $BASE_IMAGE" >&2
        exit 1
fi

if ! command -v qemu-img >/dev/null 2>&1 || ! command -v qemu-system-x86_64 >/dev/null 2>&1 || ! command -v socat >/dev/null 2>&1; then
        echo "missing one of: qemu-img, qemu-system-x86_64, socat" >&2
        exit 1
fi

cleanup() {
        local status=$?
        if [[ -n "${serial_tee_pid:-}" ]]; then
                kill "$serial_tee_pid" >/dev/null 2>&1 || true
                wait "$serial_tee_pid" 2>/dev/null || true
        fi
        if [[ -n "${SERIAL_PID:-}" ]]; then
                kill "$SERIAL_PID" >/dev/null 2>&1 || true
                wait "$SERIAL_PID" 2>/dev/null || true
        fi
        if [[ -n "${QEMU_PID:-}" ]]; then
                kill "$QEMU_PID" >/dev/null 2>&1 || true
                wait "$QEMU_PID" 2>/dev/null || true
        fi
        rm -f "$SERIAL_SOCKET" "$OVERLAY_IMAGE"
        exit "$status"
}
trap cleanup EXIT

stop_vm() {
        if [[ -n "${serial_tee_pid:-}" ]]; then
                kill "$serial_tee_pid" >/dev/null 2>&1 || true
                wait "$serial_tee_pid" 2>/dev/null || true
                unset serial_tee_pid
        fi
        if [[ -n "${SERIAL_PID:-}" ]]; then
                kill "$SERIAL_PID" >/dev/null 2>&1 || true
                wait "$SERIAL_PID" 2>/dev/null || true
                unset SERIAL_PID
        fi
        if [[ -n "${QEMU_PID:-}" ]]; then
                kill "$QEMU_PID" >/dev/null 2>&1 || true
                wait "$QEMU_PID" 2>/dev/null || true
                unset QEMU_PID
        fi
        exec 3>&- 2>/dev/null || true
        exec 4<&- 2>/dev/null || true
        rm -f "$SERIAL_SOCKET"
}

wait_for_pattern() {
        local pattern=$1
        local timeout_secs=$2
        local start

        start=$(date +%s)
        while true; do
                if [[ -f "$SERIAL_LOG" ]] && LC_ALL=C grep -aEq "$pattern" "$SERIAL_LOG"; then
                        return 0
                fi
                if [[ -n "${QEMU_PID:-}" ]] && ! kill -0 "$QEMU_PID" >/dev/null 2>&1; then
                        return 1
                fi
                if (( $(date +%s) - start >= timeout_secs )); then
                        return 1
                fi
                sleep 1
        done
}

send_serial() {
        printf '%s\r\n' "$1" >&3
}

serial_login() {
        send_serial ""
        wait_for_pattern 'login:' "$BOOT_TIMEOUT_SECS" || return 1

        send_serial "$LOGIN_USER"
        wait_for_pattern 'Password:' "$LOGIN_TIMEOUT_SECS" || return 1
        send_serial "$LOGIN_PASSWORD_PRIMARY"

        wait_for_pattern "$SHELL_MARKER" "$LOGIN_TIMEOUT_SECS" || return 1
        LOGIN_PASSWORD_USED="$LOGIN_PASSWORD_PRIMARY"
}

serial_root_shell() {
        send_serial ""
        wait_for_pattern "$ROOT_SHELL_MARKER" "$BOOT_TIMEOUT_SECS" || return 1
}

start_vm() {
        local append_args=$1

        rm -f "$SERIAL_LOG" "$QEMU_LOG" "$SERIAL_SOCKET"

        qemu-system-x86_64 \
                -enable-kvm -cpu host -m 4G -smp 1 \
                -kernel "$KERNEL_IMAGE" \
                -append "$append_args" \
                -drive "file=$OVERLAY_IMAGE,format=qcow2" \
                -nic user \
                -monitor none \
                -display none \
                -serial "unix:$SERIAL_SOCKET,server=on,wait=off" \
                >"$QEMU_LOG" 2>&1 &
        QEMU_PID=$!

        start=$(date +%s)
        while [[ ! -S "$SERIAL_SOCKET" ]]; do
                if ! kill -0 "$QEMU_PID" >/dev/null 2>&1; then
                        echo "qemu exited before serial socket was ready" >&2
                        exit 1
                fi
                if (( $(date +%s) - start >= 30 )); then
                        echo "serial socket was not created" >&2
                        exit 1
                fi
                sleep 1
        done

        sleep 1

        coproc SERIAL { socat - "UNIX-CONNECT:$SERIAL_SOCKET"; }
        SERIAL_PID=$SERIAL_PID
        exec 3>&"${SERIAL[1]}"
        exec 4<&"${SERIAL[0]}"
        stdbuf -oL cat <&4 >"$SERIAL_LOG" &
        serial_tee_pid=$!
}

echo "======================== Creating overlay for kernel version $VER ========================"
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$OVERLAY_IMAGE" >/dev/null

echo "======================== Booting kernel version $VER ========================"
start_vm "root=/dev/sda2 rw console=ttyS0 init=/bin/bash"

echo "======================== Preparing init=/bin/bash environment ========================"
if ! serial_root_shell; then
        echo "failed to reach init=/bin/bash shell over serial console" >&2
        exit 1
fi

send_serial "mount -o remount,rw / || true; mount -t proc proc /proc || true; mount -t sysfs sysfs /sys || true; mount -t devtmpfs devtmpfs /dev || true; mkdir -p /dev/pts; mount -t devpts devpts /dev/pts || true; export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
wait_for_pattern "$ROOT_SHELL_MARKER" 10 || {
        echo "failed to prepare init=/bin/bash shell" >&2
        exit 1
}

echo "======================== Running LEBench for kernel version $VER ========================"
send_serial "cd /home/user469/LEBench && env LEBENCH_DIR=/home/user469/LEBench/ ./TEST_DIR/OS_Eval 0 \"\$(uname -r)\"; printf '__BENCH_DONE__:%s\\n' \"\$?\""

if ! wait_for_pattern '__BENCH_DONE__:[0-9]+' "$BENCH_TIMEOUT_SECS"; then
        echo "LEBench did not finish before timeout" >&2
        exit 1
fi

if ! LC_ALL=C grep -aEq '__BENCH_DONE__:0' "$SERIAL_LOG"; then
        echo "LEBench exited with a non-zero status" >&2
        exit 1
fi

send_serial "printf '__CSV_BEGIN__\\n'; cat /home/user469/LEBench/output.\$(uname -r).csv; printf '\\n__CSV_END__\\n'"
if ! wait_for_pattern '__CSV_END__' 30; then
        echo "failed to retrieve CSV output from VM" >&2
        exit 1
fi

tr -d '\r' <"$SERIAL_LOG" | awk '
        /__CSV_BEGIN__/ { capture=1; next }
        /__CSV_END__/   { capture=0; exit }
        capture         { print }
' >"$RESULT_FILE"

if [[ ! -s "$RESULT_FILE" ]]; then
        echo "result file was empty: $RESULT_FILE" >&2
        exit 1
fi

echo "======================== Shutting down VM ========================"
send_serial "sync; poweroff -f"

start=$(date +%s)
while kill -0 "$QEMU_PID" >/dev/null 2>&1; do
        if (( $(date +%s) - start >= SHUTDOWN_TIMEOUT_SECS )); then
                echo "VM did not shut down cleanly within timeout" >&2
                exit 1
        fi
        sleep 1
done

wait "$QEMU_PID" 2>/dev/null || true
unset QEMU_PID

echo "======================== Saved result to $RESULT_FILE ========================"
echo "======================== Finished kernel version $VER ========================"
