"""
列出已经拉到本地数据库的所有课程和 id——手动编辑 tracked_courses.json（比如在
没有图形化设置向导的 Linux 上）时用来确认课程 id。

运行：python3 canvas_sync.py --refresh   # 先跑一次，把课程列表拉下来
      python3 list_courses.py            # 再看这份列表
"""

import sqlite3

DB_PATH = "canvas.db"


def main():
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT id, name, course_code FROM courses ORDER BY name").fetchall()
    conn.close()
    if not rows:
        print("还没有课程数据，先跑一次 python3 canvas_sync.py --refresh")
        return
    print(f"{'课程 ID':<10} 课程名")
    print("-" * 50)
    for course_id, name, code in rows:
        print(f"{course_id:<10} {name}（{code}）")
    print("\n把想追踪的课程 id 填进 tracked_courses.json，比如：")
    print('{"course_ids": [' + ", ".join(str(r[0]) for r in rows[:2]) + ']}')


if __name__ == "__main__":
    main()
