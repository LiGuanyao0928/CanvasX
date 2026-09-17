"""
把 Canvas 的 submission_types 原始值翻译成人看得懂的作业类型标签，
用于仪表盘的"类型"筛选。
"""

TYPE_LABELS = {
    "online_upload": "文件上传",
    "online_text_entry": "文字提交",
    "online_url": "网址提交",
    "online_quiz": "测验",
    "quiz": "测验",  # 独立抓取的 Canvas Quiz（没有对应 Assignment 的那种）
    "discussion_topic": "讨论",
    "media_recording": "音视频提交",
    "on_paper": "纸质/教室内",
    "external_tool": "外部工具/测验",
    "not_graded": "不计分",
    "none": "无需提交",
}


def label_for(submission_type):
    return TYPE_LABELS.get(submission_type, submission_type or "其他")
