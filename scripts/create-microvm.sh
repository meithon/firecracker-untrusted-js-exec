#!/usr/bin/env bash
set -euo pipefail

# Minimal Firecracker launcher that creates and starts one microVM.
# Usage:
#   ./create-microvm.sh --kernel ./vmlinux --rootfs ./ubuntu.ext4 [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_LOCAL_FIRECRACKER="${PROJECT_ROOT}/firecracker/build/cargo_target/$(uname -m)-unknown-linux-musl/debug/firecracker"
FIRECRACKER_BIN="${FIRECRACKER_BIN:-}"
API_SOCK="${API_SOCK:-/tmp/firecracker-microvm.socket}"
VCPU_COUNT="${VCPU_COUNT:-2}"
MEM_SIZE_MIB="${MEM_SIZE_MIB:-512}"
KERNEL_PATH=""
ROOTFS_PATH=""
APP_DRIVE_PATH=""
APP_DRIVE_ID="${APP_DRIVE_ID:-app}"
INIT_PROCESS=""
KERNEL_ARGS_DEFAULT="console=ttyS0 reboot=k panic=1 pci=off"
KERNEL_ARGS="${KERNEL_ARGS:-$KERNEL_ARGS_DEFAULT}"
ROOTFS_READ_ONLY="true"

usage() {
  cat <<USAGE
Create and start one Firecracker microVM.

Required:
  --kernel PATH        Path to uncompressed guest kernel (vmlinux)
  --rootfs PATH        Path to ext4 rootfs image

Optional:
  --firecracker PATH   Firecracker binary path
  --api-sock PATH      API socket path (default: $API_SOCK)
  --vcpu N             vCPU count (default: $VCPU_COUNT)
  --mem-mib N          Memory size in MiB (default: $MEM_SIZE_MIB)
  --kernel-args STR    Kernel boot args
  --init PATH          Guest init path (adds kernel arg: init=PATH)
  --app-drive PATH     Additional read-only ext4 drive (e.g. app disk)
  --app-drive-id ID    Drive id for app drive (default: $APP_DRIVE_ID)
  --rw-rootfs          Attach rootfs as writable (default is read-only)
  -h, --help           Show this help

Environment overrides:
  FIRECRACKER_BIN API_SOCK VCPU_COUNT MEM_SIZE_MIB KERNEL_ARGS
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: command not found: $1" >&2
    exit 1
  }
}

json_put() {
  local endpoint="$1"
  local payload="$2"
  curl --silent --show-error --fail \
    --unix-socket "$API_SOCK" \
    -X PUT "http://localhost/${endpoint}" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "$payload" >/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel)
      KERNEL_PATH="$2"
      shift 2
      ;;
    --rootfs)
      ROOTFS_PATH="$2"
      shift 2
      ;;
    --firecracker)
      FIRECRACKER_BIN="$2"
      shift 2
      ;;
    --api-sock)
      API_SOCK="$2"
      shift 2
      ;;
    --vcpu)
      VCPU_COUNT="$2"
      shift 2
      ;;
    --mem-mib)
      MEM_SIZE_MIB="$2"
      shift 2
      ;;
    --kernel-args)
      KERNEL_ARGS="$2"
      shift 2
      ;;
    --init)
      INIT_PROCESS="$2"
      shift 2
      ;;
    --app-drive)
      APP_DRIVE_PATH="$2"
      shift 2
      ;;
    --app-drive-id)
      APP_DRIVE_ID="$2"
      shift 2
      ;;
    --rw-rootfs)
      ROOTFS_READ_ONLY="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd curl
if [[ -z "$FIRECRACKER_BIN" ]]; then
  if [[ -x "$DEFAULT_LOCAL_FIRECRACKER" ]]; then
    FIRECRACKER_BIN="$DEFAULT_LOCAL_FIRECRACKER"
  elif command -v firecracker >/dev/null 2>&1; then
    FIRECRACKER_BIN="$(command -v firecracker)"
  else
    echo "error: firecracker binary not found. pass --firecracker PATH or set FIRECRACKER_BIN" >&2
    exit 1
  fi
fi

if [[ -z "$KERNEL_PATH" || -z "$ROOTFS_PATH" ]]; then
  echo "error: --kernel and --rootfs are required" >&2
  usage
  exit 1
fi

if [[ ! -x "$FIRECRACKER_BIN" ]]; then
  echo "error: firecracker binary is not executable: $FIRECRACKER_BIN" >&2
  exit 1
fi
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "warning: no read/write access to /dev/kvm; VM start may fail" >&2
fi
if [[ ! -f "$KERNEL_PATH" ]]; then
  echo "error: kernel file not found: $KERNEL_PATH" >&2
  exit 1
fi
if [[ ! -f "$ROOTFS_PATH" ]]; then
  echo "error: rootfs file not found: $ROOTFS_PATH" >&2
  exit 1
fi
if [[ -n "$APP_DRIVE_PATH" && ! -f "$APP_DRIVE_PATH" ]]; then
  echo "error: app drive file not found: $APP_DRIVE_PATH" >&2
  exit 1
fi

KERNEL_PATH="$(realpath "$KERNEL_PATH")"
ROOTFS_PATH="$(realpath "$ROOTFS_PATH")"
if [[ -n "$APP_DRIVE_PATH" ]]; then
  APP_DRIVE_PATH="$(realpath "$APP_DRIVE_PATH")"
fi
if [[ -n "$INIT_PROCESS" ]]; then
  KERNEL_ARGS="${KERNEL_ARGS} init=${INIT_PROCESS}"
fi

# Make repeated runs easy.
rm -f "$API_SOCK"

"$FIRECRACKER_BIN" --api-sock "$API_SOCK" >/tmp/firecracker.out 2>/tmp/firecracker.err &
FC_PID=$!

cleanup() {
  if kill -0 "$FC_PID" >/dev/null 2>&1; then
    kill "$FC_PID" >/dev/null 2>&1 || true
    wait "$FC_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

for _ in $(seq 1 50); do
  [[ -S "$API_SOCK" ]] && break
  sleep 0.1
done

if [[ ! -S "$API_SOCK" ]]; then
  echo "error: firecracker API socket was not created: $API_SOCK" >&2
  echo "stderr:" >&2
  tail -n 50 /tmp/firecracker.err >&2 || true
  exit 1
fi

json_put "machine-config" "{\"vcpu_count\":${VCPU_COUNT},\"mem_size_mib\":${MEM_SIZE_MIB},\"smt\":false}"
json_put "boot-source" "{\"kernel_image_path\":\"${KERNEL_PATH}\",\"boot_args\":\"${KERNEL_ARGS}\"}"
json_put "drives/rootfs" "{\"drive_id\":\"rootfs\",\"path_on_host\":\"${ROOTFS_PATH}\",\"is_root_device\":true,\"is_read_only\":${ROOTFS_READ_ONLY}}"
if [[ -n "$APP_DRIVE_PATH" ]]; then
  json_put "drives/${APP_DRIVE_ID}" "{\"drive_id\":\"${APP_DRIVE_ID}\",\"path_on_host\":\"${APP_DRIVE_PATH}\",\"is_root_device\":false,\"is_read_only\":true}"
fi

curl --silent --show-error --fail \
  --unix-socket "$API_SOCK" \
  -X PUT "http://localhost/actions" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{"action_type":"InstanceStart"}' >/dev/null

echo "microVM started"
echo "  firecracker pid: $FC_PID"
echo "  api socket: $API_SOCK"
echo "  kernel: $KERNEL_PATH"
echo "  rootfs: $ROOTFS_PATH"
if [[ -n "$APP_DRIVE_PATH" ]]; then
  echo "  app drive (${APP_DRIVE_ID}): $APP_DRIVE_PATH"
fi
echo ""
echo "Check logs:"
echo "  tail -f /tmp/firecracker.out /tmp/firecracker.err"
echo "Stop VM:"
echo "  kill $FC_PID"

# Keep the process alive while this script is running so VM is not orphaned by cleanup trap.
trap - EXIT
wait "$FC_PID"
