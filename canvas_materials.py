"""
课程资料库
把 Canvas Modules 里挂的文件（讲义/PPT/笔记等）下载到本地 materials/ 文件夹，
按 课程/模块 分类存放；同时生成一个网盘风格的网页（materials.html）：
左边是课程列表（像网盘的文件夹列表），点一个课程只看这一门课的文件，
不用像以前那样翻过其它课的几十上百个文件才能看到下一门课。
支持按模块 / 按文件类型两种查看方式，也能在本地新增/删除文件
（新增会真的把文件拷贝进 materials/ 文件夹，不是只加个记录）。

只处理 Modules 里类型是 "File" 的条目，Page/外部链接暂时不处理。
已经下载过、大小没变的文件不会重复下载，每次同步只抓新增/变动的文件。
超过 200MB 的文件跳过 —— 正常讲义/PPT不会这么大，多半是课程录像之类的，
不适合当"资料"下载管理。

运行：python3 canvas_materials.py                       # 只重新生成 materials.html
      python3 canvas_materials.py --register <course_id> <本地文件路径>   # 添加本地文件
      python3 canvas_materials.py --delete <material_id>                  # 删除一个文件
"""

import html
import json
import os
import shutil
import sqlite3
import sys

import requests

from canvas_dashboard import build_course_colors
from canvas_upcoming import TRACKED_COURSE_IDS

DB_PATH = "canvas.db"
MATERIALS_DIR = "materials"
OUTPUT_PATH = "materials.html"
MAX_FILE_SIZE = 200 * 1024 * 1024
LOCAL_MODULE_NAME = "我添加的文件"

BAD_CHARS = '/:\\*?"<>|'

FILE_TYPE_RULES = [
    (("pdf",), "PDF", "📄"),
    (("ppt", "pptx", "key"), "PPT", "📊"),
    (("doc", "docx", "pages"), "Word", "📝"),
    (("xls", "xlsx", "numbers", "csv"), "表格", "📈"),
    (("png", "jpg", "jpeg", "gif", "heic", "webp"), "图片", "🖼️"),
    (("zip", "rar", "7z"), "压缩包", "📦"),
    (("txt", "md"), "文本", "📃"),
    (("mp4", "mov", "m4v"), "视频", "🎬"),
    (("mp3", "wav", "m4a"), "音频", "🎵"),
]


def safe_folder_name(name):
    name = (name or "未命名").strip()
    cleaned = "".join(c for c in name if c not in BAD_CHARS)
    return cleaned or "未命名"


def human_size(num_bytes):
    if not num_bytes:
        return "-"
    for unit in ("B", "KB", "MB", "GB"):
        if num_bytes < 1024:
            return f"{num_bytes:.0f}{unit}" if unit == "B" else f"{num_bytes:.1f}{unit}"
        num_bytes /= 1024
    return f"{num_bytes:.1f}TB"


def file_type_info(filename):
    """按扩展名猜文件类型，用于"按类型查看"这个自动分类视图。"""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    for exts, label, icon in FILE_TYPE_RULES:
        if ext in exts:
            return label, icon
    return "其他", "📎"


def sync_materials(conn, base_url, headers, course_id, course_name, modules):
    """把这门课 Modules 里的 File 条目下载到本地，并把元数据写进 materials 表。"""
    course_dir = os.path.join(MATERIALS_DIR, safe_folder_name(course_name))

    for module in modules:
        module_name = module.get("name") or "未分类"
        items = sorted(module.get("items") or [], key=lambda i: i.get("position", 0))
        for item in items:
            if item.get("type") != "File":
                continue
            file_id = item.get("content_id")
            if not file_id:
                continue

            try:
                resp = requests.get(
                    f"{base_url.rstrip('/')}/api/v1/files/{file_id}",
                    headers=headers,
                    timeout=15,
                )
                resp.raise_for_status()
                info = resp.json()
            except requests.exceptions.RequestException:
                continue

            size = info.get("size") or 0
            if size > MAX_FILE_SIZE:
                continue
            download_url = info.get("url")
            display_name = info.get("display_name") or f"file_{file_id}"
            if not download_url:
                continue

            module_dir = os.path.join(course_dir, safe_folder_name(module_name))
            local_path = os.path.join(module_dir, display_name)

            existing = conn.execute(
                "SELECT size, local_path FROM materials WHERE id = ?", (file_id,)
            ).fetchone()
            needs_download = not (existing and existing[0] == size and os.path.exists(existing[1]))

            if needs_download:
                try:
                    os.makedirs(module_dir, exist_ok=True)
                    file_resp = requests.get(download_url, headers=headers, timeout=60)
                    file_resp.raise_for_status()
                    with open(local_path, "wb") as f:
                        f.write(file_resp.content)
                except (requests.exceptions.RequestException, OSError):
                    continue

            conn.execute(
                """INSERT OR REPLACE INTO materials
                   (id, course_id, module_name, filename, local_path, size, content_type, updated_at, source)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'canvas')""",
                (
                    file_id,
                    course_id,
                    module_name,
                    display_name,
                    os.path.abspath(local_path),
                    size,
                    info.get("content-type"),
                    info.get("updated_at"),
                ),
            )


def register_local_file(conn, course_id, course_name, source_path):
    """用户自己选的本地文件：真的拷贝一份进 materials/<课程>/我添加的文件/，
    再登记进数据库，用负数 id（跟 Canvas 真实文件 id 的正数空间区分开）。"""
    if not os.path.isfile(source_path):
        print(f"❌ 文件不存在：{source_path}")
        return

    filename = os.path.basename(source_path)
    module_dir = os.path.join(MATERIALS_DIR, safe_folder_name(course_name), safe_folder_name(LOCAL_MODULE_NAME))
    os.makedirs(module_dir, exist_ok=True)

    dest_path = os.path.join(module_dir, filename)
    if os.path.exists(dest_path):
        stem, ext = os.path.splitext(filename)
        counter = 2
        while os.path.exists(dest_path):
            dest_path = os.path.join(module_dir, f"{stem} ({counter}){ext}")
            counter += 1

    shutil.copy2(source_path, dest_path)

    row = conn.execute("SELECT MIN(id) FROM materials").fetchone()
    new_id = (row[0] - 1) if row and row[0] is not None and row[0] < 0 else -1

    conn.execute(
        """INSERT INTO materials (id, course_id, module_name, filename, local_path, size, content_type, updated_at, source)
           VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), 'local')""",
        (
            new_id,
            course_id,
            LOCAL_MODULE_NAME,
            os.path.basename(dest_path),
            os.path.abspath(dest_path),
            os.path.getsize(dest_path),
            None,
        ),
    )
    conn.commit()
    print(f"✅ 已添加本地文件：{dest_path}")


def delete_material(conn, material_id):
    row = conn.execute("SELECT local_path FROM materials WHERE id = ?", (material_id,)).fetchone()
    if not row:
        print(f"❌ 没有找到 id={material_id} 的文件记录")
        return
    local_path = row[0]
    if local_path and os.path.exists(local_path):
        try:
            os.remove(local_path)
        except OSError as e:
            print(f"⚠️ 删除本地文件失败：{e}")
    conn.execute("DELETE FROM materials WHERE id = ?", (material_id,))
    conn.commit()
    print(f"✅ 已删除：{local_path}")


def get_materials_by_course():
    if not TRACKED_COURSE_IDS:
        return []
    conn = sqlite3.connect(DB_PATH)
    placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
    rows = conn.execute(
        f"""SELECT c.id, c.name, m.id, m.module_name, m.filename, m.local_path, m.size, m.source
            FROM materials m JOIN courses c ON c.id = m.course_id
            WHERE m.course_id IN ({placeholders})
            ORDER BY c.name, m.module_name, m.filename""",
        TRACKED_COURSE_IDS,
    ).fetchall()
    conn.close()

    courses = {}
    order = []
    for course_id, course_name, material_id, module_name, filename, local_path, size, source in rows:
        if course_id not in courses:
            courses[course_id] = {"name": course_name, "modules": {}, "order": [], "files": []}
            order.append(course_id)
        c = courses[course_id]
        file_entry = {
            "id": material_id,
            "filename": filename,
            "local_path": local_path,
            "size": size,
            "source": source or "canvas",
            "module": module_name,
        }
        if module_name not in c["modules"]:
            c["modules"][module_name] = []
            c["order"].append(module_name)
        c["modules"][module_name].append(file_entry)
        c["files"].append(file_entry)
    return [(cid, courses[cid]) for cid in order]


def file_row_html(course_id, f):
    e = html.escape
    label, icon = file_type_info(f["filename"])
    search_key = e((f["filename"] + " " + f["module"]).lower())
    delete_btn = ""
    if f["source"] == "local":
        delete_btn = (
            f'<a class="delete-btn" href="canvasapp://delete?id={f["id"]}&course_id={course_id}" '
            f'title="删除这个文件">✕</a>'
        )
    local_badge = '<span class="local-badge">本地</span>' if f["source"] == "local" else ""
    return f'''<li class="file-row" data-search="{search_key}" data-type="{e(label)}">
      <a class="file-link" href="file://{e(f["local_path"])}" target="_blank" rel="noopener">
        <span class="file-icon">{icon}</span>
        <span class="file-name">{e(f["filename"])}</span>
      </a>
      {local_badge}
      <span class="file-size">{human_size(f["size"])}</span>
      {delete_btn}
    </li>'''


def build_course_block(course_id, course, color):
    e = html.escape
    text_color, bg_color = color

    # 按模块查看（跟 Canvas Modules 结构一致）
    by_module = "".join(
        f'<div class="module-block"><div class="module-title">{e(m)}</div>'
        f'<ul class="file-list">{"".join(file_row_html(course_id, f) for f in course["modules"][m])}</ul></div>'
        for m in course["order"]
    )

    # 按类型自动分类（不用手动整理，按文件扩展名自动分组）
    by_type = {}
    type_order = []
    for f in course["files"]:
        label, _ = file_type_info(f["filename"])
        if label not in by_type:
            by_type[label] = []
            type_order.append(label)
        by_type[label].append(f)
    by_type_html = "".join(
        f'<div class="module-block"><div class="module-title">{e(t)}（{len(by_type[t])}）</div>'
        f'<ul class="file-list">{"".join(file_row_html(course_id, f) for f in by_type[t])}</ul></div>'
        for t in type_order
    )

    return f'''
    <div class="drive-course" data-course-id="{course_id}">
      <div class="drive-course-header">
        <span class="course-badge" style="color:{text_color}; background:{bg_color};">{e(course["name"])}</span>
        <span class="file-count">{len(course["files"])} 个文件</span>
        <a class="btn-add" href="canvasapp://add?course_id={course_id}">＋ 添加文件</a>
      </div>
      <div class="view-by-module">{by_module}</div>
      <div class="view-by-type" hidden>{by_type_html}</div>
    </div>'''


def build_sidebar_html(data, course_colors):
    e = html.escape
    items = ['<div class="course-item active" data-course-id="all" data-course-name="全部课程">📁 全部课程</div>']
    for course_id, course in data:
        text_color, _ = course_colors.get(course["name"], ("#374151", "#e5e7eb"))
        items.append(
            f'<div class="course-item" data-course-id="{course_id}" data-course-name="{e(course["name"])}">'
            f'<span class="dot" style="background:{text_color};"></span>'
            f'<span class="name">{e(course["name"])}</span><span class="count">{len(course["files"])}</span></div>'
        )
    return "".join(items)


def build_html():
    data = get_materials_by_course()
    course_colors = build_course_colors([c["name"] for _, c in data])

    sidebar_html = build_sidebar_html(data, course_colors)
    course_blocks = "".join(
        build_course_block(cid, course, course_colors.get(course["name"], ("#374151", "#e5e7eb")))
        for cid, course in data
    )
    if not data:
        course_blocks = '<div class="empty">还没有同步到任何课程资料</div>'

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light dark">
<title>课程资料</title>
<style>
  :root {{
    --bg: #ffffff; --card-bg: #ffffff; --text: #0d0d0d; --muted: #6e6e80;
    --border: #e5e5e5; --hover: #f7f7f8; --accent: #0d0d0d; --accent-contrast: #ffffff;
    --sidebar-bg: #f7f7f8;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #212121; --card-bg: #2a2a2a; --text: #ececec; --muted: #9b9b9b;
      --border: #3a3a3a; --hover: #333333; --accent: #ececec; --accent-contrast: #171717;
      --sidebar-bg: #262626;
    }}
  }}
  * {{ box-sizing: border-box; }}
  html, body {{ height: 100%; }}
  body {{ margin: 0; background: var(--bg); color: var(--text);
    font-family: -apple-system, "PingFang SC", "Helvetica Neue", Arial, sans-serif; }}
  .drive {{ display: flex; height: 100vh; }}
  .drive-sidebar {{ width: 220px; flex-shrink: 0; background: var(--sidebar-bg); border-right: 1px solid var(--border);
    padding: 20px 12px; overflow-y: auto; }}
  .drive-sidebar h1 {{ font-size: 16px; font-weight: 600; margin: 0 0 16px; padding: 0 8px; }}
  #search-box {{ width: 100%; padding: 9px 14px; font-size: 13px; border: 1px solid var(--border);
    border-radius: 20px; background: var(--bg); color: var(--text); margin-bottom: 14px; }}
  #search-box::placeholder {{ color: var(--muted); }}
  #search-box:focus {{ outline: none; border-color: var(--muted); }}
  .course-item {{ display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 8px;
    font-size: 13px; cursor: pointer; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
  .course-item:hover {{ background: var(--hover); }}
  .course-item.active {{ background: var(--hover); font-weight: 600; }}
  .course-item .dot {{ width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }}
  .course-item .count {{ margin-left: auto; color: var(--muted); font-size: 11px; font-weight: 400; }}
  .drive-main {{ flex: 1; overflow-y: auto; padding: 24px 32px 60px; }}
  .drive-main-header {{ display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }}
  .drive-main-header h2 {{ font-size: 20px; font-weight: 600; margin: 0; flex: 1; }}
  .view-toggle {{ display: flex; background: var(--hover); border-radius: 10px; padding: 3px; }}
  .view-toggle button {{ border: none; background: none; padding: 6px 14px; font-size: 12px; border-radius: 8px;
    color: var(--muted); cursor: pointer; }}
  .view-toggle button.active {{ background: var(--card-bg); color: var(--text); box-shadow: 0 1px 2px rgba(0,0,0,0.08); }}
  .drive-course {{ margin-bottom: 32px; }}
  .drive-course-header {{ display: flex; align-items: center; gap: 12px; margin-bottom: 14px; }}
  .course-badge {{ font-size: 13px; font-weight: 700; padding: 4px 12px; border-radius: 999px; }}
  .file-count {{ color: var(--muted); font-size: 12px; }}
  .btn-add {{ margin-left: auto; font-size: 12px; font-weight: 600; text-decoration: none;
    color: var(--accent-contrast); background: var(--accent); padding: 6px 14px; border-radius: 999px; }}
  .btn-add:hover {{ opacity: 0.85; }}
  .module-block {{ margin-bottom: 14px; }}
  .module-title {{ font-size: 12px; font-weight: 600; color: var(--muted); margin-bottom: 8px; }}
  .file-list {{ list-style: none; margin: 0; padding: 0; background: var(--card-bg); border: 1px solid var(--border);
    border-radius: 16px; overflow: hidden; }}
  .file-row {{ display: flex; align-items: center; gap: 10px; padding: 10px 16px; border-bottom: 1px solid var(--border); }}
  .file-row:last-child {{ border-bottom: none; }}
  .file-row:hover {{ background: var(--hover); }}
  .file-link {{ display: flex; align-items: center; gap: 10px; color: var(--text); text-decoration: none;
    font-size: 14px; flex: 1; min-width: 0; }}
  .file-link:hover {{ text-decoration: underline; }}
  .file-icon {{ flex-shrink: 0; }}
  .file-name {{ overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }}
  .local-badge {{ font-size: 10px; color: var(--muted); border: 1px solid var(--border); border-radius: 999px;
    padding: 1px 7px; flex-shrink: 0; }}
  .file-size {{ color: var(--muted); font-size: 12px; flex-shrink: 0; }}
  .delete-btn {{ color: var(--muted); text-decoration: none; font-size: 13px; padding: 2px 4px; flex-shrink: 0; }}
  .delete-btn:hover {{ color: var(--overdue, #d1453b); }}
  .empty {{ margin: 60px 0; text-align: center; color: var(--muted); }}
</style>
</head>
<body>
<div class="drive">
  <div class="drive-sidebar">
    <h1>📁 课程资料</h1>
    <input id="search-box" type="text" placeholder="搜索全部课程的文件…" autocomplete="off">
    <div id="course-list">{sidebar_html}</div>
  </div>
  <div class="drive-main">
    <div class="drive-main-header">
      <h2 id="main-title">全部课程</h2>
      <div class="view-toggle">
        <button id="mode-module" class="active">按模块</button>
        <button id="mode-type">按类型</button>
      </div>
    </div>
    <div id="course-blocks">{course_blocks}</div>
    <div id="no-results" class="empty" style="display:none;">没有匹配的文件</div>
  </div>
</div>
<script>
(function() {{
  var searchBox = document.getElementById('search-box');
  var courseItems = Array.prototype.slice.call(document.querySelectorAll('.course-item'));
  var courseBlocks = Array.prototype.slice.call(document.querySelectorAll('.drive-course'));
  var mainTitle = document.getElementById('main-title');
  var modeModuleBtn = document.getElementById('mode-module');
  var modeTypeBtn = document.getElementById('mode-type');
  var noResults = document.getElementById('no-results');
  var currentCourse = 'all';
  var viewMode = 'module';

  function applyCourseFilter() {{
    courseBlocks.forEach(function(block) {{
      var match = currentCourse === 'all' || block.getAttribute('data-course-id') === currentCourse;
      block.style.display = match ? '' : 'none';
    }});
  }}

  function applyViewMode() {{
    Array.prototype.slice.call(document.querySelectorAll('.view-by-module')).forEach(function(el) {{
      el.hidden = viewMode !== 'module';
    }});
    Array.prototype.slice.call(document.querySelectorAll('.view-by-type')).forEach(function(el) {{
      el.hidden = viewMode !== 'type';
    }});
  }}

  function applySearch() {{
    var q = searchBox.value.trim().toLowerCase();
    if (!q) {{
      applyCourseFilter();
      Array.prototype.slice.call(document.querySelectorAll('.file-row')).forEach(function(r) {{ r.style.display = ''; }});
      Array.prototype.slice.call(document.querySelectorAll('.module-block')).forEach(function(b) {{ b.style.display = ''; }});
      noResults.style.display = 'none';
      return;
    }}
    // 搜索时忽略课程筛选，跟网盘的全局搜索一样，哪个课程都能搜到
    var anyVisible = false;
    Array.prototype.slice.call(document.querySelectorAll('.file-row')).forEach(function(row) {{
      var match = (row.getAttribute('data-search') || '').indexOf(q) !== -1;
      row.style.display = match ? '' : 'none';
      if (match) anyVisible = true;
    }});
    Array.prototype.slice.call(document.querySelectorAll('.module-block')).forEach(function(block) {{
      var visible = Array.prototype.slice.call(block.querySelectorAll('.file-row'))
        .some(function(r) {{ return r.style.display !== 'none'; }});
      block.style.display = visible ? '' : 'none';
    }});
    courseBlocks.forEach(function(block) {{
      var visible = Array.prototype.slice.call(block.querySelectorAll('.file-row'))
        .some(function(r) {{ return r.style.display !== 'none'; }});
      block.style.display = visible ? '' : 'none';
    }});
    noResults.style.display = anyVisible ? 'none' : '';
  }}

  courseItems.forEach(function(item) {{
    item.addEventListener('click', function() {{
      courseItems.forEach(function(i) {{ i.classList.remove('active'); }});
      item.classList.add('active');
      currentCourse = item.getAttribute('data-course-id');
      mainTitle.textContent = item.getAttribute('data-course-name');
      searchBox.value = '';
      applyCourseFilter();
    }});
  }});

  modeModuleBtn.addEventListener('click', function() {{
    viewMode = 'module';
    modeModuleBtn.classList.add('active');
    modeTypeBtn.classList.remove('active');
    applyViewMode();
  }});
  modeTypeBtn.addEventListener('click', function() {{
    viewMode = 'type';
    modeTypeBtn.classList.add('active');
    modeModuleBtn.classList.remove('active');
    applyViewMode();
  }});

  searchBox.addEventListener('input', applySearch);
  applyCourseFilter();
}})();
</script>
</body>
</html>"""


def generate():
    content = build_html()
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✅ 资料页已生成：{OUTPUT_PATH}")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--register" and len(args) >= 3:
        course_id = int(args[1])
        source_path = args[2]
        conn = sqlite3.connect(DB_PATH)
        course_row = conn.execute("SELECT name FROM courses WHERE id = ?", (course_id,)).fetchone()
        course_name = course_row[0] if course_row else str(course_id)
        register_local_file(conn, course_id, course_name, source_path)
        conn.close()
        generate()
    elif args and args[0] == "--delete" and len(args) >= 2:
        material_id = int(args[1])
        conn = sqlite3.connect(DB_PATH)
        delete_material(conn, material_id)
        conn.close()
        generate()
    else:
        generate()


if __name__ == "__main__":
    main()
