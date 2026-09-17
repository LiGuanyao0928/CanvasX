"""
Canvas 作业全文搜索
搜索范围：作业标题 + 说明文字 + 课程名。用 SQLite FTS5 建索引，
每次 canvas_sync.py 同步完都会自动重建一次，保证是最新数据。

运行：python3 canvas_search.py 关键词
      python3 canvas_search.py lab report
"""

import re
import sqlite3
import sys

from canvas_upcoming import TRACKED_COURSE_IDS

DB_PATH = "canvas.db"
TAG_RE = re.compile(r"<[^<]+?>")


def strip_html(text):
    return TAG_RE.sub(" ", text or "")


def rebuild_index(conn=None):
    """从 assignments 表重建一份全文索引。全量重建，简单但对这点数据量足够快。"""
    own_conn = conn is None
    if own_conn:
        conn = sqlite3.connect(DB_PATH)

    conn.execute("DROP TABLE IF EXISTS assignments_fts")
    conn.execute("""
        CREATE VIRTUAL TABLE assignments_fts USING fts5(
            name, description, course_name, url UNINDEXED, assignment_id UNINDEXED
        )
    """)

    rows = []
    if TRACKED_COURSE_IDS:
        placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
        rows = conn.execute(
            f"""
            SELECT assignments.id, assignments.name, assignments.description,
                   courses.name, assignments.html_url
            FROM assignments
            JOIN courses ON assignments.course_id = courses.id
            WHERE courses.id IN ({placeholders})
            """,
            TRACKED_COURSE_IDS,
        ).fetchall()

    conn.executemany(
        "INSERT INTO assignments_fts (name, description, course_name, url, assignment_id) VALUES (?, ?, ?, ?, ?)",
        [
            (name, strip_html(description), course_name, url, assignment_id)
            for assignment_id, name, description, course_name, url in rows
        ],
    )

    conn.commit()
    if own_conn:
        conn.close()


def search(keyword, limit=20):
    # 把每个词单独加引号，避免用户输入里带 FTS5 的保留字符（比如 - " *）搞出语法错误
    words = keyword.split()
    if not words:
        return []
    fts_query = " ".join(f'"{w}"' for w in words)

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """
            SELECT course_name, name, url, snippet(assignments_fts, 1, '[', ']', ' ... ', 12)
            FROM assignments_fts
            WHERE assignments_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """,
            (fts_query, limit),
        ).fetchall()
    except sqlite3.OperationalError:
        return []
    finally:
        conn.close()
    return rows


def main():
    if len(sys.argv) < 2:
        print("用法：python3 canvas_search.py 关键词")
        return

    keyword = " ".join(sys.argv[1:])
    results = search(keyword)

    if not results:
        print(f"没搜到跟 “{keyword}” 有关的作业")
        return

    print(f"搜到 {len(results)} 个结果：\n")
    for course_name, name, url, snippet_text in results:
        print(f"[{course_name}] {name}")
        if snippet_text.strip():
            print(f"    …{snippet_text}…")
        print(f"    {url}\n")


if __name__ == "__main__":
    main()
