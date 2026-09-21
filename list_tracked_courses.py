"""
列出正在追踪的课程 id + 课程名（从本地 canvas.db 读，不用再打一次 Canvas API）。
给课程表页面（timetable.html）的"选课程"下拉框用——课表本身（星期几/几点/教室）不是
Canvas 能提供的数据（教务系统才有），但课程名字用 Canvas 真实同步下来的，保证跟
作业看板等其他页面看到的课程名字完全一致。

运行：python3 list_tracked_courses.py
输出：JSON 数组 [{"id": 123, "name": "..."}] 打印到 stdout
"""

import json
import sqlite3

from canvas_upcoming import TRACKED_COURSE_IDS

DB_PATH = "canvas.db"


def main():
    if not TRACKED_COURSE_IDS:
        print("[]")
        return
    conn = sqlite3.connect(DB_PATH)
    placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
    rows = conn.execute(
        f"SELECT id, name FROM courses WHERE id IN ({placeholders}) ORDER BY name",
        TRACKED_COURSE_IDS,
    ).fetchall()
    conn.close()
    print(json.dumps([{"id": cid, "name": name} for cid, name in rows], ensure_ascii=False))


if __name__ == "__main__":
    main()
