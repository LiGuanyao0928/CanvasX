"""
Canvas 作业仪表盘
生成一个本地网页（dashboard.html），每个作业一张卡片，
作业要求（Assignment 自己的说明文字 + Modules 里紧挨着的附件文件）
直接展开显示在卡片里（不用再点进 Canvas 才能看），
"去 Canvas 提交" 按钮点击后跳转到对应作业的提交页。

运行：python3 canvas_dashboard.py          # 生成后自动用 Safari 打开
      python3 canvas_dashboard.py 14       # 看未来14天，默认30天
      python3 canvas_dashboard.py --no-open
"""

import html
import re
import subprocess
import sys
from datetime import datetime, timezone

from assignment_types import label_for as type_label_for
from canvas_upcoming import get_upcoming, get_unspecified

OUTPUT_PATH = "dashboard.html"

SCRIPT_RE = re.compile(r"<script.*?</script>", re.IGNORECASE | re.DOTALL)
TAG_RE = re.compile(r"<[^>]+>")


def urgency_class(due):
    now = datetime.now(timezone.utc)
    hours_left = (due - now).total_seconds() / 3600
    if hours_left < 0:
        return "overdue"
    if hours_left < 48:
        return "urgent"
    if hours_left < 24 * 7:
        return "soon"
    return "normal"


def sanitize_description(description):
    """去掉 <script>，Canvas 作业说明本身是老师写的富文本，其它标签直接展示。"""
    return SCRIPT_RE.sub("", description or "")


def has_visible_text(html_fragment):
    return bool(TAG_RE.sub("", html_fragment).strip())


def files_html(files):
    if not files:
        return ""
    e = html.escape
    items = "".join(
        f'<li><a href="{e(file_url)}" target="_blank" rel="noopener">📎 {e(title or "附件")}</a></li>'
        for title, file_url in files
    )
    return f'<ul class="card-files">{items}</ul>'


def short_course_name(course_name):
    """"202609 - Fluid Mechanics - 44292" -> "Fluid Mechanics"，用于筛选下拉框，别的地方还是用全名。"""
    name = re.sub(r"^\d+\s*-\s*", "", course_name or "")
    name = re.sub(r"\s*-\s*[^-]+$", "", name)
    return name.strip() or course_name or ""


# 每门课固定分配一个颜色，让卡片上的课程标签一眼能区分开。
# 超过调色板数量时循环使用。
COURSE_COLOR_PALETTE = [
    ("#1d4ed8", "#dbeafe"),  # 蓝
    ("#7c3aed", "#ede9fe"),  # 紫
    ("#0f766e", "#ccfbf1"),  # 青
    ("#be185d", "#fce7f3"),  # 玫红
    ("#b45309", "#fef3c7"),  # 琥珀
    ("#4338ca", "#e0e7ff"),  # 靛蓝
]


def build_course_colors(course_names):
    """course_name（全名）-> (文字色, 背景色)，按第一次出现的顺序固定分配。"""
    colors = {}
    for i, name in enumerate(course_names):
        colors[name] = COURSE_COLOR_PALETTE[i % len(COURSE_COLOR_PALETTE)]
    return colors


URGENCY_LABELS = {
    "overdue": "已过期",
    "urgent": "48小时内",
    "soon": "一周内",
    "normal": "一周以后",
    "unspecified": "日期未知",
}


def search_text(course_name, assignment_name, description, files):
    plain_desc = TAG_RE.sub(" ", description or "")
    file_titles = " ".join(title or "" for title, _ in (files or []))
    combined = " ".join([course_name or "", assignment_name or "", plain_desc, file_titles])
    return re.sub(r"\s+", " ", combined).strip().lower()


def card_html(
    course_name, assignment_name, url, date_label, css_class,
    description=None, guessed=False, files=None, submission_type=None, course_color=None,
):
    e = html.escape
    submit_url = f"{url}#submit"
    guess_badge = '<span class="badge">猜测日期</span>' if guessed else ""
    type_label = type_label_for(submission_type)
    type_badge = f'<span class="badge">{e(type_label)}</span>'

    safe_desc = sanitize_description(description)
    parts = []
    if has_visible_text(safe_desc):
        parts.append(f'<div class="card-desc">{safe_desc}</div>')
    parts.append(files_html(files))
    if not parts or not any(parts):
        parts.append('<div class="card-desc card-desc-empty">Canvas 上没有写作业说明文字，也没有挂载文件</div>')
    desc_html = "".join(parts)

    data_search = e(search_text(course_name, assignment_name, description, files))
    data_course = e(short_course_name(course_name))
    data_type = e(type_label)

    text_color, bg_color = course_color or ("#374151", "#e5e7eb")
    course_style = f"color:{text_color}; background:{bg_color};"

    return f"""
    <div class="card {css_class}" data-search="{data_search}" data-course="{data_course}" data-urgency="{css_class}" data-type="{data_type}">
      <div class="card-course" style="{course_style}">{e(short_course_name(course_name))}</div>
      <div class="card-date">{e(date_label)} {guess_badge} {type_badge}</div>
      <div class="card-title">{e(assignment_name)}</div>
      <details class="card-req" open>
        <summary>作业要求</summary>
        {desc_html}
      </details>
      <div class="card-actions">
        <a class="btn btn-submit" href="{e(submit_url)}" target="_blank" rel="noopener">去 Canvas 提交</a>
      </div>
    </div>"""


def checkbox_group(name, options):
    """options: [(value, label), ...]"""
    e = html.escape
    return "".join(
        f'''<label class="chip">
          <input type="checkbox" data-filter-group="{name}" value="{e(value)}">
          <span>{e(label)}</span>
        </label>'''
        for value, label in options
    )


def build_html(days):
    upcoming = get_upcoming(days)
    unspecified = get_unspecified()

    # 先扫一遍拿到课程出现顺序，固定分配颜色，再正式生成卡片。
    course_order = []
    for row in upcoming:
        if row[1] not in course_order:
            course_order.append(row[1])
    for row in unspecified:
        if row[0] not in course_order:
            course_order.append(row[0])
    course_colors = build_course_colors(course_order)

    cards = []
    course_names_seen = []
    urgencies_seen = []
    types_seen = []
    for due, course_name, assignment_name, url, guessed, description, files, submission_type in upcoming:
        local_due = due.astimezone()
        label = local_due.strftime("%m月%d日 %H:%M")
        css_class = urgency_class(due)
        cards.append(
            card_html(
                course_name, assignment_name, url, label, css_class, description, guessed, files,
                submission_type, course_colors.get(course_name),
            )
        )
        if course_name not in course_names_seen:
            course_names_seen.append(course_name)
        if css_class not in urgencies_seen:
            urgencies_seen.append(css_class)
        type_label = type_label_for(submission_type)
        if type_label not in types_seen:
            types_seen.append(type_label)

    unspecified_cards = []
    for course_name, assignment_name, url, description, files, submission_type in unspecified:
        unspecified_cards.append(
            card_html(
                course_name, assignment_name, url, "日期未知", "unspecified", description,
                files=files, submission_type=submission_type, course_color=course_colors.get(course_name),
            )
        )
        if course_name not in course_names_seen:
            course_names_seen.append(course_name)
        type_label = type_label_for(submission_type)
        if type_label not in types_seen:
            types_seen.append(type_label)
    if unspecified_cards:
        urgencies_seen.append("unspecified")

    course_checkboxes = checkbox_group(
        "course", [(short_course_name(c), short_course_name(c)) for c in course_names_seen]
    )
    urgency_order = ["overdue", "urgent", "soon", "normal", "unspecified"]
    urgency_checkboxes = checkbox_group(
        "urgency", [(u, URGENCY_LABELS[u]) for u in urgency_order if u in urgencies_seen]
    )
    type_checkboxes = checkbox_group("type", [(t, t) for t in types_seen])

    generated_at = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M")

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light dark">
<title>Canvas 作业追踪</title>
<style>
  :root {{
    --bg: #ffffff;
    --card-bg: #ffffff;
    --text: #0d0d0d;
    --muted: #6e6e80;
    --border: #e5e5e5;
    --hover: #f7f7f8;
    --accent: #0d0d0d;
    --accent-contrast: #ffffff;
    --overdue: #d1453b;
    --urgent: #d97a34;
    --soon: #b8912f;
    --normal: #5e5e6e;
    --unspecified: #9a9aa5;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #212121;
      --card-bg: #2a2a2a;
      --text: #ececec;
      --muted: #9b9b9b;
      --border: #3a3a3a;
      --hover: #333333;
      --accent: #ececec;
      --accent-contrast: #171717;
      --overdue: #f2726a;
      --urgent: #f0a262;
      --soon: #e0c168;
      --normal: #a9a9b8;
      --unspecified: #7a7a84;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    position: relative;
    margin: 0;
    padding: 40px 24px 100px;
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, "PingFang SC", "Helvetica Neue", Arial, sans-serif;
  }}
  .page {{
    max-width: 720px;
    margin: 0 auto;
    transition: max-width 0.15s;
  }}
  .page.two-col {{
    max-width: 1080px;
  }}
  .header {{
    margin: 0 0 28px;
  }}
  h1 {{
    font-size: 24px;
    font-weight: 600;
    letter-spacing: -0.01em;
    margin: 0 0 6px;
  }}
  .meta {{
    color: var(--muted);
    font-size: 13px;
    margin-bottom: 20px;
  }}
  #search-box {{
    width: 100%;
    padding: 12px 18px;
    font-size: 14px;
    border: 1px solid var(--border);
    border-radius: 26px;
    background: var(--card-bg);
    color: var(--text);
    box-sizing: border-box;
  }}
  #search-box::placeholder {{ color: var(--muted); }}
  #search-box:focus {{
    outline: none;
    border-color: var(--muted);
  }}
  .search-row {{
    display: flex;
    gap: 8px;
  }}
  .search-row #search-box {{
    flex: 1;
  }}
  .filter-toggle {{
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 0 18px;
    font-size: 13px;
    font-weight: 500;
    color: var(--text);
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 26px;
    cursor: pointer;
    white-space: nowrap;
  }}
  .filter-toggle:hover {{ background: var(--hover); }}
  .filter-toggle.active {{ border-color: var(--text); }}
  .filter-badge {{
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 18px;
    height: 18px;
    padding: 0 5px;
    font-size: 11px;
    font-weight: 700;
    color: var(--accent-contrast);
    background: var(--accent);
    border-radius: 999px;
  }}
  .filter-panel {{
    margin-top: 12px;
    padding: 18px;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 16px;
  }}
  .filter-group {{
    margin-bottom: 16px;
  }}
  .filter-group:last-of-type {{
    margin-bottom: 16px;
  }}
  .filter-group-title {{
    font-size: 11px;
    font-weight: 600;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin-bottom: 10px;
  }}
  .chip-row {{
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }}
  .chip {{
    display: inline-flex;
    align-items: center;
    padding: 6px 14px;
    font-size: 13px;
    color: var(--text);
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 999px;
    cursor: pointer;
    user-select: none;
  }}
  .chip input {{
    position: absolute;
    opacity: 0;
    width: 0;
    height: 0;
  }}
  .chip:has(input:checked) {{
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-contrast);
  }}
  .filter-clear {{
    font-size: 13px;
    font-weight: 500;
    color: var(--muted);
    background: none;
    border: none;
    cursor: pointer;
    padding: 0;
  }}
  .filter-clear:hover {{ color: var(--text); text-decoration: underline; }}
  .layout-fab {{
    position: fixed;
    bottom: 28px;
    right: 28px;
    display: flex;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 4px;
    box-shadow: 0 4px 16px rgba(0,0,0,0.12);
  }}
  .layout-fab .seg {{
    width: 34px;
    height: 34px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    border-radius: 10px;
    color: var(--muted);
    cursor: pointer;
  }}
  .layout-fab .seg:hover {{ background: var(--hover); }}
  .layout-fab .seg.active {{
    background: var(--accent);
    color: var(--accent-contrast);
  }}
  .layout-fab .seg.active:hover {{ background: var(--accent); }}
  .section-title {{
    margin: 36px 0 14px;
    font-size: 14px;
    font-weight: 600;
    color: var(--muted);
  }}
  .grid {{
    display: grid;
    grid-template-columns: 1fr;
    gap: 12px;
  }}
  .page.two-col .grid {{
    grid-template-columns: 1fr 1fr;
  }}
  .card {{
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-left: 4px solid var(--normal);
    border-radius: 16px;
    padding: 18px 20px;
  }}
  .card.overdue {{ border-left-color: var(--overdue); }}
  .card.urgent {{ border-left-color: var(--urgent); }}
  .card.soon {{ border-left-color: var(--soon); }}
  .card.unspecified {{ border-left-color: var(--unspecified); opacity: 0.85; }}
  .card-date {{
    font-size: 12px;
    font-weight: 600;
    color: var(--muted);
    margin-bottom: 6px;
  }}
  .card.overdue .card-date {{ color: var(--overdue); }}
  .card.urgent .card-date {{ color: var(--urgent); }}
  .card.soon .card-date {{ color: var(--soon); }}
  .badge {{
    display: inline-block;
    font-size: 11px;
    font-weight: 500;
    color: var(--muted);
    background: var(--hover);
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 2px 9px;
    margin-left: 6px;
  }}
  .card-course {{
    display: inline-block;
    font-size: 12px;
    font-weight: 700;
    padding: 3px 11px;
    border-radius: 999px;
    margin-bottom: 10px;
  }}
  .card-title {{
    font-size: 15px;
    font-weight: 600;
    line-height: 1.4;
    margin-bottom: 10px;
  }}
  .card-req {{
    margin-bottom: 12px;
  }}
  .card-req summary {{
    cursor: pointer;
    font-size: 13px;
    font-weight: 500;
    color: var(--muted);
    list-style: revert;
  }}
  .card-desc {{
    margin-top: 10px;
    padding: 12px 16px;
    background: var(--hover);
    border-radius: 12px;
    font-size: 14px;
    line-height: 1.65;
    color: var(--text);
    max-width: 100%;
    overflow-wrap: break-word;
  }}
  .card-desc img {{ max-width: 100%; height: auto; border-radius: 8px; }}
  .card-desc-empty {{
    color: var(--muted);
    font-style: italic;
  }}
  .card-files {{
    list-style: none;
    margin: 10px 0 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }}
  .card-files a {{
    color: var(--text);
    text-decoration: none;
    font-size: 14px;
  }}
  .card-files a:hover {{ text-decoration: underline; }}
  .card-actions {{
    display: flex;
    gap: 10px;
  }}
  .btn {{
    display: inline-block;
    text-decoration: none;
    font-size: 13px;
    font-weight: 600;
    padding: 8px 18px;
    border-radius: 999px;
    transition: opacity 0.15s;
  }}
  .btn:hover {{ opacity: 0.8; }}
  .btn-submit {{
    background: var(--accent);
    color: var(--accent-contrast);
  }}
  .empty {{
    margin: 48px 0;
    text-align: center;
    color: var(--muted);
  }}
</style>
</head>
<body>
<div class="page" id="page">
  <div class="header">
    <h1>📚 Canvas 作业追踪</h1>
    <div class="meta">更新时间 {generated_at} · 未来 {days} 天</div>
    <div class="search-row">
      <input id="search-box" type="text" placeholder="搜索作业标题 / 课程 / 说明文字 / 附件名…" autocomplete="off">
      <button id="filter-toggle" type="button" class="filter-toggle">
        筛选<span id="filter-badge" class="filter-badge" hidden>0</span>
      </button>
    </div>

    <div id="filter-panel" class="filter-panel" hidden>
      <div class="filter-group">
        <div class="filter-group-title">课程</div>
        <div class="chip-row">{course_checkboxes}</div>
      </div>
      <div class="filter-group">
        <div class="filter-group-title">状态</div>
        <div class="chip-row">{urgency_checkboxes}</div>
      </div>
      <div class="filter-group">
        <div class="filter-group-title">类型</div>
        <div class="chip-row">{type_checkboxes}</div>
      </div>
      <button id="filter-clear" type="button" class="filter-clear">清除筛选</button>
    </div>
  </div>

  <div id="sections">
    <div id="section-upcoming">
      {"<div class='section-title'>即将到期</div><div class='grid'>" + "".join(cards) + "</div>" if cards else "<div class='empty'>未来 " + str(days) + " 天内没有要交的作业 🎉</div>"}
    </div>

    <div id="section-unspecified">
      {"<div class='section-title'>日期未知（Canvas 没写，文字里也找不到）</div><div class='grid'>" + "".join(unspecified_cards) + "</div>" if unspecified_cards else ""}
    </div>
  </div>

  <div id="no-results" class="empty" style="display:none;">没有匹配的作业</div>

  <div class="layout-fab" role="group" aria-label="布局切换">
    <button id="layout-one" type="button" class="seg" title="单栏显示" aria-pressed="false">
      <svg viewBox="0 0 10 10" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6">
        <rect x="0.8" y="0.8" width="8.4" height="8.4" rx="1.6"></rect>
      </svg>
    </button>
    <button id="layout-two" type="button" class="seg" title="双栏显示" aria-pressed="false">
      <svg viewBox="0 0 20 10" width="18" height="9" fill="none" stroke="currentColor" stroke-width="1.6">
        <rect x="0.8" y="0.8" width="8.4" height="8.4" rx="1.6"></rect>
        <rect x="10.8" y="0.8" width="8.4" height="8.4" rx="1.6"></rect>
      </svg>
    </button>
  </div>
</div>

<script>
(function() {{
  var input = document.getElementById('search-box');
  var toggleBtn = document.getElementById('filter-toggle');
  var panel = document.getElementById('filter-panel');
  var badge = document.getElementById('filter-badge');
  var clearBtn = document.getElementById('filter-clear');
  var checkboxes = Array.prototype.slice.call(document.querySelectorAll('#filter-panel input[type=checkbox]'));
  var cards = Array.prototype.slice.call(document.querySelectorAll('.card'));
  var sectionTitles = Array.prototype.slice.call(document.querySelectorAll('.section-title'));
  var noResults = document.getElementById('no-results');

  function checkedValues(group) {{
    return checkboxes
      .filter(function(cb) {{ return cb.getAttribute('data-filter-group') === group && cb.checked; }})
      .map(function(cb) {{ return cb.value; }});
  }}

  function applyFilter() {{
    var q = input.value.trim().toLowerCase();
    var courses = checkedValues('course');
    var urgencies = checkedValues('urgency');
    var types = checkedValues('type');
    var checkedCount = courses.length + urgencies.length + types.length;
    var anyFilterActive = !!(q || checkedCount);
    var visibleCount = 0;

    badge.textContent = checkedCount;
    badge.hidden = checkedCount === 0;

    cards.forEach(function(card) {{
      var matchQ = !q || (card.getAttribute('data-search') || '').indexOf(q) !== -1;
      var matchCourse = !courses.length || courses.indexOf(card.getAttribute('data-course')) !== -1;
      var matchUrgency = !urgencies.length || urgencies.indexOf(card.getAttribute('data-urgency')) !== -1;
      var matchType = !types.length || types.indexOf(card.getAttribute('data-type')) !== -1;
      var match = matchQ && matchCourse && matchUrgency && matchType;
      card.style.display = match ? '' : 'none';
      if (match) visibleCount++;
    }});

    sectionTitles.forEach(function(title) {{
      var grid = title.nextElementSibling;
      if (!grid) return;
      var anyVisible = Array.prototype.slice.call(grid.querySelectorAll('.card'))
        .some(function(c) {{ return c.style.display !== 'none'; }});
      title.style.display = anyVisible ? '' : 'none';
      grid.style.display = anyVisible ? '' : 'none';
    }});

    noResults.style.display = (anyFilterActive && visibleCount === 0) ? '' : 'none';
  }}

  input.addEventListener('input', applyFilter);
  checkboxes.forEach(function(cb) {{ cb.addEventListener('change', applyFilter); }});

  toggleBtn.addEventListener('click', function() {{
    panel.hidden = !panel.hidden;
    toggleBtn.classList.toggle('active', !panel.hidden);
  }});

  clearBtn.addEventListener('click', function() {{
    checkboxes.forEach(function(cb) {{ cb.checked = false; }});
    applyFilter();
  }});

  // 单栏/双栏分段开关（右下角悬浮），记住上次选择（只存在这个浏览器里，仅为了体验，不影响功能）
  var page = document.getElementById('page');
  var oneBtn = document.getElementById('layout-one');
  var twoBtn = document.getElementById('layout-two');

  function readStoredLayout() {{
    try {{
      return localStorage.getItem('canvas-dashboard-columns');
    }} catch (e) {{
      return null;
    }}
  }}

  function storeLayout(value) {{
    try {{
      localStorage.setItem('canvas-dashboard-columns', value);
    }} catch (e) {{
      // 存不了就算了（比如隐私模式），不影响当次使用
    }}
  }}

  function setLayout(twoCol) {{
    page.classList.toggle('two-col', twoCol);
    oneBtn.classList.toggle('active', !twoCol);
    oneBtn.setAttribute('aria-pressed', twoCol ? 'false' : 'true');
    twoBtn.classList.toggle('active', twoCol);
    twoBtn.setAttribute('aria-pressed', twoCol ? 'true' : 'false');
  }}

  setLayout(readStoredLayout() === 'two');

  oneBtn.addEventListener('click', function() {{
    setLayout(false);
    storeLayout('one');
  }});
  twoBtn.addEventListener('click', function() {{
    setLayout(true);
    storeLayout('two');
  }});
}})();
</script>
</body>
</html>"""


def generate(days, auto_open=True):
    content = build_html(days)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✅ 仪表盘已生成：{OUTPUT_PATH}")
    if auto_open:
        subprocess.run(["open", "-a", "Safari", OUTPUT_PATH])


def main():
    args = sys.argv[1:]
    auto_open = "--no-open" not in args
    args = [a for a in args if a != "--no-open"]
    days = int(args[0]) if args else 30
    generate(days, auto_open=auto_open)


if __name__ == "__main__":
    main()
