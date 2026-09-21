using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using CanvasDashboard.Services;
using Microsoft.Web.WebView2.Core;

namespace CanvasDashboard;

/// <summary>
/// 主窗口：左侧边栏 + 右侧内容区，对应 Mac 版 main.swift 里 AppDelegate 的
/// showMainWindow / sectionChanged / handleCanvasAppLink 那部分逻辑。
/// </summary>
public partial class MainWindow : Window
{
    private int _currentSection;
    private bool _webViewReady;

    public MainWindow()
    {
        InitializeComponent();
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        await InitializeWebViewAsync();
        NavigateSection(0);
        // 跟 Mac 版一样：主窗口一打开就跑一次后台刷新，刷新完自动重新加载当前页面。
        _ = RefreshDataAsync();
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            await Browser.EnsureCoreWebView2Async();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this,
                "WebView2 初始化失败，通常是因为这台电脑还没装 WebView2 Runtime（新版 Windows 10/11 一般已经" +
                $"随 Edge 自带，缺失的话去微软官网搜 \"WebView2 Runtime\" 下载安装）。\n\n详细信息：{ex.Message}",
                "CanvasX", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        _webViewReady = true;
        // "提醒时间"现在也是网页（schedule.html），跟其它三个板块共用这同一个 WebView2，
        // 所以这里要装桥接（NativeBridge）+ 主题同步（ThemeManager），跟 WebPageWindow
        // 打开设置向导/设置面板时做的事是一样的。
        NativeBridge.Install(Browser.CoreWebView2);
        ThemeManager.RegisterWebView(Browser.CoreWebView2);
        Browser.CoreWebView2.NavigationStarting += CoreWebView2_NavigationStarting;
        Browser.CoreWebView2.NewWindowRequested += CoreWebView2_NewWindowRequested;
    }

    // MARK: - 左侧边栏切换

    private void NavButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not string tagStr || !int.TryParse(tagStr, out var index))
            return;
        NavigateSection(index);
    }

    public void NavigateSection(int index)
    {
        _currentSection = index;
        UpdateSidebarSelection(index);

        // 五个板块现在完全对称——都是"加载不同的静态网页"，跟 Mac 版
        // sectionChanged(_:) 的 switch 语句一一对应。
        var path = index switch
        {
            1 => ProjectPaths.MaterialsHtml,
            2 => ProjectPaths.GradesHtml,
            3 => ProjectPaths.TimetableHtml,
            4 => ProjectPaths.ScheduleHtml,
            _ => ProjectPaths.DashboardHtml,
        };
        LoadPage(path);
    }

    /// <summary>高亮当前选中的侧边栏项目，其余的清成透明——纯视觉反馈，不影响功能。</summary>
    private void UpdateSidebarSelection(int index)
    {
        var buttons = new[] { NavDashboardButton, NavMaterialsButton, NavGradesButton, NavTimetableButton, NavScheduleButton };
        for (var i = 0; i < buttons.Length; i++)
        {
            if (i == index)
                buttons[i].SetResourceReference(BackgroundProperty, "AppSidebarSelectedBrush");
            else
                buttons[i].ClearValue(BackgroundProperty);
        }
    }

    private void LoadPage(string path)
    {
        if (!_webViewReady || Browser.CoreWebView2 == null) return;
        if (!File.Exists(path)) return;
        Browser.CoreWebView2.Navigate(new Uri(path).AbsoluteUri);
    }

    /// <summary>供设置窗口"立即同步"完成后调用：只重新加载当前页面，不再跑一次同步。</summary>
    public void ReloadCurrentSection() => NavigateSection(_currentSection);

    // MARK: - 启动/菜单里的"刷新数据"：跑 canvas_sync.py --refresh，完成后重新加载当前页面

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshDataAsync();

    public async Task RefreshDataAsync()
    {
        var logPath = Path.Combine(ProjectPaths.LogsDir, "app_launch.log");
        try
        {
            await PythonRunner.RunAsync(new[] { "canvas_sync.py", "--refresh" }, logPath);
        }
        catch (Exception ex)
        {
            // 静默失败即可（跟 Mac 版一样只写日志），启动阶段不用弹窗打断用户
            Debug.WriteLine($"refreshData failed: {ex.Message}");
        }
        NavigateSection(_currentSection);
    }

    // MARK: - target="_blank" 的链接（作业详情/提交按钮）用系统默认浏览器打开，不要在 WebView2 里跳转

    private void CoreWebView2_NewWindowRequested(object? sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        try
        {
            Process.Start(new ProcessStartInfo(e.Uri) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"open in browser failed: {ex.Message}");
        }
    }

    // MARK: - 课程资料页的"添加文件"/"删除文件"按钮：canvasapp://add?course_id=X , canvasapp://delete?id=X
    // 这是网页里的假链接，不是真的要跳转，拦下来自己解析处理。

    private void CoreWebView2_NavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (!e.Uri.StartsWith("canvasapp://", StringComparison.OrdinalIgnoreCase))
            return;

        e.Cancel = true;
        HandleCanvasAppLink(e.Uri);
    }

    private void HandleCanvasAppLink(string uri)
    {
        // System.Uri 对自定义 scheme 的 query 解析不可靠，这里手动切：
        // "canvasapp://add?course_id=42466" -> host="add", query="course_id=42466"
        var withoutScheme = uri.Substring("canvasapp://".Length);
        var hostAndQuery = withoutScheme.Split('?', 2);
        var host = hostAndQuery[0].TrimEnd('/');
        var query = hostAndQuery.Length > 1 ? hostAndQuery[1] : "";

        var parameters = new Dictionary<string, string>();
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var kv = pair.Split('=', 2);
            var key = Uri.UnescapeDataString(kv[0]);
            var value = kv.Length > 1 ? Uri.UnescapeDataString(kv[1]) : "";
            parameters[key] = value;
        }

        switch (host)
        {
            case "add":
                if (parameters.TryGetValue("course_id", out var courseId))
                    _ = HandleAddMaterialAsync(courseId);
                break;
            case "delete":
                if (parameters.TryGetValue("id", out var materialId))
                    _ = HandleDeleteMaterialAsync(materialId);
                break;
        }
    }

    private async Task HandleAddMaterialAsync(string courseId)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Multiselect = true,
            Title = "添加到课程资料",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(this) != true) return;

        // 逐个顺序注册，不要并发——并发写 SQLite 之前在 Mac 版上真的导致过
        // "database is locked"。
        foreach (var path in dialog.FileNames)
        {
            try
            {
                await PythonRunner.RunAsync(new[] { "canvas_materials.py", "--register", courseId, path });
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"添加文件失败：{Path.GetFileName(path)}\n\n{ex.Message}",
                    "CanvasX", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        NavigateSection(1);
    }

    private async Task HandleDeleteMaterialAsync(string materialId)
    {
        try
        {
            await PythonRunner.RunAsync(new[] { "canvas_materials.py", "--delete", materialId });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"删除文件失败：{ex.Message}",
                "CanvasX", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        NavigateSection(1);
    }

    // MARK: - 设置窗口（现在是共享网页 settings.html，见 App.ShowSettings）

    private void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        App.ShowSettings(this);
    }
}
