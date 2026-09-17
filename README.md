# Canvas 作业追踪

一个个人用的 Canvas LMS 作业追踪 App：自动同步作业/测验/成绩/课程资料，猜出
Canvas 没写清楚的截止日期，推送手机提醒，还能同步进 Mac 日历。原生 macOS
App（Swift + AppKit），后台数据同步用 Python 脚本。

## 功能

- **作业看板**：按紧急程度分类显示所有作业，支持搜索/筛选，作业要求和附件
  直接展开在卡片里，不用再点进 Canvas 网页
- **课程资料**：把 Canvas Modules 里的讲义/PPT 自动下载到本地，网盘式的
  文件夹浏览 + 全文搜索，也能自己添加/删除本地文件
- **成绩**：按各课程的分组权重算当前成绩，还能试算"如果这门作业考了多少
  分，总成绩会变成多少"
- **提醒时间**：像苹果闹钟一样设置多个自动同步时间点，每条单独开关、可
  设置只在某几天重复
- **手机推送**：ntfy / 微信（Server酱）/ 苹果快捷指令，三选一，也可以不用
- **日历同步**：自动把有截止日期的作业同步进 Mac"日历"App
- 三层日期解析：Canvas 正式设置的 → 作业说明文字里猜的 → 课程 Syllabus 里
  猜的（比如期中考试日期经常只写在 Syllabus 里）

## 安装

**前提**：电脑上要有 Xcode 命令行工具（终端跑 `xcode-select --install`）
和 Python 3。

```bash
git clone <这个仓库的地址>
cd canvas-project
./setup.sh
```

`setup.sh` 会自动建 Python 虚拟环境、装依赖、编译原生 App、打开它。

**如果系统提示"无法打开，因为无法验证开发者"**：去"系统设置 → 隐私与安全
性"，找到提示信息，点"仍要打开"。这是因为 App 没有用 Apple 开发者证书签
名（那个证书一年要交钱），不影响正常使用。

第一次打开 App 会看到一个设置向导，跟着填：

1. 你自己的 Canvas 网址和 Access Token（Canvas 网页「账户 → 设置 → 新建
   访问令牌」生成，**不要把 Token 分享给别人**）
2. 勾选真正要交作业的课程（自动帮你拉出你的完整课程列表）
3. 要不要手机推送提醒，选一种方式

设置完就会自动跑第一次同步。以后每天会按你在"提醒时间"里设置的时间点自
动同步。

## 手机推送的三种方式

- **ntfy**（推荐）：跨平台，手机 App Store 装"ntfy"，订阅向导里生成的频
  道名即可
- **微信**：通过 [Server酱](https://sct.ftqq.com)（一个第三方免费服务）
  转发到你自己的微信，扫码登录拿 SendKey
- **苹果快捷指令**：纯苹果生态不依赖第三方，Mac"快捷指令"App 里建一个接
  收文字、"发送信息"给自己的快捷指令

想换推送方式或者重新选课，App 菜单栏「查看 → 重新运行设置向导」。

## 项目结构

```
canvas_sync.py          主同步脚本，串联下面所有模块
canvas_grades.py        成绩计算
canvas_materials.py     课程资料同步
canvas_calendar.py      日历同步
canvas_notify.py        手机推送（ntfy/微信/快捷指令）
canvas_dashboard.py     作业看板网页生成
due_date_parser.py      从文字/Syllabus猜日期
native_app/             原生 Swift App 源码
tracked_courses.json    你选的要追踪的课程（设置向导生成，不提交到仓库）
.env                    你的账号信息（设置向导生成，不提交到仓库）
```

## 常见问题

**重新编译后系统权限又要重新弹一遍？** ad-hoc 签名的 App 每次重新编译身
份都会变，TCC 就当作新 App 处理。想避免的话自己建一个本地签名证书：钥匙
串访问 → 证书助理 → 创建证书 → 身份类型选"自签名根证书"，证书类型选"代
码签名"，名字改成 `native_app/build.sh` 里 `SIGNING_IDENTITY` 那一行写的
名字（默认是 `CanvasDashboard Local Dev`）。

**想追踪的课程变了（比如开学换课）？** 菜单栏「查看 → 重新运行设置向导」
重新选一遍。

**Token 会不会被别人看到？** 不会，`.env` 和 `tracked_courses.json` 都在
`.gitignore` 里，不会被提交到仓库；这两个文件只存在你自己电脑上。
