"""
Canvas 作业推送脚本
把未来N天内的作业列表推送到手机——支持几种不同的推送方式，在 .env 里用
NOTIFY_METHOD 选择：

- ntfy（推荐，最简单，跨平台）：手机装 ntfy App，订阅 NTFY_TOPIC 这个频道名
- wechat（微信，通过 Server酱 中转，第三方免费服务）：
  https://sct.ftqq.com 用微信扫码登录拿 SendKey，填到 WECHAT_SENDKEY
- shortcuts（苹果快捷指令，纯苹果生态，不依赖第三方）：
  Mac 上"快捷指令"App 建一个接收文本输入、用"发送信息"发给自己的快捷指令，
  把它的名字填到 SHORTCUTS_NAME
- none：不推送，只看网页仪表盘

没有 NOTIFY_METHOD 但有 NTFY_TOPIC（老版本的 .env）时，自动当作 ntfy 处理，
不用手动改配置。

运行：python3 canvas_notify.py
      python3 canvas_notify.py 3   # 查未来3天
"""

import os
import subprocess
import sys
import tempfile

import requests
from dotenv import load_dotenv

from canvas_upcoming import get_upcoming, get_unspecified

load_dotenv()

NOTIFY_METHOD = (os.getenv("NOTIFY_METHOD") or "").strip().lower()
if not NOTIFY_METHOD:
    # 兼容老版本 .env（只写了 NTFY_TOPIC，没有 NOTIFY_METHOD 这一项）
    NOTIFY_METHOD = "ntfy" if os.getenv("NTFY_TOPIC") else "none"

NTFY_TOPIC = os.getenv("NTFY_TOPIC")
WECHAT_SENDKEY = os.getenv("WECHAT_SENDKEY")
SHORTCUTS_NAME = os.getenv("SHORTCUTS_NAME")


def build_message(days):
    upcoming = get_upcoming(days)
    unspecified = get_unspecified()

    if not upcoming:
        title = f"Canvas: no dated assignments in {days} days"
        body_parts = [f"未来 {days} 天内没有要交的作业 🎉"]
    else:
        title = f"Canvas: {len(upcoming)} assignments in {days} days"
        blocks = []
        for due, course_name, assignment_name, url, guessed, description, files, submission_type in upcoming:
            local_due = due.astimezone()
            tag = "~" if guessed else ""
            blocks.append(f"[{tag}{local_due.strftime('%m-%d %H:%M')}] {course_name}\n{assignment_name}")
        body_parts = ["\n\n".join(blocks)]

    if unspecified:
        lines = [
            f"[not specified] {course_name}\n{assignment_name}"
            for course_name, assignment_name, url, description, files, submission_type in unspecified
        ]
        body_parts.append("\n\n".join(lines))

    body = "\n\n---\n\n".join(body_parts)
    return title, body


def send_ntfy(title, body):
    if not NTFY_TOPIC:
        print("❌ 缺少 .env 里的 NTFY_TOPIC")
        return
    resp = requests.post(
        f"https://ntfy.sh/{NTFY_TOPIC}",
        data=body.encode("utf-8"),
        headers={"Title": title, "Priority": "default"},
        timeout=10,
    )
    if resp.status_code == 200:
        print(f"✅ 已通过 ntfy 推送到手机：{title}")
    else:
        print(f"❌ ntfy 推送失败，状态码：{resp.status_code}")
        print(resp.text[:300])


def send_wechat(title, body):
    if not WECHAT_SENDKEY:
        print("❌ 缺少 .env 里的 WECHAT_SENDKEY")
        return
    resp = requests.post(
        f"https://sctapi.ftqq.com/{WECHAT_SENDKEY}.send",
        data={"title": title, "desp": body},
        timeout=10,
    )
    try:
        ok = resp.json().get("code") == 0
    except ValueError:
        ok = False
    if ok:
        print(f"✅ 已通过微信推送：{title}")
    else:
        print(f"❌ 微信推送失败：{resp.text[:300]}")


def send_shortcuts(title, body):
    if not SHORTCUTS_NAME:
        print("❌ 缺少 .env 里的 SHORTCUTS_NAME")
        return
    text = f"{title}\n\n{body}"
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(text)
        temp_path = f.name
    try:
        result = subprocess.run(
            ["shortcuts", "run", SHORTCUTS_NAME, "--input-path", temp_path],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            print(f"✅ 已通过快捷指令《{SHORTCUTS_NAME}》推送")
        else:
            print(f"❌ 快捷指令运行失败：{result.stderr.strip()}")
    finally:
        try:
            os.remove(temp_path)
        except OSError:
            pass


def notify(days):
    if NOTIFY_METHOD == "none":
        print("ℹ️ 未开启手机推送（NOTIFY_METHOD=none），跳过")
        return

    title, body = build_message(days)

    if NOTIFY_METHOD == "ntfy":
        send_ntfy(title, body)
    elif NOTIFY_METHOD == "wechat":
        send_wechat(title, body)
    elif NOTIFY_METHOD == "shortcuts":
        send_shortcuts(title, body)
    else:
        print(f"❌ 不认识的 NOTIFY_METHOD：{NOTIFY_METHOD}")


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    notify(days)


if __name__ == "__main__":
    main()
