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
}
