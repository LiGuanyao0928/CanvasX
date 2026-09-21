using System.Windows;
using System.Windows.Threading;
using CanvasDashboard.Services;
using CanvasDashboard.Views;

namespace CanvasDashboard;

/// <summary>
/// 应用入口 + 窗口流转的中枢，对应 Mac 版 main.swift 里的 AppDelegate。
///
/// 设置向导/设置面板现在都是共享网页（WebPageWindow 里加载 setup_wizard.html /
/// settings.html），"填完表单之后该切到哪个窗口"这类流转逻辑不再由窗口自己的事件
/// 触发（旧版用的是 SetupWizardWindow.Completed 事件），而是 NativeBridge 处理完
/// 具体 action 之后直接调用这里的静态方法——跟 Mac 版 Bridge.swift 直接调用全局
/// `delegate.finishSetupWizard()` / `delegate.performLogoutTransition()` 是同一个思路。
/// </summary>
public partial class App : Application
{
    private static WebPageWindow? _wizardWindow;
    private static WebPageWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 兜底：任何没被 catch 到的异常，弹一个中文错误框而不是让程序静默崩溃/闪退。
        DispatcherUnhandledException += OnDispatcherUnhandledException;

        try
        {
            _ = ProjectPaths.ProjectRoot; // 触发一次解析，找不到会抛异常
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "找不到项目目录（应该能在这个 exe 所在位置往上找到包含 canvas_sync.py 的文件夹）。\n\n" +
                $"详细信息：{ex.Message}\n\n" +
                "请确认这个程序是从 canvas-project 项目文件夹内部（比如 windows_app\\bin\\... 或你自己放的任意子目录）运行的，" +
                "而不是被单独拷贝到了别的地方。",
                "CanvasX - 启动失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(-1);
            return;
        }

        var prefs = PrefsStore.Load();
        ThemeManager.Apply(prefs.Theme);

        if (EnvFile.HasValidConfig())
        {
            ShowMainWindow();
        }
        else
        {
            ShowSetupWizard();
        }
    }

    // MARK: - 窗口流转（对应 main.swift 里 AppDelegate 的同名方法）

    /// <summary>首次使用、以及"退出登录"/在设置里"重新选课"时，展示设置向导网页窗口。</summary>
    public static void ShowSetupWizard()
    {
        _wizardWindow = new WebPageWindow("setup_wizard.html", "欢迎使用 CanvasX", 480, 780);
        _wizardWindow.Show();
        _wizardWindow.Activate();
    }

    /// <summary>设置向导网页调用 completeSetup 桥接、Python 写完配置+首次同步跑完之后，
    /// NativeBridge 回调这里，关掉向导、展示主窗口。</summary>
    public static void FinishSetupWizard()
    {
        _wizardWindow?.Close();
        _wizardWindow = null;
        ShowMainWindow();
    }

    public static void ShowMainWindow()
    {
        // 从设置向导第二次回来时（比如用户在设置面板点了"重新选课/更换 Token"）复用已有
        // 主窗口，只刷新数据，不要重新建一整套 WebView2/侧边栏——跟 Mac 版 showMainWindow()
        // 开头那个提前 return 分支一样。
        if (Current.MainWindow is MainWindow existing)
        {
            existing.Show();
            existing.Activate();
            _ = existing.RefreshDataAsync();
            return;
        }

        var main = new MainWindow();
        Current.MainWindow = main;
        main.Show();
    }

    /// <summary>设置面板"立即同步"跑完之后，NativeBridge 回调这里，把主窗口当前那一页重新加载一遍。</summary>
    public static void ReloadMainWindowCurrentSection()
    {
        (Current.MainWindow as MainWindow)?.ReloadCurrentSection();
    }

    /// <summary>主窗口侧边栏"设置"按钮点击时调用，展示设置面板网页窗口。</summary>
    public static void ShowSettings(MainWindow owner)
    {
        _settingsWindow = new WebPageWindow("settings.html", "设置", 460, 620) { Owner = owner };
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    /// <summary>
    /// 设置面板网页调用 logout 桥接、Python 清完文件之后，NativeBridge 回调这里，
    /// 负责窗口切换。先展示新向导窗口，再关掉旧窗口——顺序不能反过来，中间有一瞬间
    /// 零窗口存在的话，WPF 默认 ShutdownMode（OnLastWindowClose）会让整个应用提前退出，
    /// 新向导窗口就再也弹不出来了。
    /// </summary>
    public static void PerformLogoutTransition()
    {
        _settingsWindow?.Close();
        _settingsWindow = null;
        ShowSetupWizard();
        (Current.MainWindow as MainWindow)?.Close();
        Current.MainWindow = null;
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(
            $"出现了一个没处理的错误，App 可能需要重新启动：\n\n{e.Exception.Message}",
            "CanvasX",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
        e.Handled = true;
    }

    // 登录页"记住我"没勾选（公用电脑场景）：退出时自动清掉这台电脑上的登录信息，
    // 不等用户自己记得去点"退出登录"。没有偏好文件（老版本，或者还没走过新版
    // 向导）时 PrefsStore.Load() 返回的默认值 RememberLogin=true，不会误清。
    // 用同步阻塞版本的 PythonRunner——OnExit 返回之后进程就真的退出了，
    // 没法安全地在这里排一个 await 续体。
    protected override void OnExit(ExitEventArgs e)
    {
        var prefs = PrefsStore.Load();
        if (!prefs.RememberLogin)
        {
            PythonRunner.RunSyncBlocking(new[] { "clear_local_user_data.py" });
        }
        base.OnExit(e);
    }
}
