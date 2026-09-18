# Canvas 作业追踪 · Windows 客户端

WPF（.NET 8）原生客户端，对齐 `native_app/`（Mac 版，Swift + AppKit）的功能范围：
作业看板 / 课程资料 / 成绩（WebView2 显示 Python 后端生成的静态网页）、提醒时间
（原生列表 + 编辑器，改动后驱动 Windows 任务计划程序）、设置向导、以及 Mac 版目前还
没有的"设置"窗口（外观/语言/账号/立即同步/日志/关于）。

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
  （`canvas_sync.py` 等）复用的是同一套 Python 代码，不用重写。

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
# windows_app\bin\Release\net8.0-windows\win-x64\publish\CanvasDashboardWin.exe
```

也可以直接用 Visual Studio 2022（装 ".NET 桌面开发" workload）打开
`windows_app\CanvasDashboard.csproj` 编译调试，比命令行更容易看到具体报错行号。

## 项目结构

```
windows_app/
  CanvasDashboard.csproj       项目文件（net8.0-windows, WPF, WebView2 包引用）
  App.xaml / App.xaml.cs       入口：找项目目录、应用主题、决定先显示向导还是主窗口
  MainWindow.xaml(.cs)         主窗口：左侧边栏 + WebView2/提醒时间 内容区
  Models/                      Alarm、CanvasCourse、AppPrefs 数据模型
  Services/
    ProjectPaths.cs            项目根目录解析（见下方"已知风险点"第一条）
    PythonRunner.cs            统一的"跑 python 脚本"封装
    CanvasApi.cs                拉课程列表（设置向导用）
    EnvFile.cs                  读写 .env
    ScheduleStore.cs             读写 schedule.json + 调用 update_schedule_windows.py
    PrefsStore.cs                读写 .windows_app_prefs.json（本客户端自己的偏好）
    ThemeManager.cs               手动切换 Light/Dark 资源字典 + 读系统主题
    Loc.cs                        设置窗口专用的极简中英字符串表
  Views/
    ScheduleView.xaml(.cs)        "提醒时间" 页（UserControl）
    AlarmEditorWindow.xaml(.cs)   添加/编辑一条提醒时间
    SetupWizardWindow.xaml(.cs)   首次使用设置向导（4 步）
    SettingsWindow.xaml(.cs)      设置窗口
  Themes/Light.xaml, Dark.xaml     两套同名 key 的画刷资源
  build.ps1                       发布脚本
```

## 已知风险点 / 请优先检查

按"最值得先测"的顺序排列：

1. **项目根目录解析（`Services/ProjectPaths.cs`）**——从 exe 所在目录往上找包含
   `canvas_sync.py` 的文件夹。这是最关键的一处"胶水代码"：如果你把编译好的 exe
   单独拷到别的地方运行（不在 `canvas-project` 目录树下），或者
   `PublishSingleFile` 自解压后的临时目录结构跟设想的不一样，这里就会找不到，
   启动时会弹出中文错误框（不会静默崩溃），但具体报错信息值得看一眼来判断要不要
   调整判定逻辑。**建议第一次测试时就从项目原始位置（`windows_app\bin\...\publish\`
   或者直接拷到 `canvas-project` 根目录）运行 exe，排除这个变量。**

2. **WebView2 自定义 scheme 拦截（`MainWindow.xaml.cs` 的
   `CoreWebView2_NavigationStarting`）**——`canvasapp://add?...` / `canvasapp://delete?...`
   这两个假链接的拦截逻辑，用的是手动字符串切分解析 query（因为 `System.Uri` 对
   自定义 scheme 解析不可靠）。这部分逻辑没有实机验证过，尤其要确认：materials.html
   里生成的链接格式（`canvasapp://add?course_id=42466`）能被正确拦截并且不会先被
   WebView2 当成"无法识别的协议"报错弹窗挡住。

3. **`schtasks` 调用（Python 侧 `update_schedule_windows.py`，C# 侧只是原样调用它）**——
   这个 Python 脚本本身不是这次改的重点，但 C# 这边调用它、以及它内部拼 `schtasks`
   命令行参数（尤其是路径里如果有空格）的引号处理，都还没有在真实的 Windows
   任务计划程序里验证过实际生效。保存一条提醒时间之后，去"任务计划程序"里确认一下
   `CanvasSync_<id>` 任务确实创建成功、触发时间对得上。

4. **PasswordBox 取值 / TextBox 默认样式**——设置向导第 1 步用的是 `PasswordBox`
   （WPF 里密码框不能像 TextBox 一样用绑定/在 XAML 里预填值，所以是纯代码读取
   `.Password` 属性），逻辑上没问题，但强烈建议实际测一下粘贴长 Token 进去、以及
   窗口在真实分辨率/DPI 缩放下的排版是否跑偏（`SetupWizardWindow.xaml` 用的是固定
   宽度的卡片布局，没有做高 DPI/超宽屏的专门适配）。

5. **单文件发布（`PublishSingleFile`）+ WebView2 native loader**——理论上
   `IncludeNativeLibrariesForSelfExtract=true` 能让 WebView2 的 loader dll 一起被
   自解压出来正常工作，但这个组合没有在真机上跑过，如果启动直接报"找不到
   WebView2Loader.dll"之类的错，先尝试去掉 `PublishSingleFile`（改成普通多文件发布）
   排除是不是单文件打包的问题。

6. **`Microsoft.Web.WebView2` NuGet 包版本号**——`CanvasDashboard.csproj` 里锁定的是
   `1.0.2903.40`，这是编写时已知存在过的版本号，但 `dotnet restore` 时如果提示
   "找不到这个版本"，直接在 Visual Studio 的 NuGet 包管理器里升级到当前可用的最新
   版本即可，不涉及代码改动。

7. **深色模式下少数系统控件的默认外观**——`Expander`、`MessageBox`、原生文件选择框
   这些控件走的是 Windows 系统默认样式，不受本项目 `Themes/Light.xaml` /
   `Dark.xaml` 的自定义画刷影响（这是 WPF 手动换肤方案的已知局限，不是 bug）。
   如果想要它们也跟着变暗，需要额外给这些控件类型写自定义 ControlTemplate，
   目前没有做，可以后续按需补。

以上这些都是"大概率能跑，但值得优先盯一眼"的点，不代表功能没做——四个 Tab、
提醒时间的增删改查、设置向导四步、设置窗口的六个功能区块都已经按需求实现了完整的
业务逻辑，只是缺一次真机编译/运行的验证。
