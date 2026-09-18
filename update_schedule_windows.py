"""
Windows 版的定时同步：把 schedule.json 里设置的提醒时间，转换成 Windows「任务
计划程序」(Task Scheduler) 里的一批计划任务，每次改动后重新生成。

跟 Mac 版 update_schedule.py 用 launchd 是同一个思路，只是换成 Windows 自己的
schtasks 命令。由 Windows 客户端在"提醒时间"设置界面里改动后自动调用，也可以
自己手动跑：
    python update_schedule_windows.py

schedule.json 格式（跟 Mac 版完全一样，方便代码复用）：
{
  "alarms": [
    {"id": "...", "hour": 8, "minute": 0, "enabled": true, "days": [0,1,2,3,4,5,6]}
  ]
}
days: 0=周日 1=周一 ... 6=周六
"""

import json
import os
import subprocess
import sys

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEDULE_PATH = os.path.join(PROJECT_DIR, "schedule.json")
TASK_PREFIX = "CanvasSync_"

WEEKDAY_CODES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

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


def existing_task_names():
    result = subprocess.run(
        ["schtasks", "/Query", "/FO", "CSV", "/NH"],
        capture_output=True, text=True,
    )
    names = []
    for line in result.stdout.splitlines():
        cols = line.split('","')
        if not cols:
            continue
        name = cols[0].strip('"').lstrip("\\")
        if name.startswith(TASK_PREFIX):
            names.append(name)
    return names


def remove_task(name):
    subprocess.run(["schtasks", "/Delete", "/TN", name, "/F"], capture_output=True, text=True)


def create_task(alarm):
    name = f"{TASK_PREFIX}{alarm['id']}"
    hour, minute = alarm["hour"], alarm["minute"]
    days = sorted(set(alarm.get("days") or range(7)))
    python_exe = os.path.join(PROJECT_DIR, ".venv", "Scripts", "python.exe")
    sync_script = os.path.join(PROJECT_DIR, "canvas_sync.py")
    action = f'"{python_exe}" "{sync_script}" --daily'
    start_time = f"{hour:02d}:{minute:02d}"

    if len(days) >= 7:
        cmd = ["schtasks", "/Create", "/TN", name, "/TR", action, "/SC", "DAILY",
               "/ST", start_time, "/F"]
    else:
        day_codes = ",".join(WEEKDAY_CODES[d] for d in days)
        cmd = ["schtasks", "/Create", "/TN", name, "/TR", action, "/SC", "WEEKLY",
               "/D", day_codes, "/ST", start_time, "/F"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr.strip()


def apply():
    schedule = load_schedule()
    alarms = [a for a in schedule.get("alarms", []) if a.get("enabled", True)]

    for name in existing_task_names():
        remove_task(name)

    if not alarms:
        print("⚠️ 所有提醒时间都关闭了，定时任务已清空（不会自动同步）")
        return

    ok_count = 0
    for alarm in alarms:
        ok, err = create_task(alarm)
        if ok:
            ok_count += 1
        else:
            print(f"❌ 创建计划任务失败（{alarm['id']}）：{err}")

    print(f"✅ 已更新 {ok_count}/{len(alarms)} 个触发时间点的 Windows 计划任务")


if __name__ == "__main__":
    if sys.platform != "win32":
        print("⚠️ 这个脚本只能在 Windows 上运行（要用 schtasks 命令）")
        sys.exit(1)
    apply()
