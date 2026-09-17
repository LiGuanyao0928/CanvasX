"""
从作业标题/说明文字，或者课程 Syllabus 正文里猜截止日期。
用于 Canvas 没有设置正式 due_at 字段、但日期其实写在别的地方的情况：
- 标题/说明手打日期（例如 "Due Sept 20th at 10:30 PM"）
- Syllabus 里的课程安排表（例如 Midterm 1/2 的考试日期通常只写在这里）

猜不出来就返回 None，调用方应该把它当成"未知"处理，不是错误。
"""

import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from dateutil import parser as dateutil_parser

# 学校所在时区（Ontario Tech University, Oshawa, ON）。
# 文字里的日期没写时区，按本地时间理解。
SCHOOL_TZ = ZoneInfo("America/Toronto")

TAG_RE = re.compile(r"<[^<]+?>")
DUE_RE = re.compile(r"due\s*:?\s*(on)?\s*(.{3,40})", re.IGNORECASE)

# 匹配 "Oct. 28/29, 2026"、"Nov 25th 2026" 这类写法，日期范围只取第一天。
MONTH_DATE_RE = re.compile(
    r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-zA-Z]*\.?\s+"
    r"(\d{1,2})(?:/\d{1,2})?(?:st|nd|rd|th)?,?\s*(\d{4})",
    re.IGNORECASE,
)


def strip_html(html):
    return TAG_RE.sub(" ", html or "")


def _to_due_at(parsed):
    """把 naive datetime（按学校本地时区理解）转成 UTC ISO8601 字符串，并做合理性检查。"""
    now = datetime.now()
    if not (now - timedelta(days=60) <= parsed <= now + timedelta(days=400)):
        return None  # 防止误匹配出离谱的日期（比如解析到几十年前/后）
    local_dt = parsed.replace(tzinfo=SCHOOL_TZ)
    return local_dt.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ")


def guess_due_at(name, description_html):
    """从作业标题/说明文字里猜。返回 UTC ISO8601 字符串，或 None。"""
    text = f"{name or ''}  {strip_html(description_html)}"

    m = DUE_RE.search(text)
    if not m:
        return None

    try:
        parsed = dateutil_parser.parse(m.group(2), fuzzy=True)
    except (ValueError, OverflowError):
        return None

    return _to_due_at(parsed)


def guess_due_at_from_syllabus(assignment_name, syllabus_html, window=150):
    """
    在课程 Syllabus 正文里找作业名字附近出现的日期
    （比如 "Midterm 1: 25% (Oct. 28/29, 2026)"）。
    时间猜不出来，统一按当天 23:59 处理。返回 UTC ISO8601 字符串，或 None。
    """
    if not assignment_name or not syllabus_html:
        return None

    text = re.sub(r"\s+", " ", strip_html(syllabus_html))
    name = assignment_name.strip()
    if not name:
        return None

    for m in re.finditer(re.escape(name), text, re.IGNORECASE):
        start = max(0, m.start() - window)
        end = min(len(text), m.end() + window)
        chunk = text[start:end]
        anchor_pos = m.start() - start

        # 窗口内可能不止一个日期（比如相邻的 Midterm 1/Midterm 2 各自带日期），
        # 取离作业名字最近的那个，而不是窗口里第一个。
        dm = min(
            MONTH_DATE_RE.finditer(chunk),
            key=lambda x: abs(x.start() - anchor_pos),
            default=None,
        )
        if not dm:
            continue
        month, day, year = dm.group(1), dm.group(2), dm.group(3)
        try:
            parsed = dateutil_parser.parse(f"{month} {day}, {year} 23:59", fuzzy=True)
        except (ValueError, OverflowError):
            continue
        due_at = _to_due_at(parsed)
        if due_at:
            return due_at
    return None
