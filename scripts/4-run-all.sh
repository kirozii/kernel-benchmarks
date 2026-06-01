#!/usr/bin/env bash
set -euo pipefail

usage() {
        cat <<EOF
usage: $0 [--cleanup] [--versions-file FILE] <all|kernel-version...>

Examples:
  $0 5.0 5.4 5.11.3
  $0 --cleanup 5.11.3
  $0 all
  $0 --versions-file scripts/versions.txt all

Notes:
  - "all" reads one kernel version per line from scripts/versions.txt by default.
  - --cleanup removes scripts/kernels/linux-<ver> and scripts/build/linux-<ver>
    after a successful benchmark run to save disk space.
EOF
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DEFAULT_VERSIONS_FILE="$SCRIPT_DIR/versions.txt"

cleanup=0
versions_file="$DEFAULT_VERSIONS_FILE"
targets=()

while (( $# > 0 )); do
        case "$1" in
                --cleanup)
                        cleanup=1
                        shift
                        ;;
                --versions-file)
                        [[ $# -ge 2 ]] || { usage; exit 1; }
                        versions_file=$2
                        shift 2
                        ;;
                -h|--help)
                        usage
                        exit 0
                        ;;
                *)
                        targets+=("$1")
                        shift
                        ;;
        esac
done

(( ${#targets[@]} > 0 )) || { usage; exit 1; }

versions=()

read_versions_file() {
        local file=$1
        [[ -f "$file" ]] || {
                echo "missing versions file: $file" >&2
                exit 1
        }

        while IFS= read -r line; do
                line=${line#"${line%%[![:space:]]*}"}
                line=${line%"${line##*[![:space:]]}"}
                [[ -n "$line" ]] || continue
                [[ "$line" =~ ^# ]] && continue
                versions+=("$line")
        done <"$file"
}

for target in "${targets[@]}"; do
        if [[ "$target" == "all" ]]; then
                read_versions_file "$versions_file"
        else
                versions+=("$target")
        fi
done

(( ${#versions[@]} > 0 )) || {
        echo "no kernel versions to run" >&2
        exit 1
}

for ver in "${versions[@]}"; do
        echo "======================== Orchestrating kernel version $ver ========================"
        (
                cd "$SCRIPT_DIR"
                ./1-fetchkern.sh "$ver"
                ./2-buildkern.sh "$ver"
        )
        "$SCRIPT_DIR/3-run-version.sh" "$ver"

        if (( cleanup == 1 )); then
                echo "======================== Cleaning build artifacts for kernel version $ver ========================"
                rm -rf "$SCRIPT_DIR/kernels/linux-$ver" "$SCRIPT_DIR/build/linux-$ver"
        fi
done

echo "======================== Finished orchestration ========================"
