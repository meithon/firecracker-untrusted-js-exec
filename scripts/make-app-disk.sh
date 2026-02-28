#!/usr/bin/env bash
set -euo pipefail

INDEX_JS=""
OUTPUT="./app.ext4"
SIZE_MB="64"

usage() {
  cat <<USAGE
Create an immutable app disk that contains /index.js.

Required:
  --index-js PATH      Host index.js path

Optional:
  --output PATH        Output ext4 path (default: $OUTPUT)
  --size-mb N          Disk size in MiB (default: $SIZE_MB)
  -h, --help           Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-js)
      INDEX_JS="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --size-mb)
      SIZE_MB="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$INDEX_JS" ]]; then
  echo "error: --index-js is required" >&2
  usage
  exit 1
fi
[[ -f "$INDEX_JS" ]] || { echo "error: index.js not found: $INDEX_JS" >&2; exit 1; }

INDEX_JS="$(realpath "$INDEX_JS")"
OUTPUT="$(realpath "$OUTPUT")"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

cp "$INDEX_JS" "$tmpdir/index.js"
chmod 0644 "$tmpdir/index.js"

truncate -s "${SIZE_MB}M" "$OUTPUT"
mkfs.ext4 -d "$tmpdir" -F "$OUTPUT" >/dev/null

echo "Created app disk: $OUTPUT"
echo "Contains: /index.js"
