# CanvasX · Windows 客户端

WPF（.NET 8）原生客户端，对齐 `native_app/`（Mac 版，Swift + AppKit）的功能范围。

四个板块（作业看板/课程资料/成绩/提醒时间）用 WebView2 显示 Python 后端生成/项目自带的
静态网页；设置向导、设置面板、提醒时间编辑器**不再是原生 UI**，改成跟 Mac 版共用同一份
HTML/CSS/JS（`setup_wizard.html` / `settings.html` / `schedule.html`，项目根目录下），
通过一层小小的"网页调原生代码"桥接（`NativeBridge`）调用读写配置文件、跑 Python 脚本、
开关窗口这些原生能力。原生 C# 代码现在只剩：窗口管理、托管 WebView2、通用桥接分发。
背景见根目录 `PARITY.md`。

这份客户端是在一台 Mac 上写的——**完全没有编译或运行过**，因为这台机器没有 .NET /
Windows 工具链。代码尽量写得规范、贴合 WPF/WebView2 的标准用法，但第一次在真机上
`dotnet build` 大概率会冒出一些小问题（缺 using、控件属性名拼错之类），这是正常的，
不代表设计方向有问题。文末"已知风险点"列出了最值得优先检查的地方。

## 前提条件

- **.NET 8 SDK**（不是只装运行时）——`dotnet --version` 应该显示 `8.x`。去
  https://dotnet.microsoft.com/download/dotnet/8.0 下载安装。
- **WebView2 Runtime**——Windows 10/11 上几乎所有电脑都已经通过 Edge 浏览器自带装好了，
  一般不用额外操心；如果启动时报 WebView2 初始化失败，去微软官网搜索
  "WebView2 Runtime" 单独装一个 Evergreen Runtime。
- **Python 3**（跟 Mac 版一样，装的时候记得勾选 "Add python.exe to PATH"），后端脚本
  （`canvas_sync.py`、`fetch_courses.py`、`write_config.py` 等）复用的是同一套 Python
  代码，不用重写。

## 构建 / 运行

最简单的方式：在项目根目录跑一次 `setup.bat`（建虚拟环境 + 装依赖 + 编译 + 打开），
跟 Mac 版的 `setup.sh` 是同一个思路。

也可以分步自己来：

```powershell
# 1. Python 后端环境（在项目根目录）
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt

# 2. 编译 Windows 客户端（自包含 + 单文件，这样同学电脑不用先装 .NET 运行时）
cd windows_app
powershell -ExecutionPolicy Bypass -File build.ps1

# 编译产物：
# windows_app\bin\Release\net8.0-windows\win-x64\publish\CanvasX.exe
```

也可以直接用 Visual Studio 2022（装 ".NET 桌面开发" workload）打开
`windows_app\CanvasDashboard.csproj` 编译调试，比命令行更容易看到具体报错行号。

## 项目结构

```
windows_app/
  CanvasDashboard.csproj       项目文件（net8.0-windows, WPF, WebView2 包引用）
  App.xaml / App.xaml.cs       入口 + 窗口流转中枢：找项目目录、应用主题、决定先显示
                                向导还是主窗口，以及 ShowSetupWizard/FinishSetupWizard/
                                ShowMainWindow/ReloadMainWindowCurrentSection/ShowSettings/
                                PerformLogoutTransition 这些被 NativeBridge 回调的静态方法
                                （对应 Mac 版 main.swift 里 AppDelegate 的同名方法）
  MainWindow.xaml(.cs)         主窗口：左侧边栏 + 一个 WebView2 内容区，四个板块（作业看板/
                                课程资料/成绩/提醒时间）完全对称，只是加载不同的网页
  Models/
    AppPrefs.cs                 Windows 客户端自己的本地偏好（主题/语言/记住我）
    CanvasCourse.cs              Canvas 课程 DTO（目前桥接层直接透传 JSON，未使用，
                                  保留供以后需要强类型时用）
  Services/
    ProjectPaths.cs              项目根目录解析（见下方"已知风险点"第一条）
    PythonRunner.cs              统一的"跑 python 脚本"封装：RunAsync（只看退出码，
                                  可选写日志文件）、RunSyncBlocking（给 App 退出钩子用的
                                  同步阻塞版）、RunJsonRawAsync（从 stdin 传一段 JSON、
                                  捕获 stdout/stderr——给 fetch_courses.py/write_config.py用）
    NativeBridge.cs              网页 <-> 原生代码桥接的核心：接 WebView2 的
                                  WebMessageReceived，按 action 分发（fetchCourses/
                                  completeSetup/getEnv/getPrefs/setPrefs/syncNow/logout/
                                  openLogs/openWizard/getSchedule/saveSchedule），处理完
                                  用 ExecuteScriptAsync 把结果送回 window.__bridgeResult
    EnvFile.cs                   读写 .env
    ScheduleStore.cs              读写 schedule.json（原样存取 JSON 数组，不再用强类型
                                  Alarm 模型）+ 调用 update_schedule_windows.py
    PrefsStore.cs                读写 .windows_app_prefs.json（本客户端自己的偏好）
    ThemeManager.cs               手动切换 Light/Dark 资源字典（原生窗口外观）+ 读系统
                                  主题 + 把同一个选择同步给所有 WebView2（网页内容外观，
                                  见下方"已知风险点"）
  Views/
    WebPageWindow.xaml(.cs)       通用"开一个窗口显示一个本地网页"外壳，设置向导
                                  (setup_wizard.html) 和设置面板 (settings.html) 都用它
  Themes/Light.xaml, Dark.xaml     两套同名 key 的画刷资源
  build.ps1                       发布脚本
```

以下这些原生实现已经被项目根目录下的共享网页（Mac/Windows 通用）取代，这次重构里删掉了：
`Views/SetupWizardWindow.xaml(.cs)`、`Views/SettingsWindow.xaml(.cs)`、
`Views/ScheduleView.xaml(.cs)`、`Views/AlarmEditorWindow.xaml(.cs)`、
`Services/CanvasApi.cs`（HTTP 调用现在在 `fetch_courses.py` 里）、
`Models/Alarm.cs`（提醒时间数据结构现在是网页 JS 和桥接层之间原样传递的 JSON，不需要
C# 强类型模型）、`Services/Loc.cs`（原生设置窗口专用的中英字符串表，settings.html 自己
带了一份等价的 JS 版本）。

## 已知风险点 / 请优先检查

按"最值得先测"的顺序排列：

1. **`NativeBridge.cs` 里的 stdin JSON 编码（`PythonRunner.RunJsonRawAsync`）**——这是这次
   重构里最容易踩坑、也最不容易被发现的一处：`fetch_courses.py`/`write_config.py` 用
   `json.load(sys.stdin)`（文本模式，不认 BOM）读输入，如果 C# 这边用带 BOM 的
   `Encoding.UTF8` 常量设置 `StandardInputEncoding`，第一次写入时 `StreamWriter` 会在最
   前面插入 EF BB BF 三个字节，导致**每一次** `fetchCourses`/`completeSetup` 调用都在
   Python 那边直接报 JSON 解析错误——现象会是"设置向导第一步永远连不上"，很容易被误判
   成网络问题或 Token 问题。代码里已经改用不带 BOM 的
   `new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)`，但这个坑没有实机验证过，
   第一次测设置向导时如果报"输入格式不对（应该是 JSON）"，先检查这里。

2. **WebView2 的 `WebMessageReceived` / `postMessage` 往返（`NativeBridge.cs`）**——
   `bridge.js` 用 `window.chrome.webview.postMessage(message)` 发一个 JS 对象（不是字符串），
   原生这边用 `e.WebMessageAsJson` 取 JSON 文本再解析。这条链路（网页发消息 → C# 收到 →
   跑 Python → `ExecuteScriptAsync` 把结果传回 `window.__bridgeResult`）之前完全没有跑过，
   建议第一次测试就打开设置向导，走完整 4 步，确认每一步都有响应（不会一直转圈或者
   点了没反应）。如果消息完全收不到，检查 WebView2 SDK 版本是否支持
   `WebMessageAsJson`（`CoreWebView2WebMessageReceivedEventArgs` 的这个属性）。

3. **`ExecuteScriptAsync` 回调时机跟页面导航之间的竞态**——`completeSetup`/`logout` 这两个
   action 会在"给网页发送结果"和"关掉当前这个窗口（连带它的 WebView2 一起销毁）"之间
   只隔了一行代码，没有互相等待。理论上存在"响应还没真正送达页面、窗口已经开始关闭"的
   竞态窗口——Mac 版其实有一模一样的竞态（`setup_wizard.html` 的注释里也承认了"正常情况下
   走不到检查返回值那一步"），两边都是有意接受这个设计取舍，不是遗漏，但如果测出来
   "设置向导点完成之后没反应、也没报错"，先怀疑这里。

4. **`ThemeManager.cs` 里 `CoreWebView2Profile.PreferredColorScheme`**——这是整个 Windows
   移植里**最没把握的一个 API**：为了让"设置面板选浅色/深色"这个操作也能让 WebView2
   渲染的网页内容（`prefers-color-scheme` 媒体查询）跟着变，而不是只影响原生窗口外观
   （对应 Mac 版"设置 `NSApp.appearance` 后 `WKWebView` 自动跟着变"的效果），代码里用了
   `CoreWebView2.Profile.PreferredColorScheme`（`CoreWebView2PreferredColorScheme` 枚举：
   `Auto`/`Light`/`Dark`）。这个属性在 WebView2 SDK 里存在的版本、以及具体生效的时机
   （是否需要重新导航页面才能反映新值，还是像真实系统主题切换一样实时生效）都没有实机
   验证过。代码里包了 try/catch，就算这个 API 不存在/调用失败也不会崩溃——退化结果是
   "浅色/深色"这两个强制选项只影响原生窗口外观，网页内容还是跟着 Windows 系统的实际
   深浅色模式走（`app_theme.css` 的 `prefers-color-scheme` 兜底），不是完全没用，但达不到
   跟 Mac 版一样的强制覆盖效果。第一次测试时建议：系统开着"浅色"，在设置面板里手动切到
   "深色"，看设置面板本身、以及切回作业看板之后的网页，是不是都真的变暗了。

5. **项目根目录解析（`Services/ProjectPaths.cs`）**——从 exe 所在目录往上找包含
   `canvas_sync.py` 的文件夹。如果你把编译好的 exe 单独拷到别的地方运行（不在
   `CanvasX` 项目目录树下），或者 `PublishSingleFile` 自解压后的临时目录结构跟设想的
   不一样，这里就会找不到，启动时会弹出中文错误框（不会静默崩溃）。**建议第一次测试时
   就从项目原始位置（`windows_app\bin\...\publish\` 或者直接拷到 `CanvasX` 项目根目录）
   运行 exe，排除这个变量。**

6. **WebView2 自定义 scheme 拦截（`MainWindow.xaml.cs` 的
   `CoreWebView2_NavigationStarting`）**——`canvasapp://add?...` / `canvasapp://delete?...`
   这两个假链接的拦截逻辑没有变（这次重构特意没碰它，见 `main.swift` 里对应的注释），
   但也还没有实机验证过，尤其要确认：materials.html 里生成的链接格式能被正确拦截，
   不会先被 WebView2 当成"无法识别的协议"报错弹窗挡住。

7. **`schtasks` 调用（Python 侧 `update_schedule_windows.py`，C# 侧只是原样调用它）**——
   这个 Python 脚本本身不是这次改的重点，但 C# 这边调用它、以及它内部拼 `schtasks`
   命令行参数（尤其是路径里如果有空格）的引号处理，都还没有在真实的 Windows
   任务计划程序里验证过实际生效。保存一条提醒时间之后，去"任务计划程序"里确认一下
   `CanvasSync_<id>` 任务确实创建成功、触发时间对得上。

8. **单文件发布（`PublishSingleFile`）+ WebView2 native loader**——理论上
   `IncludeNativeLibrariesForSelfExtract=true` 能让 WebView2 的 loader dll 一起被
   自解压出来正常工作，但这个组合没有在真机上跑过，如果启动直接报"找不到
   WebView2Loader.dll"之类的错，先尝试去掉 `PublishSingleFile`（改成普通多文件发布）
   排除是不是单文件打包的问题。

9. **`Microsoft.Web.WebView2` NuGet 包版本号**——`CanvasDashboard.csproj` 里锁定的是
   `1.0.2903.40`；`dotnet restore` 时如果提示"找不到这个版本"，直接在 Visual Studio 的
   NuGet 包管理器里升级到当前可用的最新版本即可，不涉及代码改动（升级版本对
   `PreferredColorScheme` 这类较新 API 只会更保险，不会更差）。

10. **深色模式下少数系统控件的默认外观**——`MessageBox`、原生文件选择框这些控件走的是
    Windows 系统默认样式，不受本项目 `Themes/Light.xaml` / `Dark.xaml` 的自定义画刷影响
    （这是 WPF 手动换肤方案的已知局限，不是 bug）。设置向导/设置面板/提醒时间这三块
    原来受此影响最大的界面现在都是网页、完全由 CSS 控制深浅色，这一条的影响范围比
    上一版小了很多，只剩系统级弹窗还有这个问题。

以上这些都是"大概率能跑，但值得优先盯一眼"的点，不代表功能没做——四个 Tab、
设置向导四步、设置面板的各个功能区块、提醒时间的增删改查，都已经按 Mac 版的桥接协议
实现了完整的业务逻辑，只是缺一次真机编译/运行的验证。
