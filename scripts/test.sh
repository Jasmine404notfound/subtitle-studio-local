#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v
bash "$ROOT/scripts/build.sh"
