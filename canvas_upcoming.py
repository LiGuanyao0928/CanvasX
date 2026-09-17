"""
Canvas 近期作业提醒脚本
从本地 canvas.db 读取数据，列出未来N天内要交的作业（默认7天）。
日期前面带 "~" 表示是从标题/说明文字里猜出来的，不是Canvas正式设置的。
运行：python3 canvas_upcoming.py
      python3 canvas_upcoming.py 3   # 查未来3天
"""

import json
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

DB_PATH = "canvas.db"

# 要跟踪哪些课，每个用户自己配置（不再写死）——由设置向导生成，
# 或者手动编辑 tracked_courses.json：{"course_ids": [123, 456]}
TRACKED_COURSES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tracked_courses.json")


def _load_tracked_course_ids():
    try:
        with open(TRACKED_COURSES_PATH, encoding="utf-8") as f:
            data = json.load(f)
        return tuple(data.get("course_ids", []))
    except (FileNotFoundError, json.JSONDecodeError):
        return ()


TRACKED_COURSE_IDS = _load_tracked_course_ids()


def get_upcoming(days):
    """有日期（Canvas正式设置的，或者从文字里猜出来的）且落在未来N天内的作业。"""
    if not TRACKED_COURSE_IDS:
        return []
    now = datetime.now(timezone.utc)
    deadline = now + timedelta(days=days)

    placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        f"""
        SELECT courses.name, assignments.name, assignments.due_at, assignments.html_url,
               assignments.due_at_guessed, assignments.description, assignments.module_files,
               assignments.submission_type
        FROM assignments
        JOIN courses ON assignments.course_id = courses.id
        WHERE assignments.due_at IS NOT NULL
          AND courses.id IN ({placeholders})
        ORDER BY assignments.due_at
        """,
        TRACKED_COURSE_IDS,
    ).fetchall()
    conn.close()

    upcoming = []
    for course_name, assignment_name, due_at, url, guessed, description, module_files, submission_type in rows:
        due = datetime.fromisoformat(due_at.replace("Z", "+00:00"))
        if now <= due <= deadline:
            files = json.loads(module_files) if module_files else []
            upcoming.append(
                (due, course_name, assignment_name, url, bool(guessed), description, files, submission_type)
            )
    return upcoming


def get_unspecified():
    """标题/说明里也猜不出日期的作业——真的没法判断，不再要求手动确认，直接标 not specified。"""
    if not TRACKED_COURSE_IDS:
        return []
    placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        f"""
        SELECT courses.name, assignments.name, assignments.html_url, assignments.description,
               assignments.module_files, assignments.submission_type
        FROM assignments
        JOIN courses ON assignments.course_id = courses.id
        WHERE assignments.due_at IS NULL
          AND courses.id IN ({placeholders})
        ORDER BY courses.name
        """,
        TRACKED_COURSE_IDS,
    ).fetchall()
    conn.close()
    return [
        (course_name, assignment_name, url, description, json.loads(module_files) if module_files else [], submission_type)
        for course_name, assignment_name, url, description, module_files, submission_type in rows
    ]


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    upcoming = get_upcoming(days)
    unspecified = get_unspecified()

    if not upcoming:
        print(f"未来 {days} 天内没有要交的作业 🎉")
    else:
        print(f"未来 {days} 天内要交的作业（共 {len(upcoming)} 个）：\n")
        for due, course_name, assignment_name, url, guessed, description, files, submission_type in upcoming:
            local_due = due.astimezone()
            tag = "~" if guessed else ""
            print(f"[{tag}{local_due.strftime('%m-%d %H:%M')}] {course_name}")
            print(f"    {assignment_name}")
            print(f"    {url}\n")

    if unspecified:
        print(f"\n以下作业查不到日期：\n")
        for course_name, assignment_name, url, description, files, submission_type in unspecified:
            print(f"[not specified] {course_name}")
            print(f"    {assignment_name}")
            print(f"    {url}\n")


if __name__ == "__main__":
    main()
