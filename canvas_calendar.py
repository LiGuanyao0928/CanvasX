"""
把已同步的作业截止日期同步进 Mac"日历" App 的本地日历"Canvas作业"里，
用 AppleScript 驱动 Calendar.app —— 不需要额外申请 API key，
第一次运行时 macOS 会弹出"允许访问日历"的系统权限框，同意一次就行。
（这一步系统权限最好在自己手动打开 App 点"刷新数据"时批准一次，
不要指望launchd后台8点自动同步时能弹出对话框让你点。）

用作业 id 编码进事件备注里的 "[canvas-id:N]" 标记做去重/更新依据，
不是靠标题文本匹配（标题可能会改，id 不会变）。已经从 Canvas 消失、
或者不再有到期日的作业，对应的日历事件也会被清掉。

运行：python3 canvas_calendar.py   # 单独跑一次日历同步
"""

import json
import os
import subprocess
import tempfile
from datetime import datetime

from canvas_upcoming import TRACKED_COURSE_IDS

DB_PATH = "canvas.db"
CALENDAR_NAME = "Canvas作业"
STATE_PATH = "calendar_synced_ids.json"


def _escape(text):
    return (text or "").replace("\\", "\\\\").replace('"', '\\"')


def _marker(assignment_id):
    return f"[canvas-id:{assignment_id}]"


def get_dated_assignments():
    import sqlite3

    if not TRACKED_COURSE_IDS:
        return []
    conn = sqlite3.connect(DB_PATH)
    placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
    rows = conn.execute(
        f"""SELECT a.id, c.name, a.name, a.due_at, a.due_at_guessed, a.html_url
            FROM assignments a JOIN courses c ON c.id = a.course_id
            WHERE a.course_id IN ({placeholders}) AND a.due_at IS NOT NULL""",
        TRACKED_COURSE_IDS,
    ).fetchall()
    conn.close()
    return rows


def _load_state():
    try:
        with open(STATE_PATH) as f:
            return set(json.load(f))
    except (FileNotFoundError, json.JSONDecodeError):
        return set()


def _save_state(ids):
    with open(STATE_PATH, "w") as f:
        json.dump(sorted(ids), f)


def build_script(rows, removed_ids):
    call_lines = []
    current_ids = []

    for aid, course_name, assignment_name, due_at, guessed, url in rows:
        try:
            dt = datetime.fromisoformat(due_at.replace("Z", "+00:00")).astimezone()
        except ValueError:
            continue
        current_ids.append(aid)
        prefix = "~" if guessed else ""
        title = f"{prefix}{course_name}：{assignment_name}"
        notes = f"{course_name} · {assignment_name} · {url or ''} · {_marker(aid)}"
        call_lines.append(
            f'    my addOrUpdateEvent("{_escape(title)}", {dt.year}, {dt.month}, {dt.day}, '
            f'{dt.hour}, {dt.minute}, "{_escape(notes)}", "{_marker(aid)}")'
        )

    for rid in removed_ids:
        call_lines.append(f'    my deleteEventByMarker("{_marker(rid)}")')

    script = f'''
on run
    tell application "Calendar"
        if not (exists calendar "{CALENDAR_NAME}") then
            make new calendar with properties {{name:"{CALENDAR_NAME}"}}
        end if
    end tell
{chr(10).join(call_lines)}
end run

on addOrUpdateEvent(theTitle, startY, startMo, startD, startH, startMi, theNotes, theMarker)
    tell application "Calendar"
        set targetCal to calendar "{CALENDAR_NAME}"
        set startDate to current date
        set year of startDate to startY
        set month of startDate to startMo
        set day of startDate to startD
        set hours of startDate to startH
        set minutes of startDate to startMi
        set seconds of startDate to 0
        set endDate to startDate + 30 * minutes

        set matches to (every event of targetCal whose description contains theMarker)
        if (count of matches) > 0 then
            set theEvent to item 1 of matches
            set summary of theEvent to theTitle
            set start date of theEvent to startDate
            set end date of theEvent to endDate
            set description of theEvent to theNotes
        else
            make new event at end of events of targetCal with properties {{summary:theTitle, start date:startDate, end date:endDate, description:theNotes}}
        end if
    end tell
end addOrUpdateEvent

on deleteEventByMarker(theMarker)
    tell application "Calendar"
        set targetCal to calendar "{CALENDAR_NAME}"
        set matches to (every event of targetCal whose description contains theMarker)
        repeat with e in matches
            delete e
        end repeat
    end tell
end deleteEventByMarker
'''
    return script, current_ids


def sync_to_calendar():
    rows = get_dated_assignments()
    previously_synced = _load_state()
    current_ids_preview = {r[0] for r in rows}
    removed_ids = previously_synced - current_ids_preview

    if not rows and not removed_ids:
        return

    script, current_ids = build_script(rows, removed_ids)

    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".applescript", delete=False, encoding="utf-8")
    try:
        tmp.write(script)
        tmp.close()
        try:
            result = subprocess.run(
                ["osascript", tmp.name], capture_output=True, text=True, timeout=60
            )
        except subprocess.TimeoutExpired:
            print("⚠️ 日历同步超时（很可能是系统正在等你点'允许访问日历'的权限框，去点一下再重试）")
            return
        if result.returncode != 0:
            print(f"⚠️ 日历同步失败（可能还没允许访问日历权限）：{result.stderr.strip()}")
            return
        _save_state(current_ids)
        print(f"✅ 日历已同步：{len(current_ids)} 个作业，清理了 {len(removed_ids)} 个过期事件")
    finally:
        try:
            os.remove(tmp.name)
        except OSError:
            pass


if __name__ == "__main__":
    sync_to_calendar()
