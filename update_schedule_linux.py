"""
Linux 版定时同步：把 schedule.json 里的提醒时间写进 crontab，用 cron 触发。
Linux 目前没有独立的原生客户端（没有能实际测试图形界面的环境），先提供"Python
后端 + 网页仪表盘"这种能跑起来的方案：cron 定时跑 canvas_sync.py --daily，平时
打开 dashboard.html 网页看作业，见 setup_linux.sh。

用法：python3 update_schedule_linux.py
（只会整体替换 crontab 里 "# canvas-dashboard-start" 到 "# canvas-dashboard-end"
之间的内容，不影响你自己其他的 crontab 任务）
"""

import json
import os
import subprocess
import sys

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEDULE_PATH = os.path.join(PROJECT_DIR, "schedule.json")
MARK_START = "# canvas-dashboard-start"
MARK_END = "# canvas-dashboard-end"

DEFAULT_SCHEDULE = {
    "alarms": [
        {"id": "default", "hour": 8, "minute": 0, "enabled": True, "days": [0, 1, 2, 3, 4, 5, 6]}
    ]
}


def load_schedule():
    if not os.path.exists(SCHEDULE_PATH):
        return DEFAULT_SCHEDULE
    with open(SCHEDULE_PATH, encoding="utf-8") as f:
        return json.load(f)


def current_crontab():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else ""


def build_block(alarms):
    python_bin = os.path.join(PROJECT_DIR, ".venv", "bin", "python3")
    sync_script = os.path.join(PROJECT_DIR, "canvas_sync.py")
    lines = [MARK_START]
    for alarm in alarms:
        if not alarm.get("enabled", True):
            continue
        days = sorted(set(alarm.get("days") or range(7)))
        day_field = "*" if len(days) >= 7 else ",".join(str(d) for d in days)
        lines.append(
            f"{alarm['minute']} {alarm['hour']} * * {day_field} "
            f"cd {PROJECT_DIR} && {python_bin} {sync_script} --daily >> logs/sync.log 2>&1"
        )
    lines.append(MARK_END)
    return "\n".join(lines)


def apply():
    schedule = load_schedule()
    alarms = schedule.get("alarms", [])

    old = current_crontab()
    before, _, rest = old.partition(MARK_START)
    _, _, after = rest.partition(MARK_END)
    kept = before.rstrip("\n") + ("\n" if before.strip() else "") + after.lstrip("\n")

    block = build_block(alarms)
    new_crontab = (kept.rstrip("\n") + "\n\n" + block + "\n") if kept.strip() else block + "\n"

    proc = subprocess.run(["crontab", "-"], input=new_crontab, text=True, capture_output=True)
    if proc.returncode == 0:
        enabled = [a for a in alarms if a.get("enabled", True)]
        print(f"✅ 已更新 crontab，{len(enabled)} 个触发时间点生效")
    else:
        print(f"❌ 写入 crontab 失败：{proc.stderr.strip()}")


if __name__ == "__main__":
    if sys.platform in ("darwin", "win32"):
        print("⚠️ 这个脚本是给 Linux 用的（用 crontab）。Mac 请用 update_schedule.py，"
              "Windows 请用 update_schedule_windows.py")
        sys.exit(1)
    apply()
