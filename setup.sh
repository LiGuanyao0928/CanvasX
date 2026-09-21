#!/bin/bash
# 第一次拿到这个项目时跑一次就行。做三件事：
# 1. 建 Python 虚拟环境 + 装依赖
# 2. 编译原生 App 并签名
# 3. 打开 App——第一次打开会自动出现设置向导，跟着填你自己的 Canvas 账号信息就行
#
# 需要电脑上已经有：Xcode 命令行工具（跑 `xcode-select --install` 装）、Python 3
#
# 用法：./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "== 1/3 创建虚拟环境 + 安装依赖 =="
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
.venv/bin/python3 -m pip install --upgrade pip --quiet
.venv/bin/python3 -m pip install -r requirements.txt --quiet
echo "✅ Python 环境准备好了"

echo "== 2/3 编译原生 App =="
native_app/build.sh
echo "✅ App 编译好了"

echo "== 3/3 打开 App =="
mkdir -p logs
open CanvasX.app
echo "✅ 完成！第一次打开会看到设置向导，跟着填你自己的 Canvas 网址/Token/要追踪的课程就行。"
echo "   如果系统提示"无法打开，因为无法验证开发者"，去"系统设置 → 隐私与安全性"里点"仍要打开"。"
