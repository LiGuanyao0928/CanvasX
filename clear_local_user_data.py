"""
清掉这台电脑上这个人的 Canvas 账号信息和已同步数据——设置面板的"退出登录"、
以及登录页"记住我"没勾选时退出 App 自动清理，Mac 版和 Windows 版都调用这
同一份脚本，不在 Swift/C# 两边各自维护一份文件名单。以后要是加了新的
per-user 生成文件，只用改这一处，两个客户端的清理行为自动一起更新。

运行：python3 clear_local_user_data.py
"""

import os

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))

FILES_TO_REMOVE = [
    ".env",
    "tracked_courses.json",
    "canvas.db",
    "canvas.db-journal",
    "dashboard.html",
    "materials.html",
    "grades.html",
    "calendar_synced_ids.json",
    "canvas_assignments.ics",
]


def clear():
    for name in FILES_TO_REMOVE:
        try:
            os.remove(os.path.join(PROJECT_DIR, name))
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    clear()
