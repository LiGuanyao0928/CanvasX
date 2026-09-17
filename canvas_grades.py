"""
成绩 / What-if 计算器
从本地数据库读取已同步的作业成绩（同步时用 Canvas 的 include[]=submission
一起拉回来的），按每门课自己的作业分组权重算出"当前成绩"，并生成一个可以
手动填未出分作业"假设分数"、实时看总成绩会变成多少的网页（grades.html）。

简化规则（比 Canvas 自己的算法简单一些，够个人查看用）：
- 只按 assignment_group 的 group_weight 加权，不处理"丢弃最低/最高分"
  这类更细的分组规则（Canvas 支持，但要看具体课程有没有设置，真遇到了
  发现算出来的成绩跟 Canvas 网页对不上再加）。
- 一个分组里如果一门都还没出分，这个分组不计入当前成绩的加权分母——
  不然学期初大多数分组都是 0 分，会把"当前成绩"拉得很难看，这也是
  Canvas 自己"当前成绩"的算法惯例。
- 独立 Quiz（负数 id，没有 assignment_group）不参与成绩计算，只在
  作业看板里显示。

运行：python3 canvas_grades.py   # 单独重新生成 grades.html
"""

import html
import json
import sqlite3

from canvas_dashboard import build_course_colors
from canvas_upcoming import TRACKED_COURSE_IDS

DB_PATH = "canvas.db"
OUTPUT_PATH = "grades.html"


def get_grade_data():
    if not TRACKED_COURSE_IDS:
        return []
    conn = sqlite3.connect(DB_PATH)
    placeholders = ",".join("?" * len(TRACKED_COURSE_IDS))
    courses = conn.execute(
        f"SELECT id, name, apply_group_weights FROM courses WHERE id IN ({placeholders})",
        TRACKED_COURSE_IDS,
    ).fetchall()

    data = []
    for course_id, course_name, apply_group_weights in courses:
        groups = conn.execute(
            "SELECT id, name, group_weight FROM assignment_groups WHERE course_id = ?",
            (course_id,),
        ).fetchall()
        assignments = conn.execute(
            """SELECT name, assignment_group_id, points_possible, score, workflow_state, due_at
               FROM assignments
               WHERE course_id = ? AND id > 0 AND points_possible IS NOT NULL AND points_possible > 0
               ORDER BY due_at IS NULL, due_at""",
            (course_id,),
        ).fetchall()
        if not assignments:
            continue
        data.append(
            {
                "id": course_id,
                "name": course_name,
                "weighted": bool(apply_group_weights),
                "groups": [{"id": g[0], "name": g[1], "weight": g[2]} for g in groups],
                "assignments": [
                    {
                        "name": a[0],
                        "group_id": a[1],
                        "points_possible": a[2],
                        "score": a[3],
                        "workflow_state": a[4],
                        "due_at": a[5],
                    }
                    for a in assignments
                ],
            }
        )
    conn.close()
    return data


def build_course_section(course, color):
    e = html.escape
    text_color, bg_color = color
    group_names = {g["id"]: g["name"] for g in course["groups"]}

    rows = []
    for a in course["assignments"]:
        group_label = group_names.get(a["group_id"], "未分组")
        score_value = "" if a["score"] is None else a["score"]
        state_label = {
            "graded": "已出分",
            "submitted": "已交，待批改",
            "unsubmitted": "未提交",
            "pending_review": "待复核",
            "excused": "已豁免",
        }.get(a["workflow_state"], "未提交")
        rows.append(f'''
        <tr>
          <td>{e(a["name"])}</td>
          <td class="muted">{e(group_label)}</td>
          <td class="muted">{e(state_label)}</td>
          <td class="score-cell">
            <input type="number" class="score-input" step="any"
                   data-points="{a["points_possible"]}" data-group="{e(str(a["group_id"]))}"
                   data-real="{score_value}" value="{score_value}"> / {a["points_possible"]:g}
          </td>
        </tr>''')

    groups_json = html.escape(json.dumps(course["groups"]), quote=True)

    return f'''
    <div class="course-section" data-weighted="{"1" if course["weighted"] else "0"}" data-groups="{groups_json}">
      <div class="course-header" style="color:{text_color}; background:{bg_color};">{e(course["name"])}</div>
      <div class="grade-summary">
        <div class="grade-box"><div class="grade-label">当前成绩</div><div class="grade-value current-grade">-</div></div>
        <div class="grade-box"><div class="grade-label">假设成绩</div><div class="grade-value whatif-grade">-</div></div>
        <button type="button" class="reset-btn">重置假设</button>
      </div>
      <table class="grade-table">
        <thead><tr><th>作业</th><th>分组</th><th>状态</th><th>得分</th></tr></thead>
        <tbody>{"".join(rows)}</tbody>
      </table>
    </div>'''


def build_html():
    data = get_grade_data()
    course_colors = build_course_colors([c["name"] for c in data])
    sections = "".join(build_course_section(c, course_colors.get(c["name"], ("#374151", "#e5e7eb"))) for c in data)
    if not data:
        sections = '<div class="empty">还没有已出分的作业</div>'

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light dark">
<title>成绩</title>
<style>
  :root {{
    --bg: #ffffff; --card-bg: #ffffff; --text: #0d0d0d; --muted: #6e6e80;
    --border: #e5e5e5; --hover: #f7f7f8; --accent: #0d0d0d; --accent-contrast: #ffffff;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #212121; --card-bg: #2a2a2a; --text: #ececec; --muted: #9b9b9b;
      --border: #3a3a3a; --hover: #333333; --accent: #ececec; --accent-contrast: #171717;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; padding: 40px 24px 60px; background: var(--bg); color: var(--text);
    font-family: -apple-system, "PingFang SC", "Helvetica Neue", Arial, sans-serif; }}
  .page {{ max-width: 720px; margin: 0 auto; }}
  h1 {{ font-size: 24px; font-weight: 600; letter-spacing: -0.01em; margin: 0 0 6px; }}
  .hint {{ color: var(--muted); font-size: 13px; margin-bottom: 24px; line-height: 1.6; }}
  .course-section {{ margin-bottom: 20px; background: var(--card-bg); border: 1px solid var(--border);
    border-radius: 16px; padding: 20px 22px; }}
  .course-header {{ display: inline-block; font-size: 13px; font-weight: 700; padding: 4px 12px;
    border-radius: 999px; margin-bottom: 16px; }}
  .grade-summary {{ display: flex; align-items: center; gap: 20px; margin-bottom: 16px; flex-wrap: wrap; }}
  .grade-box {{ display: flex; flex-direction: column; }}
  .grade-label {{ font-size: 12px; color: var(--muted); }}
  .grade-value {{ font-size: 22px; font-weight: 600; }}
  .reset-btn {{ margin-left: auto; font-size: 13px; padding: 7px 16px; border-radius: 999px;
    border: 1px solid var(--border); background: var(--bg); color: var(--text); cursor: pointer; }}
  .reset-btn:hover {{ background: var(--hover); }}
  .grade-table {{ width: 100%; border-collapse: collapse; font-size: 14px; }}
  .grade-table th {{ text-align: left; font-size: 11px; color: var(--muted); font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.03em; padding: 8px; border-bottom: 1px solid var(--border); }}
  .grade-table td {{ padding: 10px 8px; border-bottom: 1px solid var(--border); }}
  .grade-table tr:last-child td {{ border-bottom: none; }}
  .muted {{ color: var(--muted); font-size: 13px; }}
  .score-cell {{ white-space: nowrap; }}
  .score-input {{ width: 60px; padding: 5px 8px; border: 1px solid var(--border); border-radius: 8px;
    background: var(--bg); color: var(--text); font-size: 14px; text-align: right; }}
  .score-input:focus {{ outline: none; border-color: var(--muted); }}
  .empty {{ margin: 60px 0; text-align: center; color: var(--muted); }}
</style>
</head>
<body>
<div class="page">
  <h1>📊 成绩</h1>
  <div class="hint">得分框可以直接改数字试算"假设成绩"——比如还没出分的作业先填个预期分数，看看总成绩会变多少。改动不会传回 Canvas。</div>
  {sections}
</div>
<script>
(function() {{
  var sections = Array.prototype.slice.call(document.querySelectorAll('.course-section'));

  function computeGrade(section, useHypothetical) {{
    var weighted = section.getAttribute('data-weighted') === '1';
    var groups = JSON.parse(section.getAttribute('data-groups'));
    var inputs = Array.prototype.slice.call(section.querySelectorAll('.score-input'));

    var byGroup = {{}};
    groups.forEach(function(g) {{ byGroup[g.id] = {{ weight: g.weight || 0, earned: 0, possible: 0 }}; }});

    var totalEarned = 0, totalPossible = 0;

    inputs.forEach(function(input) {{
      var points = parseFloat(input.getAttribute('data-points'));
      var real = input.getAttribute('data-real');
      var raw = useHypothetical ? input.value : real;
      if (raw === '' || raw === null || isNaN(parseFloat(raw))) return;
      var score = parseFloat(raw);
      var groupId = input.getAttribute('data-group');

      totalEarned += score;
      totalPossible += points;
      if (byGroup[groupId]) {{
        byGroup[groupId].earned += score;
        byGroup[groupId].possible += points;
      }}
    }});

    if (weighted && groups.length) {{
      var weightedSum = 0, weightUsed = 0;
      Object.keys(byGroup).forEach(function(gid) {{
        var g = byGroup[gid];
        if (g.possible > 0) {{
          weightedSum += (g.earned / g.possible) * g.weight;
          weightUsed += g.weight;
        }}
      }});
      if (weightUsed === 0) return null;
      return (weightedSum / weightUsed) * 100;
    }}

    if (totalPossible === 0) return null;
    return (totalEarned / totalPossible) * 100;
  }}

  function refresh(section) {{
    var current = computeGrade(section, false);
    var whatif = computeGrade(section, true);
    var currentEl = section.querySelector('.current-grade');
    var whatifEl = section.querySelector('.whatif-grade');
    currentEl.textContent = current === null ? '暂无成绩' : current.toFixed(1) + '%';
    whatifEl.textContent = whatif === null ? '暂无成绩' : whatif.toFixed(1) + '%';
  }}

  sections.forEach(function(section) {{
    var inputs = Array.prototype.slice.call(section.querySelectorAll('.score-input'));
    inputs.forEach(function(input) {{
      input.addEventListener('input', function() {{ refresh(section); }});
    }});
    var resetBtn = section.querySelector('.reset-btn');
    resetBtn.addEventListener('click', function() {{
      inputs.forEach(function(input) {{ input.value = input.getAttribute('data-real'); }});
      refresh(section);
    }});
    refresh(section);
  }});
}})();
</script>
</body>
</html>"""


def generate():
    content = build_html()
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✅ 成绩页已生成：{OUTPUT_PATH}")


if __name__ == "__main__":
    generate()
