#!/bin/bash
# Linux 目前没有独立的原生客户端（没有能实际测试图形界面的环境），这个脚本给你
# 一个能跑起来的方案：Python 后端照常同步，网页仪表盘用浏览器打开，定时靠 cron。
# 功能上（作业/成绩/资料/推送/日历导出）跟 Mac/Windows 版是对等的，只是没有独立
# 窗口的客户端外壳。
#
# 用法：./setup_linux.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "== 1/4 创建虚拟环境 + 安装依赖 =="
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
.venv/bin/python3 -m pip install --upgrade pip --quiet
.venv/bin/python3 -m pip install -r requirements.txt --quiet
echo "✅ Python 环境准备好了"

echo "== 2/4 填 Canvas 账号信息 =="
if [ ! -f ".env" ]; then
    echo "在 Canvas 网页里，进入「账户 → 设置」，拉到最下面点「+新建访问令牌」。"
    read -rp "Canvas 网址（比如 https://yourschool.instructure.com）: " canvas_url
    read -rsp "Canvas Access Token: " canvas_token
    echo
    {
        echo "CANVAS_API_TOKEN=$canvas_token"
        echo "CANVAS_BASE_URL=$canvas_url"
        echo "NOTIFY_METHOD=none"
    } > .env
    echo '{"course_ids": []}' > tracked_courses.json
else
    echo "已经有 .env 了，跳过"
fi

echo "== 3/4 拉课程列表，选要追踪的课 =="
mkdir -p logs
.venv/bin/python3 canvas_sync.py --refresh
.venv/bin/python3 list_courses.py
echo ""
echo "⚠️ 上面是你的课程列表——把真正要交作业的课程 id 抄进 tracked_courses.json，比如："
echo '   {"course_ids": [12345, 67890]}'
read -rp "改好了按回车继续（先不改也行，以后随时能改，改完重新跑一次 .venv/bin/python3 canvas_sync.py --refresh 生效）: " _

.venv/bin/python3 canvas_sync.py --refresh

echo "== 4/4 打开网页仪表盘 =="
xdg-open dashboard.html >/dev/null 2>&1 || echo "打不开浏览器的话，手动用浏览器打开这个文件夹里的 dashboard.html"

echo ""
echo "✅ 完成！以后手动刷新：.venv/bin/python3 canvas_sync.py --refresh"
echo "   想要每天自动同步 + 手机推送 + 生成日历文件，运行一次：.venv/bin/python3 update_schedule_linux.py"
echo "   （推送方式在 .env 里的 NOTIFY_METHOD 设置，参考 .env.example）"
