"""
把设置向导收集到的账号信息/选课/推送方式写成 .env 和 tracked_courses.json。
Mac/Windows 两边原生桥接层都调用这一份脚本，不用在 Swift/C# 里各自处理一遍
.env 的格式拼接（以前两边分别写，字段名/格式稍有出入就容易踩坑）。

从 stdin 传一份 JSON（不用命令行参数——Token 出现在参数里会被 `ps aux`
之类的命令看到，公用电脑上不安全）。

用法：echo '{"token":"...","baseUrl":"...","notifyMethod":"none","courseIds":[1,2]}' \
        | python3 write_config.py
"""

import json
import os
import sys

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        print("输入格式不对（应该是 JSON）", file=sys.stderr)
        sys.exit(1)

    method = data.get("notifyMethod") or "none"
    env_lines = [
        f"CANVAS_API_TOKEN={data.get('token', '')}",
        f"CANVAS_BASE_URL={data.get('baseUrl', '')}",
        f"NOTIFY_METHOD={method}",
    ]
    if method == "ntfy":
        env_lines.append(f"NTFY_TOPIC={data.get('ntfyTopic', '')}")
    elif method == "discord":
        env_lines.append(f"DISCORD_WEBHOOK_URL={data.get('discordWebhook', '')}")
    elif method == "shortcuts":
        env_lines.append(f"SHORTCUTS_NAME={data.get('shortcutsName', '')}")

    with open(os.path.join(PROJECT_DIR, ".env"), "w", encoding="utf-8") as f:
        f.write("\n".join(env_lines) + "\n")

    course_ids = sorted(int(i) for i in (data.get("courseIds") or []))
    ids_text = ", ".join(str(i) for i in course_ids)
    with open(os.path.join(PROJECT_DIR, "tracked_courses.json"), "w", encoding="utf-8") as f:
        f.write('{"course_ids": [' + ids_text + ']}\n')

    print("ok")


if __name__ == "__main__":
    main()
