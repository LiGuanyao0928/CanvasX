"""
拉当前 Canvas 账号的课程列表，给设置向导用（验证网址/Token 是否有效 + 列出课程
供勾选）。这段 HTTP 请求逻辑之前在 Mac 版（CanvasAPI.swift）和 Windows 版
（CanvasApi.cs）里各写了一份——现在统一走这一份 Python 代码，原生桥接层只管
调用 + 转发结果，不用在两边分别实现同一个 API 调用。

Token 从 stdin 传（不用命令行参数）——命令行参数会被同一台电脑上其他进程用
`ps aux` 之类的命令看到，stdin 不会，这台电脑万一是公用电脑时更安全一点。

用法：echo '{"baseUrl": "...", "token": "..."}' | python3 fetch_courses.py
成功：课程列表以 JSON 数组打印到 stdout，退出码 0
失败：错误信息打印到 stderr，退出码非 0
"""

import json
import sys

import requests


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        print("输入格式不对（应该是 JSON）", file=sys.stderr)
        sys.exit(1)

    base_url = (data.get("baseUrl") or "").rstrip("/")
    token = data.get("token") or ""
    if not base_url or not token:
        print("缺少 baseUrl 或 token", file=sys.stderr)
        sys.exit(1)

    try:
        resp = requests.get(
            f"{base_url}/api/v1/courses",
            headers={"Authorization": f"Bearer {token}"},
            params={"per_page": 50, "enrollment_state": "active"},
            timeout=15,
        )
    except requests.exceptions.ConnectionError:
        print("连不上服务器，检查一下网址拼得对不对、网络是否正常", file=sys.stderr)
        sys.exit(1)
    except requests.exceptions.Timeout:
        print("连接超时，检查一下网络", file=sys.stderr)
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"请求出错：{e}", file=sys.stderr)
        sys.exit(1)

    if resp.status_code == 401:
        print("Token 无效或已过期", file=sys.stderr)
        sys.exit(1)
    if not resp.ok:
        print(f"请求失败（状态码 {resp.status_code}）", file=sys.stderr)
        sys.exit(1)

    try:
        courses = resp.json()
    except ValueError:
        print("服务器返回的内容解析不了，确认一下网址是不是 Canvas 的地址", file=sys.stderr)
        sys.exit(1)

    simplified = [
        {
            "id": c.get("id"),
            "name": c.get("name") or "未命名课程",
            "course_code": c.get("course_code") or "",
        }
        for c in courses
        if isinstance(c, dict) and c.get("id") is not None
    ]
    print(json.dumps(simplified, ensure_ascii=False))


if __name__ == "__main__":
    main()
