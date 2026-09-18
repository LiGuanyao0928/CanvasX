using System.Windows;
using System.Windows.Threading;
using CanvasDashboard.Services;
using CanvasDashboard.Views;

namespace CanvasDashboard;

/// <summary>
/// 应用入口，对应 Mac 版 main.swift 里 AppDelegate.applicationDidFinishLaunching：
/// 先确认项目目录能找到、应用主题，再看 .env 是否已经有有效配置——没有就先走设置向导，
/// 有的话直接进主窗口。
/// </summary>
public partial class App : Application
{
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
                "Canvas 作业追踪 - 启动失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(-1);
            return;
        }

        var prefs = PrefsStore.Load();
        ThemeManager.Apply(prefs.Theme);

        if (EnvFile.HasValidConfig())
        {
            var main = new MainWindow();
            MainWindow = main;
            main.Show();
        }
        else
        {
            ShowFreshWizard();
        }
    }

    /// <summary>
    /// 展示一个全新的设置向导，完成后创建全新主窗口。
    /// 供首次启动、以及"退出登录"清空数据后重新引导使用。
    /// </summary>
    public static void ShowFreshWizard()
    {
        var wizard = new SetupWizardWindow();
        wizard.Completed += () =>
        {
            var main = new MainWindow();
            Current.MainWindow = main;
            main.Show();
        };
        wizard.Show();
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(
            $"出现了一个没处理的错误，App 可能需要重新启动：\n\n{e.Exception.Message}",
            "Canvas 作业追踪",
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
