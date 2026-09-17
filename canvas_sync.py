"""
Canvas 作业同步脚本
拉取所有当前课程的作业列表，写入本地 SQLite 数据库（canvas.db）。
日期猜测顺序：Canvas 正式 due_at → 标题/说明文字 → 课程 Syllabus 正文
（比如 Midterm 考试日期通常只在 Syllabus 里写着）。
也会补抓没有对应 Assignment 的独立 Quiz（比如练习测验）。
同步完还会重建全文搜索索引（见 canvas_search.py）。

这个文件本身只负责"同步数据"，推送手机 / 打开仪表盘网页是两种不同场景，
用命令行参数区分：
    python3 canvas_sync.py            只同步数据，不推送、不开网页
    python3 canvas_sync.py --daily    同步 + 推送手机提醒 + 生成网页（不自动打开）
                                       —— 给 launchd 每天早8点跑的
    python3 canvas_sync.py --open     同步 + 生成网页并自动打开（不推送手机）
                                       —— 给 Safari 版"打开App"图标用的
    python3 canvas_sync.py --refresh  同步 + 生成网页，不自动打开、不推送
                                       —— 给原生 Swift App 用的，它自己内嵌网页窗口

复用之前 canvas_test.py 用的同一个 .env（CANVAS_API_TOKEN, CANVAS_BASE_URL）。

可以反复运行，重复数据会自动覆盖更新，不会产生重复记录。
"""

import json
import os
import sqlite3
import sys
import requests
from dotenv import load_dotenv
from canvas_notify import notify
from canvas_dashboard import generate as generate_dashboard
from canvas_search import rebuild_index as rebuild_search_index
from canvas_grades import generate as generate_grades
from canvas_materials import sync_materials, generate as generate_materials
from canvas_calendar import sync_to_calendar
from due_date_parser import guess_due_at, guess_due_at_from_syllabus

load_dotenv()

TOKEN = os.getenv("CANVAS_API_TOKEN")
BASE_URL = os.getenv("CANVAS_BASE_URL")
DB_PATH = "canvas.db"

HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def get_paginated(url, params=None):
    """处理 Canvas API 的分页（用 Link header 找下一页），返回所有结果的 list"""
    results = []
    while url:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=10)
        resp.raise_for_status()
        results.extend(resp.json())
        url = None
        params = None  # 下一页的参数已经包含在 next 链接里了
        if "Link" in resp.headers:
            for link in requests.utils.parse_header_links(resp.headers["Link"]):
                if link.get("rel") == "next":
                    url = link["url"]
    return results


def get_standalone_quizzes(course_id, known_assignment_ids):
    """
    Canvas 的 Quiz 如果是计分的，本来就会在 /assignments 里出现（带 quiz_id）。
    这里只补抓那些没有对应 Assignment 的 Quiz（比如练习测验、问卷）。
    用负数 id 存进 assignments 表，跟真正的 assignment id 区分开、不会撞车。
    """
    try:
        quizzes = get_paginated(
            f"{BASE_URL.rstrip('/')}/api/v1/courses/{course_id}/quizzes",
            params={"per_page": 50},
        )
    except requests.exceptions.HTTPError:
        return []  # 这门课没开启 Quizzes 页面

    standalone = []
    for q in quizzes:
        assignment_id = q.get("assignment_id")
        if assignment_id and assignment_id in known_assignment_ids:
            continue  # 已经在 assignments 里同步过了，跳过避免重复
        standalone.append(
            {
                "id": -q["id"],  # 负数：跟 assignment id 空间区分开
                "name": q.get("title"),
                "due_at": q.get("due_at"),
                "points_possible": q.get("points_possible"),
                "html_url": q.get("html_url"),
                "description": q.get("description"),
                "submission_types": ["quiz"],
            }
        )
    return standalone


def get_modules(course_id):
    """抓这门课 Modules 页面的完整结构（含每个 module 里的条目），
    资料库同步（canvas_materials）和作业附件关联（get_module_file_links）共用同一份数据，
    避免重复调用 API。"""
    try:
        return get_paginated(
            f"{BASE_URL.rstrip('/')}/api/v1/courses/{course_id}/modules",
            params={"include[]": "items", "per_page": 50},
        )
    except requests.exceptions.HTTPError:
        return []


def get_assignment_groups(course_id):
    """作业分组 + 权重（算加权成绩要用），比如"作业 20% / 期中 30% / 期末 50%"。"""
    try:
        return get_paginated(
            f"{BASE_URL.rstrip('/')}/api/v1/courses/{course_id}/assignment_groups",
            params={"per_page": 50},
        )
    except requests.exceptions.HTTPError:
        return []


def get_module_file_links(modules):
    """
    Canvas 里作业要求经常不是写在 Assignment 的 description 里，
    而是在 Modules 页面挂了一个文件，紧挨在对应的 Assignment 条目前面。
    返回 {assignment_id: [(文件名, 链接), ...]}
    """
    links_by_assignment = {}
    for module in modules:
        items = sorted(module.get("items") or [], key=lambda i: i.get("position", 0))
        pending_files = []
        for item in items:
            if item.get("type") == "File":
                pending_files.append((item.get("title"), item.get("html_url")))
            elif item.get("type") == "Assignment":
                if pending_files:
                    links_by_assignment[item.get("content_id")] = pending_files
                pending_files = []
            else:
                pending_files = []
    return links_by_assignment


def init_db(conn):
    conn.execute("""
        CREATE TABLE IF NOT EXISTS courses (
            id INTEGER PRIMARY KEY,
            name TEXT,
            course_code TEXT
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS assignments (
            id INTEGER PRIMARY KEY,
            course_id INTEGER,
            name TEXT,
            due_at TEXT,
            due_at_guessed INTEGER DEFAULT 0,
            points_possible REAL,
            html_url TEXT,
            description TEXT,
            module_files TEXT,
            submission_type TEXT,
            last_synced TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS assignment_groups (
            id INTEGER PRIMARY KEY,
            course_id INTEGER,
            name TEXT,
            group_weight REAL
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS materials (
            id INTEGER PRIMARY KEY,
            course_id INTEGER,
            module_name TEXT,
            filename TEXT,
            local_path TEXT,
            size INTEGER,
            content_type TEXT,
            updated_at TEXT
        )
    """)
    for column, coltype in [
        ("due_at_guessed", "INTEGER DEFAULT 0"),
        ("description", "TEXT"),
        ("module_files", "TEXT"),
        ("submission_type", "TEXT"),
        ("score", "REAL"),
        ("assignment_group_id", "INTEGER"),
        ("workflow_state", "TEXT"),
    ]:
        try:
            conn.execute(f"ALTER TABLE assignments ADD COLUMN {column} {coltype}")
        except sqlite3.OperationalError:
            pass  # 已经有这一列了（老数据库升级）
    try:
        conn.execute("ALTER TABLE materials ADD COLUMN source TEXT DEFAULT 'canvas'")
    except sqlite3.OperationalError:
        pass
    try:
        conn.execute("ALTER TABLE courses ADD COLUMN apply_group_weights INTEGER DEFAULT 0")
    except sqlite3.OperationalError:
        pass
    conn.commit()


def sync():
    if not TOKEN or not BASE_URL:
        print("❌ 缺少 .env 里的 CANVAS_API_TOKEN 或 CANVAS_BASE_URL")
        return

    conn = sqlite3.connect(DB_PATH)
    init_db(conn)

    print("正在拉取课程列表...")
    courses = get_paginated(
        f"{BASE_URL.rstrip('/')}/api/v1/courses",
        params={"per_page": 50, "enrollment_state": "active", "include[]": "syllabus_body"},
    )

    for course in courses:
        course_id = course.get("id")
        name = course.get("name", "未命名课程")
        course_code = course.get("course_code", "")
        syllabus_body = course.get("syllabus_body")
        apply_group_weights = 1 if course.get("apply_assignment_group_weights") else 0

        conn.execute(
            "INSERT OR REPLACE INTO courses (id, name, course_code, apply_group_weights) VALUES (?, ?, ?, ?)",
            (course_id, name, course_code, apply_group_weights),
        )

        print(f"  拉取《{name}》的作业...")
        try:
            assignments = get_paginated(
                f"{BASE_URL.rstrip('/')}/api/v1/courses/{course_id}/assignments",
                params={"per_page": 50, "include[]": "submission"},
            )
        except requests.exceptions.HTTPError as e:
            print(f"    ⚠️ 跳过这门课（可能没有权限或已归档）：{e}")
            continue

        modules = get_modules(course_id)
        module_file_links = get_module_file_links(modules)

        assignment_groups = get_assignment_groups(course_id)
        for g in assignment_groups:
            conn.execute(
                "INSERT OR REPLACE INTO assignment_groups (id, course_id, name, group_weight) VALUES (?, ?, ?, ?)",
                (g.get("id"), course_id, g.get("name"), g.get("group_weight")),
            )

        known_assignment_ids = {a.get("id") for a in assignments}
        standalone_quizzes = get_standalone_quizzes(course_id, known_assignment_ids)
        if standalone_quizzes:
            print(f"    额外找到 {len(standalone_quizzes)} 个独立 Quiz（没有对应 Assignment 的）")

        for a in assignments + standalone_quizzes:
            due_at = a.get("due_at")
            due_at_guessed = 0
            if not due_at:
                guessed = guess_due_at(a.get("name"), a.get("description"))
                if guessed:
                    due_at = guessed
                    due_at_guessed = 1
            if not due_at:
                guessed = guess_due_at_from_syllabus(a.get("name"), syllabus_body)
                if guessed:
                    due_at = guessed
                    due_at_guessed = 1

            module_files = module_file_links.get(a.get("id"), [])
            submission_type = (a.get("submission_types") or ["none"])[0]
            submission = a.get("submission") or {}
            score = submission.get("score")
            workflow_state = "excused" if submission.get("excused") else submission.get("workflow_state")

            conn.execute(
                """INSERT OR REPLACE INTO assignments
                   (id, course_id, name, due_at, due_at_guessed, points_possible, html_url, description,
                    module_files, submission_type, score, assignment_group_id, workflow_state)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    a.get("id"),
                    course_id,
                    a.get("name"),
                    due_at,
                    due_at_guessed,
                    a.get("points_possible"),
                    a.get("html_url"),
                    a.get("description"),
                    json.dumps(module_files),
                    submission_type,
                    score,
                    a.get("assignment_group_id"),
                    workflow_state,
                ),
            )

        sync_materials(conn, BASE_URL, HEADERS, course_id, name, modules)

    rebuild_search_index(conn)

    conn.commit()
    conn.close()
    print(f"\n✅ 同步完成，数据已写入 {DB_PATH}")


def main():
    sync()
    if "--daily" in sys.argv:
        notify(7)
        generate_dashboard(30, auto_open=False)
        generate_grades()
        generate_materials()
        sync_to_calendar()
    elif "--open" in sys.argv:
        generate_dashboard(30, auto_open=True)
        generate_grades()
        generate_materials()
    elif "--refresh" in sys.argv:
        # 给原生 App 用的：只刷新数据 + 重新生成网页，不推送、不自己开 Safari
        # （App 自己内嵌网页窗口，展示这份刚生成的 dashboard.html）
        generate_dashboard(30, auto_open=False)
        generate_grades()
        generate_materials()
        sync_to_calendar()


if __name__ == "__main__":
    main()
