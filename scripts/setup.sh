#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${SUBTITLE_PYTHON:-python3.12}"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo '需要 Apple Silicon Mac。' >&2; exit 1
fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 26 ]; then echo '当前固定的 MLX 环境需要 macOS 26 或以上。' >&2; exit 1; fi
if ! command -v "$PYTHON" >/dev/null; then echo '请先安装 Python 3.12，或设置 SUBTITLE_PYTHON 为它的路径。' >&2; exit 1; fi
"$PYTHON" -c 'import sys; assert sys.version_info[:2] == (3,12), "请使用 Python 3.12"'
if ! command -v ffmpeg >/dev/null; then echo '请先安装 FFmpeg（例如 brew install ffmpeg），再运行本脚本。' >&2; exit 1; fi
xcrun --find swiftc >/dev/null
RUNTIME="$ROOT/dist/本地校对环境"
mkdir -p "$RUNTIME"
"$PYTHON" -m venv "$RUNTIME/venv"
"$RUNTIME/venv/bin/python3" -m pip install -r "$ROOT/requirements.txt"
"$RUNTIME/venv/bin/python3" "$ROOT/scripts/download_model.py" --destination "$RUNTIME"
bash "$ROOT/scripts/build.sh"
"$RUNTIME/venv/bin/python3" "$ROOT/scripts/doctor.py"
echo '安装完成：dist/字幕转写.app。请保持项目路径和 Python 安装位置不变。'
