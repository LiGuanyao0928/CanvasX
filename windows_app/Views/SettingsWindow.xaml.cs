using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using CanvasDashboard.Models;
using CanvasDashboard.Services;

namespace CanvasDashboard.Views;

/// <summary>
/// 设置窗口——Mac 版目前还没有这一块（这个 Windows 客户端和 Mac 版的设置窗口是在
/// 同一个会话里并行开发的两份独立实现，功能范围保持一致，代码不共享）。
///
/// 范围：外观（跟随系统/浅色/深色）、语言（只影响这一个窗口自己的文字）、账号
/// （查看网址、重新选课/换 Token、退出登录清空本机数据）、立即同步、打开日志文件夹、关于。
/// </summary>
public partial class SettingsWindow : Window
{
    private AppPrefs _prefs = new();
    private string _lang = "zh";

    public SettingsWindow()
    {
        InitializeComponent();

        _prefs = PrefsStore.Load();
        _lang = _prefs.Language == "en" ? "en" : "zh";

        // 设置初始选中状态——会触发一次 Checked 回调，属于幂等操作，无副作用风险。
        (_prefs.Theme switch
        {
            "light" => ThemeLightRadio,
            "dark" => ThemeDarkRadio,
            _ => ThemeSystemRadio,
        }).IsChecked = true;

        (_lang == "en" ? LangEnRadio : LangZhRadio).IsChecked = true;

        LoadAccountInfo();
        ApplyLocalization();
    }

    private void LoadAccountInfo()
    {
        var env = EnvFile.Load();
        BaseUrlValueText.Text = env.TryGetValue("CANVAS_BASE_URL", out var url) && !string.IsNullOrWhiteSpace(url)
            ? url
            : Loc.T("settings.account.baseurl.empty", _lang);
    }

    private void ApplyLocalization()
    {
        Title = Loc.T("settings.title", _lang);
        WindowTitleLabel.Text = Loc.T("settings.title", _lang);

        AppearanceHeader.Text = Loc.T("settings.section.appearance", _lang);
        ThemeSystemRadio.Content = Loc.T("settings.appearance.system", _lang);
        ThemeLightRadio.Content = Loc.T("settings.appearance.light", _lang);
        ThemeDarkRadio.Content = Loc.T("settings.appearance.dark", _lang);

        LanguageHeader.Text = Loc.T("settings.section.language", _lang);
        LangZhRadio.Content = Loc.T("settings.language.zh", _lang);
        LangEnRadio.Content = Loc.T("settings.language.en", _lang);

        AccountHeader.Text = Loc.T("settings.section.account", _lang);
        BaseUrlLabelText.Text = Loc.T("settings.account.baseurl.label", _lang);
        ReconfigureButton.Content = Loc.T("settings.account.reconfigure", _lang);
        LogoutButton.Content = Loc.T("settings.account.logout", _lang);

        OtherHeader.Text = Loc.T("settings.section.other", _lang);
        SyncNowButton.Content = Loc.T("settings.sync.now", _lang);
        OpenLogsButton.Content = Loc.T("settings.logs.open", _lang);
        CalendarNoteText.Text = Loc.T("settings.calendar.note", _lang);

        AboutHeader.Text = Loc.T("settings.section.about", _lang);
        AboutBodyText.Text = Loc.T("settings.about.body", _lang);

        CloseButton.Content = Loc.T("settings.close", _lang);

        LoadAccountInfo();
    }

    // MARK: - 外观

    private void ThemeRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is not RadioButton { Tag: string theme }) return;
        _prefs.Theme = theme;
        ThemeManager.Apply(theme);
        PrefsStore.Save(_prefs);
    }

    // MARK: - 语言（只影响这个窗口自己的文字）

    private void LanguageRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is not RadioButton { Tag: string lang }) return;
        _lang = lang;
        _prefs.Language = lang;
        PrefsStore.Save(_prefs);
        ApplyLocalization();
    }

    // MARK: - 账号

    private void ReconfigureButton_Click(object sender, RoutedEventArgs e)
    {
        var owner = Owner as MainWindow;
        var wizard = new SetupWizardWindow();
        wizard.Completed += () =>
        {
            _ = owner?.RefreshDataAsync();
            owner?.Activate();
        };
        Close();
        wizard.Show();
    }

    private void LogoutButton_Click(object sender, RoutedEventArgs e)
    {
        var title = Loc.T("settings.account.logout.confirm.title", _lang);
        var body = Loc.T("settings.account.logout.confirm.body", _lang);
        var result = MessageBox.Show(this, body, title, MessageBoxButton.YesNo,
            MessageBoxImage.Warning, MessageBoxResult.No);
        if (result != MessageBoxResult.Yes) return;

        // 文件名单只在 clear_local_user_data.py 里维护一份，Mac/Windows 两边都调
        // 用它，不在这里重复写一份容易漏改的清单。
        PythonRunner.RunSyncBlocking(new[] { "clear_local_user_data.py" });

        // 先展示新向导窗口，再关掉旧窗口——顺序不能反过来：Application 默认的
        // ShutdownMode 是 OnLastWindowClose，如果先把设置+主窗口都关掉，中间会有
        // 一瞬间零窗口存在，可能触发整个应用提前退出，新向导窗口就再也弹不出来了。
        var owner = Owner as MainWindow;
        App.ShowFreshWizard();
        Close();
        owner?.Close();
    }

    // MARK: - 其它

    private async void SyncNowButton_Click(object sender, RoutedEventArgs e)
    {
        SyncNowButton.IsEnabled = false;
        var original = SyncNowButton.Content;
        SyncNowButton.Content = Loc.T("settings.sync.inprogress", _lang);

        try
        {
            await PythonRunner.RunAsync(new[] { "canvas_sync.py", "--refresh" });
            (Owner as MainWindow)?.ReloadCurrentSection();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, Loc.T("settings.sync.failed.title", _lang),
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            SyncNowButton.Content = original;
            SyncNowButton.IsEnabled = true;
        }
    }

    private void OpenLogsButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(ProjectPaths.LogsDir);
            Process.Start(new ProcessStartInfo("explorer.exe", ProjectPaths.LogsDir) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Canvas 作业追踪", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
}
