"""
把 schedule.json 里设置的提醒时间（可以有多个，每个能单独开关/选星期重复）
编译成 launchd 的 plist 配置，重新加载生效。

由原生 App 的"提醒时间设置"界面在你改动后自动调用，也可以自己手动跑：
    python3 update_schedule.py

schedule.json 格式：
{
  "alarms": [
    {"id": "...", "hour": 8, "minute": 0, "enabled": true, "days": [0,1,2,3,4,5,6]}
  ]
}
days: 0=周日 1=周一 ... 6=周六（跟 launchd 的 Weekday 编号一致）
"""

import json
import os
import plistlib
import subprocess

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEDULE_PATH = os.path.join(PROJECT_DIR, "schedule.json")
PROJECT_PLIST_PATH = os.path.join(PROJECT_DIR, "com.guanyao.canvassync.plist")
INSTALLED_PLIST_PATH = os.path.expanduser("~/Library/LaunchAgents/com.guanyao.canvassync.plist")
LABEL = "com.guanyao.canvassync"

DEFAULT_SCHEDULE = {
    "alarms": [
        {"id": "default", "hour": 8, "minute": 0, "enabled": True, "days": [0, 1, 2, 3, 4, 5, 6]}
    ]
}


def load_schedule():
    if not os.path.exists(SCHEDULE_PATH):
        return DEFAULT_SCHEDULE
    with open(SCHEDULE_PATH) as f:
        return json.load(f)


def build_calendar_intervals(alarms):
    """每个开启的闹钟展开成一个或多个 {Hour, Minute[, Weekday]} 字典。"""
    intervals = []
    for alarm in alarms:
        if not alarm.get("enabled", True):
            continue
        days = alarm.get("days") or list(range(7))
        hour = alarm["hour"]
        minute = alarm["minute"]
        if len(set(days)) >= 7:
            intervals.append({"Hour": hour, "Minute": minute})
        else:
            for d in days:
                intervals.append({"Hour": hour, "Minute": minute, "Weekday": d})
    return intervals


def build_plist(intervals):
    return {
        "Label": LABEL,
        "ProgramArguments": [
            os.path.join(PROJECT_DIR, ".venv/bin/python3"),
            os.path.join(PROJECT_DIR, "canvas_sync.py"),
            "--daily",
        ],
        "WorkingDirectory": PROJECT_DIR,
        "StartCalendarInterval": intervals,
        "StandardOutPath": os.path.join(PROJECT_DIR, "logs/sync.log"),
        "StandardErrorPath": os.path.join(PROJECT_DIR, "logs/sync_error.log"),
        "RunAtLoad": False,
    }


def apply():
    schedule = load_schedule()
    intervals = build_calendar_intervals(schedule.get("alarms", []))
    plist_data = build_plist(intervals)

    for path in (PROJECT_PLIST_PATH, INSTALLED_PLIST_PATH):
        with open(path, "wb") as f:
            plistlib.dump(plist_data, f)

    subprocess.run(["launchctl", "unload", INSTALLED_PLIST_PATH], capture_output=True)

    if not intervals:
        print("⚠️ 所有提醒时间都关闭了，定时任务已卸载（不会自动同步）")
        return

    result = subprocess.run(["launchctl", "load", INSTALLED_PLIST_PATH], capture_output=True, text=True)
    if result.returncode == 0:
        print(f"✅ 已更新 {len(intervals)} 个触发时间点，定时任务重新加载成功")
    else:
        print(f"❌ launchctl load 失败：{result.stderr}")


if __name__ == "__main__":
    apply()
