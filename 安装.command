#!/bin/bash
cd "$(dirname "$0")" || exit 1
if bash scripts/setup.sh; then
  open 'dist/字幕转写.app'
else
  echo '安装未完成，请查看上方提示。'
  read -r -p '按回车关闭…'
  exit 1
fi
