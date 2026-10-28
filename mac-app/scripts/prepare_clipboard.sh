#!/bin/bash
# 固定官方 server 版本与 SHA-256；仅在构建时下载，用户运行 App 无需联网或安装 scrcpy。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=5.0.1
SHA256=764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536
CACHE="$ROOT/build/dependencies"
SERVER="$CACHE/scrcpy-server-v$VERSION"
mkdir -p "$CACHE"
verify() { [ -f "$SERVER" ] && [ "$(shasum -a 256 "$SERVER" | cut -d ' ' -f 1)" = "$SHA256" ]; }
if ! verify; then
  PART="$(mktemp "$CACHE/scrcpy-download.XXXXXX")"
  trap 'rm -f "$PART"' EXIT
  curl --fail --location --retry 2 --connect-timeout 15 --max-time 120 \
    "https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/scrcpy-server-v$VERSION" -o "$PART"
  [ "$(shasum -a 256 "$PART" | cut -d ' ' -f 1)" = "$SHA256" ] || { echo 'scrcpy-server SHA-256 校验失败' >&2; exit 1; }
  mv "$PART" "$SERVER"
fi
if [ -n "${1:-}" ]; then
  mkdir -p "$1"
  cp "$SERVER" "$1/"
  cp "$ROOT/Resources/scrcpy-LICENSE.txt" "$1/"
fi
