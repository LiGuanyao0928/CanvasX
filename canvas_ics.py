"""
生成标准 iCalendar (.ics) 文件——给 Windows / Linux 用户导入到 Outlook / Google 日历 /
其他任意日历软件。Mac 版走的是 canvas_calendar.py 直接操作系统日历 App 的 AppleScript，
Windows/Linux 没有对应的系统日历 API，所以退而求其次生成一份通用的 .ics 文件，
双击（或用日历软件的"导入"功能）打开就能导进去。

用作业 id 编码进事件 UID 里（canvas-<id>@canvas-dashboard），Outlook/Apple日历/
Thunderbird 等大部分桌面日历软件重新导入时会按 UID 识别成"同一个事件"进行更新，
不会重复添加。但 Google 日历网页版的"导入"功能比较特殊——它不按 UID 去重，每次手动
导入都会当成全新事件，反复导入会重复。这是本地文件方案本身的限制（真正的"订阅并
自动更新"需要把文件挂在一个外网能访问的地址上，纯本地生成的文件做不到），不是这份
代码的 bug，只是提前告诉你别踩坑。

运行：python3 canvas_ics.py   # 生成/更新 canvas_assignments.ics
"""

from datetime import datetime, timedelta, timezone

from canvas_calendar import get_dated_assignments

ICS_PATH = "canvas_assignments.ics"


def _escape(text):
    return (text or "").replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", "\\n")


def build_ics(rows):
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//CanvasX//canvas_ics.py//CN",
        "CALSCALE:GREGORIAN",
        "X-WR-CALNAME:Canvas 作业",
    ]
    for aid, course_name, assignment_name, due_at, guessed, url in rows:
        try:
            start = datetime.fromisoformat(due_at.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            continue
        end = start + timedelta(minutes=30)
        prefix = "~" if guessed else ""
        title = f"{prefix}{course_name}：{assignment_name}"
        lines += [
            "BEGIN:VEVENT",
            f"UID:canvas-{aid}@canvas-dashboard",
            f"DTSTAMP:{now}",
            f"DTSTART:{start.strftime('%Y%m%dT%H%M%SZ')}",
            f"DTEND:{end.strftime('%Y%m%dT%H%M%SZ')}",
            f"SUMMARY:{_escape(title)}",
            f"DESCRIPTION:{_escape(url or '')}",
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"


def sync_to_calendar():
    rows = get_dated_assignments()
    ics_text = build_ics(rows)
    with open(ICS_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(ics_text)
    print(f"✅ 已生成 {ICS_PATH}（{len(rows)} 个作业）——用日历软件的「导入」功能打开这个文件即可")


if __name__ == "__main__":
    sync_to_calendar()
