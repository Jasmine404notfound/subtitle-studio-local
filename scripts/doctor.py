#!/usr/bin/env python3
"""Read-only dependency check. Never downloads a model or opens private media."""
import importlib.util
import platform
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
runtime = root / 'dist' / '本地校对环境'
checks = {
    'Apple Silicon macOS': sys.platform == 'darwin' and platform.machine() == 'arm64',
    'macOS 26+': bool(platform.mac_ver()[0]) and int(platform.mac_ver()[0].split('.')[0]) >= 26,
    'Python 3.12': sys.version_info[:2] == (3, 12),
    'FFmpeg': shutil.which('ffmpeg') is not None,
    'Swift compiler': shutil.which('swiftc') is not None,
    'Whisper CLI': (runtime / 'venv/bin/mlx_whisper').is_file(),
    'Qwen model config': (runtime / 'model/config.json').is_file(),
    'Qwen model weights': any((runtime / 'model').glob('*.safetensors')),
    'Qwen chat template': (runtime / 'model/chat_template.jinja').is_file(),
    'App': (root / 'dist/字幕转写.app/Contents/MacOS/SubtitleStudio').is_file(),
}
for name in ('mlx', 'mlx_whisper', 'mlx_lm', 'transformers', 'webrtcvad'):
    checks[name] = importlib.util.find_spec(name) is not None
for label, ok in checks.items():
    print(('OK   ' if ok else 'MISS ') + label)
if not all(checks.values()):
    print('请从项目根目录运行 bash scripts/setup.sh；已有环境则使用 dist/本地校对环境/venv/bin/python3 执行本脚本。')
    sys.exit(1)
print('路径和依赖检查通过；这不代表真实音频转写质量已验证。')
