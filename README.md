# Canvas 作业追踪

一个个人用的 Canvas LMS 作业追踪 App：自动同步作业/测验/成绩/课程资料，猜出
Canvas 没写清楚的截止日期，推送手机提醒，还能同步进日历。Mac/Windows 都有
原生客户端（Mac 是 Swift + AppKit，Windows 是 C# + WPF），Linux 目前是网页版，
后台数据同步统一用 Python 脚本，三个平台共用同一份。

## 功能

- **作业看板**：按紧急程度分类显示所有作业，支持搜索/筛选，作业要求和附件
  直接展开在卡片里，不用再点进 Canvas 网页
- **课程资料**：把 Canvas Modules 里的讲义/PPT 自动下载到本地，网盘式的
  文件夹浏览 + 全文搜索，也能自己添加/删除本地文件
- **成绩**：按各课程的分组权重算当前成绩，还能试算"如果这门作业考了多少
  分，总成绩会变成多少"
- **提醒时间**：像苹果闹钟一样设置多个自动同步时间点，每条单独开关、可
  设置只在某几天重复
- **手机推送**：ntfy / Discord / 苹果快捷指令（Windows 上是 ntfy / Discord），
  可以不用
- **日历同步**：Mac 自动同步进系统"日历"App；Windows/Linux 生成一份标准
  `.ics` 文件，导入到 Outlook / Google 日历都行
- **设置面板**：外观（浅色/深色/跟随系统）、语言（目前仅设置面板文字支持中英
  切换，作业看板等网页内容还是中文）、退出登录、立即同步、打开日志文件夹
- 三层日期解析：Canvas 正式设置的 → 作业说明文字里猜的 → 课程 Syllabus 里
  猜的（比如期中考试日期经常只写在 Syllabus 里）

## 安装 — macOS

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

## 安装 — Windows

**前提**：[.NET 8 SDK](https://dotnet.microsoft.com/download)、Python 3
（装的时候记得勾选"Add to PATH"）。WebView2 运行时基本都已经预装（跟着
Edge 浏览器装的），一般不用额外装。

```bat
git clone <这个仓库的地址>
cd canvas-project
setup.bat
```

第一次打开也是同样的设置向导：填 Canvas 网址/Token → 选课程 → 选推送方式。
详细的技术说明和已知待验证的问题见 [`windows_app/README.md`](windows_app/README.md)——
这部分是全新重写的，还没有在真机上跑过完整测试，第一次用遇到问题很正常，
反馈给我就行。

## 安装 — Linux

Linux 上还没有独立窗口的原生客户端（这边没有能实际测试图形界面的 Linux
环境），先提供一个能跑起来的替代方案：Python 后端照常同步（作业/成绩/资料/
推送/日历导出功能都在），网页仪表盘用浏览器打开，定时靠 cron。

```bash
git clone <这个仓库的地址>
cd canvas-project
./setup_linux.sh
```

跟着终端里的提示填账号信息、选课程即可。以后想要每天自动同步，运行一次
`.venv/bin/python3 update_schedule_linux.py`。

Mac/Windows 上第一次打开 App 会看到一个图形化设置向导，跟着填：你自己的
Canvas 网址和 Access Token（**不要把 Token 分享给别人**）→ 勾选真正要交
作业的课程 → 要不要手机推送提醒。设置完就会自动跑第一次同步，以后每天会
按"提醒时间"里设置的时间点自动同步。

## 手机推送的几种方式

- **ntfy**（推荐）：跨平台，手机 App Store 装"ntfy"，订阅向导里生成的频
  道名即可
- **Discord**：Discord 频道设置 →「整合」→「Webhook」→「新增 Webhook」，
  把生成的网址填进去，不用邀请机器人
- **苹果快捷指令**（仅 Mac）：纯苹果生态不依赖第三方，Mac"快捷指令"App
  里建一个接收文字、"发送信息"给自己的快捷指令

想换推送方式或重新选课：Mac 版在菜单栏「设置…」或「查看 → 重新运行设置
向导」；Windows 版在设置窗口里点"重新选课 / 更换 Token"；Linux 版直接手
动改 `.env` 和 `tracked_courses.json`（改完跑一次 `canvas_sync.py --refresh`
生效，课程 id 可以用 `list_courses.py` 查）。

## 项目结构

```
canvas_sync.py              主同步脚本，串联下面所有模块
canvas_grades.py            成绩计算
canvas_materials.py         课程资料同步
canvas_calendar.py          日历同步（macOS，写进系统日历）
canvas_ics.py               日历同步（Windows/Linux，生成 .ics 文件）
canvas_notify.py            手机推送（ntfy/Discord/快捷指令）
canvas_dashboard.py         作业看板网页生成
due_date_parser.py          从文字/Syllabus猜日期
update_schedule.py          定时任务：macOS launchd
update_schedule_windows.py  定时任务：Windows 任务计划程序
update_schedule_linux.py    定时任务：Linux crontab
list_courses.py             查本地已同步的课程 id（Linux 手动配置用）
native_app/                 macOS 原生 App 源码（Swift + AppKit）
windows_app/                Windows 原生 App 源码（C# + WPF）
tracked_courses.json        你选的要追踪的课程（设置向导生成，不提交到仓库）
.env                        你的账号信息（设置向导生成，不提交到仓库）
```

## 常见问题

**重新编译后系统权限又要重新弹一遍？（Mac）** ad-hoc 签名的 App 每次重新
编译身份都会变，TCC 就当作新 App 处理。想避免的话自己建一个本地签名证书：
钥匙串访问 → 证书助理 → 创建证书 → 身份类型选"自签名根证书"，证书类型选
"代码签名"，名字改成 `native_app/build.sh` 里 `SIGNING_IDENTITY` 那一行
写的名字（默认是 `CanvasDashboard Local Dev`）。

**这个证书能直接给同学用吗，这样大家都不用重新弹权限了？** 不行。证书的
私钥是生成在你自己电脑的钥匙串里的，没法拷给别人、也没法通过 git 仓库或
压缩包分享——每个人只能自己建一个自己的证书。不过这其实不是问题：同学们
一般只编译一次（跑一遍 `setup.sh` 装好就不会再重新编译了），根本不会遇到
"重新编译"这个场景，`build.sh` 找不到你的证书时会自动改用 ad-hoc 签名，
一次性使用完全没问题。只有你自己因为改代码要频繁重新编译调试时，才值得
建这个证书省去反复的权限确认。

**证书签名时老是弹窗要输钥匙串密码？** 去"钥匙串访问"里找到这个证书对应
的私钥（双击证书展开能看到"私钥"那一项），双击私钥 → "存取控制" 标签页 →
选"允许所有应用程序访问这个项目"。这样以后用这个证书签名就不会再弹密码
确认了。（这一步涉及钥匙串访问权限设置，需要你自己手动操作，我没法替你
在系统层面改这个设置。）

**Canvas 网页里找不到"新建访问令牌"的选项，生成不了 Token 怎么办？** 这
通常是学校 Canvas 管理员关掉了学生自主生成 Token 的权限，不是操作问题。
唯一的办法是找任课老师或学校 IT/教务，请他们在 Canvas 管理后台给你开启
"用户自主生成访问令牌"的权限——Canvas 官方的应用授权（OAuth）流程需要学
校管理员审批注册，普通学生个人没法自己申请，目前没有绕开 Token 的替代
方案。

**想追踪的课程变了（比如开学换课）？** 见上面"想换推送方式或重新选课"。

**Token 会不会被别人看到？** 不会，`.env` 和 `tracked_courses.json` 都在
`.gitignore` 里，不会被提交到仓库；这两个文件只存在你自己电脑上。设置面
板里的"退出登录"会把这些文件从本机删掉，方便下一个用同一台电脑的同学。
