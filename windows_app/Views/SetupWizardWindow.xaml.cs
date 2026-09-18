using System.IO;
using System.Windows;
using System.Windows.Controls;
using CanvasDashboard.Models;
using CanvasDashboard.Services;

namespace CanvasDashboard.Views;

/// <summary>
/// 首次使用引导：连接 Canvas 账号 → 选课程 → (可选)手机推送 → 写配置+首次同步。
/// 对应 Mac 版 SetupWizardWindowController.swift。四步用同一个窗口里四块
/// StackPanel 的显隐切换来实现（Mac 版是动态换整个 NSView，这里图省事、图稳妥
/// 用可见性切换，效果一样）。
///
/// 手机推送只保留 none / ntfy / discord 三选一——苹果快捷指令是 Mac 专属功能，
/// Windows 上没有意义，所以不像 Mac 版那样出现第四个选项。
/// </summary>
public partial class SetupWizardWindow : Window
{
    public event Action? Completed;

    private string _canvasUrl = "";
    private string _canvasToken = "";
    private List<CanvasCourse> _allCourses = new();
    private readonly HashSet<int> _selectedCourseIds = new();
    private readonly List<(int Id, CheckBox Box)> _courseCheckboxes = new();

    private string _notifyMethod = "none";
    private string _ntfyTopic = "";
    private string _discordWebhook = "";
    private TextBox? _ntfyField;
    private TextBox? _discordField;

    public SetupWizardWindow()
    {
        InitializeComponent();
    }

    // MARK: - 第 1 步

    private async void Step1Next_Click(object sender, RoutedEventArgs e)
    {
        var url = UrlBox.Text.Trim();
        var token = TokenBox.Password.Trim();
        if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(token))
        {
            ShowStep1Error("网址和 Token 都要填");
            return;
        }

        Step1Error.Visibility = Visibility.Collapsed;
        Step1Spinner.Visibility = Visibility.Visible;
        Step1NextButton.IsEnabled = false;

        try
        {
            var courses = await CanvasApi.FetchCoursesAsync(url, token);
            _canvasUrl = url;
            _canvasToken = token;
            _allCourses = courses;
            ShowStep2();
        }
        catch (CanvasApiException ex)
        {
            ShowStep1Error($"连接失败：{ex.Message}");
        }
        catch (Exception ex)
        {
            ShowStep1Error($"连接失败：{ex.Message}");
        }
        finally
        {
            Step1Spinner.Visibility = Visibility.Collapsed;
            Step1NextButton.IsEnabled = true;
        }
    }

    private void ShowStep1Error(string message)
    {
        Step1Error.Text = message;
        Step1Error.Visibility = Visibility.Visible;
    }

    // MARK: - 第 2 步

    private void ShowStep2()
    {
        Step1Panel.Visibility = Visibility.Collapsed;
        Step2Panel.Visibility = Visibility.Visible;

        CoursesPanel.Children.Clear();
        _courseCheckboxes.Clear();

        foreach (var course in _allCourses)
        {
            var checkBox = new CheckBox
            {
                Content = course.DisplayName,
                IsChecked = _selectedCourseIds.Contains(course.Id),
                Margin = new Thickness(0, 5, 0, 5),
            };
            CoursesPanel.Children.Add(checkBox);
            _courseCheckboxes.Add((course.Id, checkBox));
        }

        if (_allCourses.Count == 0)
        {
            CoursesPanel.Children.Add(new TextBlock
            {
                Text = "没有拉到课程，返回上一步检查一下网址和 Token",
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 8, 0, 8),
            });
        }
    }

    private void CaptureSelectedCourses()
    {
        _selectedCourseIds.Clear();
        foreach (var (id, box) in _courseCheckboxes)
        {
            if (box.IsChecked == true) _selectedCourseIds.Add(id);
        }
    }

    private void Step2Back_Click(object sender, RoutedEventArgs e)
    {
        CaptureSelectedCourses();
        Step2Panel.Visibility = Visibility.Collapsed;
        Step1Panel.Visibility = Visibility.Visible;
    }

    private void Step2Next_Click(object sender, RoutedEventArgs e)
    {
        CaptureSelectedCourses();
        ShowStep3();
    }

    // MARK: - 第 3 步

    private void ShowStep3()
    {
        Step2Panel.Visibility = Visibility.Collapsed;
        Step3Panel.Visibility = Visibility.Visible;
        UpdateNotifyDetail();
    }

    private void NotifyRadio_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is not RadioButton { Tag: string method }) return;
        _notifyMethod = method;
        UpdateNotifyDetail();
    }

    private void UpdateNotifyDetail()
    {
        NotifyDetailPanel.Children.Clear();
        _ntfyField = null;
        _discordField = null;

        switch (_notifyMethod)
        {
            case "ntfy":
                NotifyDetailPanel.Children.Add(new TextBlock
                {
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 12,
                    Margin = new Thickness(0, 0, 0, 8),
                    Text = "手机 App Store 搜索安装「ntfy」，打开后点右下角 ＋，粘贴下面这个频道名订阅它（频道名相当于一个不公开的密钥，不要告诉别人）：",
                });
                _ntfyField = new TextBox
                {
                    Text = string.IsNullOrEmpty(_ntfyTopic)
                        ? $"canvas-{Random.Shared.Next(100_000, 999_999)}"
                        : _ntfyTopic,
                };
                NotifyDetailPanel.Children.Add(_ntfyField);
                break;

            case "discord":
                NotifyDetailPanel.Children.Add(new TextBlock
                {
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 12,
                    Margin = new Thickness(0, 0, 0, 8),
                    Text = "在你的 Discord 服务器里：频道设置 →「整合」→「Webhook」→「新增 Webhook」，复制生成的网址粘贴到下面（不用邀请机器人，纯网址推送）：",
                });
                _discordField = new TextBox { Text = _discordWebhook };
                NotifyDetailPanel.Children.Add(_discordField);
                break;
        }
    }

    private void Step3Back_Click(object sender, RoutedEventArgs e)
    {
        Step3Panel.Visibility = Visibility.Collapsed;
        Step2Panel.Visibility = Visibility.Visible;
    }

    private async void Step3Finish_Click(object sender, RoutedEventArgs e)
    {
        _ntfyTopic = _ntfyField?.Text.Trim() ?? "";
        _discordWebhook = _discordField?.Text.Trim() ?? "";

        Step3Panel.Visibility = Visibility.Collapsed;
        Step4Panel.Visibility = Visibility.Visible;

        await WriteConfigAndSyncAsync();
    }

    // MARK: - 第 4 步：写配置 + 首次同步

    private async Task WriteConfigAndSyncAsync()
    {
        var env = new List<KeyValuePair<string, string>>
        {
            new("CANVAS_API_TOKEN", _canvasToken),
            new("CANVAS_BASE_URL", _canvasUrl),
            new("NOTIFY_METHOD", _notifyMethod),
        };
        switch (_notifyMethod)
        {
            case "ntfy":
                env.Add(new KeyValuePair<string, string>("NTFY_TOPIC", _ntfyTopic));
                break;
            case "discord":
                env.Add(new KeyValuePair<string, string>("DISCORD_WEBHOOK_URL", _discordWebhook));
                break;
        }

        try
        {
            EnvFile.Write(env);

            var idsText = string.Join(", ", _selectedCourseIds.OrderBy(id => id));
            File.WriteAllText(
                Path.Combine(ProjectPaths.ProjectRoot, "tracked_courses.json"),
                $"{{\"course_ids\": [{idsText}]}}\n");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"写配置文件失败：{ex.Message}", "Canvas 作业追踪",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }

        try
        {
            await PythonRunner.RunAsync(new[] { "canvas_sync.py", "--refresh" });
        }
        catch
        {
            // 首次同步失败也不阻塞流程——跟 Mac 版一样，进主窗口后用户随时能手动刷新重试
        }

        Completed?.Invoke();
        Close();
    }
}
