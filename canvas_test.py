"""
Canvas API 连接测试脚本
用于验证 Access Token 是否有效，并测试基本的课程列表拉取。

使用前：
1. 安装依赖：
   pip install requests python-dotenv

2. 在这个脚本同目录下创建一个 .env 文件，内容如下：
   CANVAS_API_TOKEN=你的新token（不要用之前贴在聊天里的那个，先去撤销重新生成）
   CANVAS_BASE_URL=https://你学校的canvas域名

3. 运行：
   python canvas_test.py
"""

import os
import sys
import requests
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.getenv("CANVAS_API_TOKEN")
BASE_URL = os.getenv("CANVAS_BASE_URL")


def test_connection():
    if not TOKEN or not BASE_URL:
        print("❌ 缺少环境变量，请检查 .env 文件里是否设置了 CANVAS_API_TOKEN 和 CANVAS_BASE_URL")
        sys.exit(1)

    url = f"{BASE_URL.rstrip('/')}/api/v1/courses"
    headers = {"Authorization": f"Bearer {TOKEN}"}
    params = {"per_page": 50, "enrollment_state": "active"}

    try:
        response = requests.get(url, headers=headers, params=params, timeout=10)
    except requests.exceptions.RequestException as e:
        print(f"❌ 网络请求失败：{e}")
        sys.exit(1)

    if response.status_code == 200:
        courses = response.json()
        print(f"✅ 连接成功！拿到 {len(courses)} 门课程：\n")
        for c in courses:
            name = c.get("name", "未命名课程")
            course_id = c.get("id")
            print(f"  - [{course_id}] {name}")
    elif response.status_code == 401:
        print("❌ 认证失败（401），Token 可能无效、已过期，或没有正确设置。")
    elif response.status_code == 403:
        print("❌ 权限不足（403），检查一下 Token 的权限范围。")
    else:
        print(f"❌ 请求失败，状态码：{response.status_code}")
        print(response.text[:500])


if __name__ == "__main__":
    test_connection()
